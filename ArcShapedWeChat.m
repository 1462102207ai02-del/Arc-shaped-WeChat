//
//  ArcShapedWeChat.m
//  Arc-shaped WeChat
//
//  dylib 入口（纯 Objective-C runtime，不依赖 MobileSubstrate / Logos）。
//
//  适配 TrollFools 的三条硬约束：
//   1. 只认裸 .dylib（README 明确写了 .deb/.zip 支持仍是 Milestone），
//      而且对"加密的 App Store 应用"只支持 bare dynamic library —— 微信正是加密应用。
//   2. 注入点是微信包里某个"未加密"的 Mach-O，加载时机不保证，
//      所以所有 hook 都要能容忍目标类晚出现（延迟重试）。
//   3. 微信仍运行在 App 沙盒里，不能写 /var/mobile —— 配置走 App 容器（见 ArcPrefs）。
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

#import "ArcHook.h"
#import "ArcPrefs.h"
#import "ArcStatus.h"
#import "ArcCardEngine.h"
#import "ArcForceRound.h"
#import "ArcTargetClasses.h"
#import "ArcSettingsController.h"

/// 插件在微信「设置 → 插件」列表里的外显名称
#define kArcPluginTitle   @"你啊爸支鼎溜"
#define kArcPluginVersion @"1.2-1"
#define kArcSettingsClass @"ArcShapedWeChatSettingsController"

#pragma mark - 私有 API 声明（仅声明，不实现）

@interface UITableView (ArcPrivate)
- (void)_configureCellForDisplay:(UITableViewCell *)cell forIndexPath:(NSIndexPath *)indexPath;
@end

/// WCPluginsMgr 的注册接口。ARC 下不允许向 id 发送未知 selector，
/// 必须先用协议把方法签名告诉编译器；运行时仍走 NSClassFromString 反射。
@protocol ArcWCPluginsMgrProtocol <NSObject>
+ (instancetype)sharedInstance;
- (void)registerControllerWithTitle:(NSString *)title
                            version:(NSString *)version
                         controller:(NSString *)controller;
@end

#pragma mark - 插件收纳注册

static BOOL gEntryRegistered = NO;

static void ArcRegisterPluginEntry(void) {
    if (gEntryRegistered) { return; }

    ArcStatus *status = [ArcStatus shared];
    status.registerAttempts++;

    Class mgrClass = NSClassFromString(@"WCPluginsMgr");
    status.mgrClassFound = (mgrClass != Nil);
    if (!mgrClass) { return; }

    @try {
        if (![mgrClass respondsToSelector:@selector(sharedInstance)]) {
            status.sharedInstanceOK = NO;
            return;
        }
        id mgr = [mgrClass performSelector:@selector(sharedInstance)];
        status.sharedInstanceOK = (mgr != nil);
        if (!mgr) { return; }

        SEL reg = @selector(registerControllerWithTitle:version:controller:);
        status.registerSelectorOK = [mgr respondsToSelector:reg];
        if (![mgr respondsToSelector:reg]) { return; }

        id<ArcWCPluginsMgrProtocol> registrar = (id<ArcWCPluginsMgrProtocol>)mgr;
        [registrar registerControllerWithTitle:kArcPluginTitle
                                       version:kArcPluginVersion
                                    controller:kArcSettingsClass];
        gEntryRegistered = YES;
        status.registerSucceeded = YES;
    } @catch (NSException *exception) {
        status.registerError = exception.reason ?: @"未知异常";
    }
}

/// TrollFools 的注入时机不保证，WCPluginsMgr 很可能晚于 dylib 才可用。
/// 在注册成功前按递增间隔反复尝试 —— 每次开销仅一次 NSClassFromString + 一次注册。
static void ArcScheduleEntryRegistration(void) {
    static const NSTimeInterval delays[] = {0.5, 1.5, 3.0, 6.0, 12.0, 25.0, 45.0, 75.0};
    for (NSUInteger i = 0; i < sizeof(delays) / sizeof(delays[0]); i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delays[i] * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (gEntryRegistered) { return; }
            ArcRegisterPluginEntry();
        });
    }
}

#pragma mark - UITableViewCell：左右缩进

static IMP gOrigCellSetFrame = NULL;

static void ArcCellSetFrame(UITableViewCell *self, SEL _cmd, CGRect frame) {
    CGRect adjusted = [[ArcCardEngine shared] adjustedFrameForCell:self frame:frame];
    if (gOrigCellSetFrame) {
        ((void (*)(id, SEL, CGRect))gOrigCellSetFrame)(self, _cmd, adjusted);
    }
}

#pragma mark - UITableView：通用 cell 配置入口（私有但覆盖最全）

static IMP gOrigConfigureCell = NULL;

static void ArcConfigureCellForDisplay(UITableView *self, SEL _cmd,
                                       UITableViewCell *cell, NSIndexPath *indexPath) {
    if (gOrigConfigureCell) {
        ((void (*)(id, SEL, UITableViewCell *, NSIndexPath *))gOrigConfigureCell)(self, _cmd, cell, indexPath);
    }
    @try {
        [[ArcCardEngine shared] applyCardToCell:cell tableView:self indexPath:indexPath];
    } @catch (NSException *exception) { }
}

#pragma mark - WCTableViewManager：微信表格构造器

static IMP gOrigManagerWillDisplay = NULL;

static void ArcManagerWillDisplay(id self, SEL _cmd, UITableView *tableView,
                                  UITableViewCell *cell, NSIndexPath *indexPath) {
    if (gOrigManagerWillDisplay) {
        ((void (*)(id, SEL, UITableView *, UITableViewCell *, NSIndexPath *))gOrigManagerWillDisplay)
            (self, _cmd, tableView, cell, indexPath);
    }
    @try {
        [[ArcCardEngine shared] applyCardToCell:cell tableView:tableView indexPath:indexPath];
    } @catch (NSException *exception) { }
}

static IMP gOrigManagerFooterHeight = NULL;

static CGFloat ArcManagerFooterHeight(id self, SEL _cmd, UITableView *tableView, NSInteger section) {
    CGFloat origin = 0;
    if (gOrigManagerFooterHeight) {
        origin = ((CGFloat (*)(id, SEL, UITableView *, NSInteger))gOrigManagerFooterHeight)
                 (self, _cmd, tableView, section);
    }
    if (origin < 0) { return origin; }   // UITableViewAutomaticDimension，原样返回
    return origin + [[ArcCardEngine shared] extraSpacingForFooterInTableView:tableView];
}

#pragma mark - 一级 Tab 页面（自己当 delegate，不走 WCTableViewManager）

#define ARC_DEFINE_WILL_DISPLAY(unique)                                              \
    static IMP gOrigWillDisplay_##unique = NULL;                                      \
    static void ArcWillDisplay_##unique(id self, SEL _cmd, UITableView *tableView,     \
                                        UITableViewCell *cell, NSIndexPath *indexPath) {\
        if (gOrigWillDisplay_##unique) {                                              \
            ((void (*)(id, SEL, UITableView *, UITableViewCell *, NSIndexPath *))      \
             gOrigWillDisplay_##unique)(self, _cmd, tableView, cell, indexPath);       \
        }                                                                             \
        @try { [[ArcCardEngine shared] applyCardToCell:cell                            \
                                            tableView:tableView                        \
                                            indexPath:indexPath]; }                     \
        @catch (NSException *exception) { }                                            \
    }

ARC_DEFINE_WILL_DISPLAY(NewMainFrame)
ARC_DEFINE_WILL_DISPLAY(Contacts)
ARC_DEFINE_WILL_DISPLAY(More)

#pragma mark - 插件入口页

// 关键：注册必须在 %orig **之前**完成。
// 微信插件列表页是在自己的 viewDidLoad 里构建数据源的，
// 如果等 %orig 跑完再注册，这一次打开列表里就不会出现本插件。
#define ARC_DEFINE_ENTRY_VIEWDIDLOAD(unique) \
    static IMP gOrigEntry_##unique = NULL; \
    static void ArcEntryViewDidLoad_##unique(UIViewController *self, SEL _cmd) { \
        ArcRegisterPluginEntry(); \
        if (gOrigEntry_##unique) { ((void (*)(id, SEL))gOrigEntry_##unique)(self, _cmd); } \
    }

ARC_DEFINE_ENTRY_VIEWDIDLOAD(Minimize)
ARC_DEFINE_ENTRY_VIEWDIDLOAD(Plugins)
ARC_DEFINE_ENTRY_VIEWDIDLOAD(SettingPlugins)

#pragma mark - 安装

static BOOL gHooksInstalled = NO;
static NSMutableSet<NSString *> *gHookedClasses = nil;

static void ArcInstallUIKitHooks(void) {
    ArcHookInstance([UITableViewCell class], @selector(setFrame:),
                    (IMP)ArcCellSetFrame, &gOrigCellSetFrame);

    if ([[UITableView class] instancesRespondToSelector:@selector(_configureCellForDisplay:forIndexPath:)]) {
        ArcHookInstance([UITableView class], @selector(_configureCellForDisplay:forIndexPath:),
                        (IMP)ArcConfigureCellForDisplay, &gOrigConfigureCell);
    }
}

static void ArcInstallWeChatHooks(void) {
    if (!gHookedClasses) { gHookedClasses = [NSMutableSet set]; }

    // 微信表格构造器：设置 / 我 / 通用 / 插件 等绝大多数页面
    Class managerClass = NSClassFromString(@"WCTableViewManager");
    if (managerClass && ![gHookedClasses containsObject:@"WCTableViewManager"]) {
        [gHookedClasses addObject:@"WCTableViewManager"];
        ArcHookInstance(managerClass, @selector(tableView:willDisplayCell:forRowAtIndexPath:),
                        (IMP)ArcManagerWillDisplay, &gOrigManagerWillDisplay);
        ArcHookInstance(managerClass, @selector(tableView:heightForFooterInSection:),
                        (IMP)ArcManagerFooterHeight, &gOrigManagerFooterHeight);
        [[ArcStatus shared] noteHookedClass:@"WCTableViewManager"];
    }

    // 一级 Tab
    struct { NSString *name; IMP imp; IMP *slot; } const willDisplayTargets[] = {
        { @"NewMainFrameViewController", (IMP)ArcWillDisplay_NewMainFrame, &gOrigWillDisplay_NewMainFrame },
        { @"ContactsViewController",     (IMP)ArcWillDisplay_Contacts,     &gOrigWillDisplay_Contacts },
        { @"MoreViewController",         (IMP)ArcWillDisplay_More,         &gOrigWillDisplay_More },
    };
    for (NSUInteger i = 0; i < sizeof(willDisplayTargets) / sizeof(willDisplayTargets[0]); i++) {
        NSString *name = willDisplayTargets[i].name;
        if ([gHookedClasses containsObject:name]) { continue; }
        Class cls = NSClassFromString(name);
        if (!cls) { continue; }
        if (![cls instancesRespondToSelector:@selector(tableView:willDisplayCell:forRowAtIndexPath:)]) {
            continue;
        }
        [gHookedClasses addObject:name];
        if (ArcHookInstance(cls, @selector(tableView:willDisplayCell:forRowAtIndexPath:),
                            willDisplayTargets[i].imp, willDisplayTargets[i].slot)) {
            [[ArcStatus shared] noteHookedClass:name];
        }
    }

    // 插件收纳入口：MinimizeViewController（官方声明给的入口）
    // + WCPluginsViewController / SettingPluginsViewController（插件列表页自身，保底）
    // 三者各用独立的原始 IMP 槽位，不能共用。
    struct { NSString *name; IMP imp; IMP *slot; } const pluginEntries[] = {
        { @"MinimizeViewController",       (IMP)ArcEntryViewDidLoad_Minimize,       &gOrigEntry_Minimize },
        { @"WCPluginsViewController",      (IMP)ArcEntryViewDidLoad_Plugins,        &gOrigEntry_Plugins },
        { @"SettingPluginsViewController", (IMP)ArcEntryViewDidLoad_SettingPlugins, &gOrigEntry_SettingPlugins },
    };
    for (NSUInteger i = 0; i < sizeof(pluginEntries) / sizeof(pluginEntries[0]); i++) {
        NSString *name = pluginEntries[i].name;
        if ([gHookedClasses containsObject:name]) { continue; }
        Class cls = NSClassFromString(name);
        if (!cls) { continue; }
        if (![cls instancesRespondToSelector:@selector(viewDidLoad)]) { continue; }
        [gHookedClasses addObject:name];
        if (ArcHookInstance(cls, @selector(viewDidLoad), pluginEntries[i].imp, pluginEntries[i].slot)) {
            [[ArcStatus shared] noteHookedClass:name];
        }
    }

    // 强制圆角（视图类清单）
    [ArcForceRound install];
}

static void ArcInstallAll(void) {
    if (gHooksInstalled) { return; }
    gHooksInstalled = YES;

    ArcInstallUIKitHooks();
    ArcInstallWeChatHooks();

    // TrollFools 的注入点可能是微信包里的某个 framework，加载顺序不保证，
    // 目标类可能还没注册。这里做几次延迟重试把漏掉的补上。
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ ArcInstallWeChatHooks(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ ArcInstallWeChatHooks(); });

    // 插件收纳注册独立于 hook 安装，单独排重试序列（注册失败是最常见的问题）
    ArcScheduleEntryRegistration();
}

#pragma mark - dylib 入口

__attribute__((constructor))
static void ArcShapedWeChatEntry(void) {
    @autoreleasepool {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (![bundleID isEqualToString:@"com.tencent.xin"]) {
            return;   // 只作用于微信主程序
        }

        (void)[ArcPrefs shared];
        (void)[ArcCardEngine shared];

        ArcStatus *status = [ArcStatus shared];
        status.dylibLoaded = YES;

        ArcInstallAll();
        // 先同步注册一次（若 WCPluginsMgr 此刻已可用就能立刻成功），
        // 不成功则由 ArcScheduleEntryRegistration 的延迟序列继续重试。
        ArcRegisterPluginEntry();
    }
}

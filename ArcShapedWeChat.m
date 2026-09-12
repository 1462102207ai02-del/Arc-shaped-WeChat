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
#import "ArcCardEngine.h"
#import "ArcForceRound.h"
#import "ArcTargetClasses.h"
#import "ArcSettingsController.h"

#define kArcPluginTitle   @"Arc-shaped WeChat"
#define kArcPluginVersion @"1.1-1"
#define kArcSettingsClass @"ArcShapedWeChatSettingsController"

#pragma mark - 私有 API 声明（仅声明，不实现）

@interface UITableView (ArcPrivate)
- (void)_configureCellForDisplay:(UITableViewCell *)cell forIndexPath:(NSIndexPath *)indexPath;
@end

/// WCPluginsMgr 的注册接口。ARC 下不允许向 id 发送未知 selector，
/// 必须先用协议把方法签名告诉编译器；运行时仍走 NSClassFromString 反射。
@protocol ArcWCPluginsMgrProtocol <NSObject>
- (void)registerControllerWithTitle:(NSString *)title
                            version:(NSString *)version
                         controller:(NSString *)controller;
@end

#pragma mark - 插件收纳注册

static BOOL gEntryRegistered = NO;

static void ArcRegisterPluginEntry(void) {
    if (gEntryRegistered) { return; }
    Class mgrClass = NSClassFromString(@"WCPluginsMgr");
    if (!mgrClass) { return; }
    @try {
        id mgr = [mgrClass respondsToSelector:@selector(sharedInstance)]
               ? [mgrClass performSelector:@selector(sharedInstance)] : nil;
        if (!mgr) { return; }
        SEL reg = @selector(registerControllerWithTitle:version:controller:);
        if (![mgr respondsToSelector:reg]) { return; }
        id<ArcWCPluginsMgrProtocol> registrar = (id<ArcWCPluginsMgrProtocol>)mgr;
        [registrar registerControllerWithTitle:kArcPluginTitle
                                       version:kArcPluginVersion
                                    controller:kArcSettingsClass];
        gEntryRegistered = YES;
    } @catch (NSException *exception) {
        // 注册失败绝不能让微信崩，静默跳过
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

static IMP gOrigMinimizeViewDidLoad = NULL;
static void ArcMinimizeViewDidLoad(UIViewController *self, SEL _cmd) {
    if (gOrigMinimizeViewDidLoad) {
        ((void (*)(id, SEL))gOrigMinimizeViewDidLoad)(self, _cmd);
    }
    ArcRegisterPluginEntry();
}

static IMP gOrigPluginsViewDidLoad = NULL;
static void ArcPluginsViewDidLoad(UIViewController *self, SEL _cmd) {
    if (gOrigPluginsViewDidLoad) {
        ((void (*)(id, SEL))gOrigPluginsViewDidLoad)(self, _cmd);
    }
    ArcRegisterPluginEntry();
}

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
        ArcHookInstance(cls, @selector(tableView:willDisplayCell:forRowAtIndexPath:),
                        willDisplayTargets[i].imp, willDisplayTargets[i].slot);
    }

    // 插件收纳入口
    Class minimizeClass = NSClassFromString(@"MinimizeViewController");
    if (minimizeClass && ![gHookedClasses containsObject:@"MinimizeViewController"]) {
        [gHookedClasses addObject:@"MinimizeViewController"];
        ArcHookInstance(minimizeClass, @selector(viewDidLoad),
                        (IMP)ArcMinimizeViewDidLoad, &gOrigMinimizeViewDidLoad);
    }
    Class pluginsClass = NSClassFromString(@"WCPluginsViewController");
    if (pluginsClass && ![gHookedClasses containsObject:@"WCPluginsViewController"]) {
        [gHookedClasses addObject:@"WCPluginsViewController"];
        ArcHookInstance(pluginsClass, @selector(viewDidLoad),
                        (IMP)ArcPluginsViewDidLoad, &gOrigPluginsViewDidLoad);
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
                   dispatch_get_main_queue(), ^{ ArcInstallWeChatHooks(); ArcRegisterPluginEntry(); });
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

        ArcInstallAll();
        ArcRegisterPluginEntry();
    }
}

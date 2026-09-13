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
#import "ArcBannerRound.h"
#import "ArcTargetClasses.h"
#import "ArcSettingsController.h"

/// 插件在微信「设置 → 插件」列表里的外显名称
#define kArcPluginTitle   @"你啊爸支鼎溜"
#define kArcPluginVersion @"1.9-4"
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

/// 复查本插件是否还在 WCPluginsMgr.plugins 里。
/// 微信自身的初始化流程可能在启动中期重建 sharedInstance 的 _plugins 数组，
/// 把早期注册进去的条目静默冲掉 —— 参考成熟实现（WBRound）从不在启动早期
/// 注册、只在页面出现时注册，正是为了躲开这个时序。这里反过来做：
/// 允许早期注册，但每次触发都复查，条目丢了就自动补注册。
static BOOL ArcEntryStillListed(id mgr) {
    @try {
        id plugins = nil;
        @try { plugins = [mgr valueForKey:@"plugins"]; } @catch (NSException *e) { return NO; }
        if (![plugins isKindOfClass:[NSArray class]]) { return NO; }
        for (id item in plugins) {
            // 不猜条目的具体结构（字典/模型都有可能），直接扫描述串，
            // 只要外显名或控制器类名出现在里面就算还在。
            NSString *desc = [NSString stringWithFormat:@"%@", item];
            if ([desc containsString:kArcPluginTitle] ||
                [desc containsString:kArcSettingsClass]) { return YES; }
        }
    } @catch (NSException *e) { return NO; }
    return NO;
}

static void ArcRegisterPluginEntry(void) {
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

        // 已注册过 → 每次触发都复查一遍列表；条目被微信重建冲掉时自动补注册
        if (gEntryRegistered) {
            if (ArcEntryStillListed(mgr)) { return; }
            gEntryRegistered = NO;
            status.registerSucceeded = NO;
        }

        SEL reg = @selector(registerControllerWithTitle:version:controller:);
        status.registerSelectorOK = [mgr respondsToSelector:reg];
        if (![mgr respondsToSelector:reg]) { return; }

        id<ArcWCPluginsMgrProtocol> registrar = (id<ArcWCPluginsMgrProtocol>)mgr;
        [registrar registerControllerWithTitle:kArcPluginTitle
                                       version:kArcPluginVersion
                                    controller:kArcSettingsClass];
        gEntryRegistered = YES;
        status.registerSucceeded = YES;
        NSLog(@"[ArcShapedWeChat] WCPluginsMgr entry registered: %@ (v%@)",
              kArcPluginTitle, kArcPluginVersion);
    } @catch (NSException *exception) {
        status.registerError = exception.reason ?: @"未知异常";
        NSLog(@"[ArcShapedWeChat] register error: %@", status.registerError);
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

#pragma mark - 设置页第二入口（页脚按钮，参考 WBRound WBInstallFooter）

// WCPluginsMgr 注册之外，保底一条不依赖微信私有 API 的入口：
// 在设置根页表格尾部插一个按钮，直接 push 我们的设置页。
// 这样即使 WCPluginsMgr 注册失败或被微信冲掉，用户也永远进得来。
static UIViewController *ArcHostViewController(UIView *view) {
    UIResponder *r = view;
    while (r) {
        if ([r isKindOfClass:[UIViewController class]]) { return (UIViewController *)r; }
        r = r.nextResponder;
    }
    return nil;
}

@interface ArcEntryOpener : NSObject
- (void)arcOpen:(UIButton *)sender;
@end

@implementation ArcEntryOpener
- (void)arcOpen:(UIButton *)sender {
    UIViewController *host = ArcHostViewController(sender);
    if (!host || !host.navigationController) { return; }
    @try {
        Class cls = NSClassFromString(kArcSettingsClass);
        if (!cls) { return; }
        for (UIViewController *vc in host.navigationController.viewControllers) {
            if ([vc isKindOfClass:cls]) { return; }   // 已在栈里，不重复推
        }
        UIViewController *settings = [[cls alloc] init];
        [host.navigationController pushViewController:settings animated:YES];
    } @catch (NSException *e) { }
}
@end

static void ArcInstallEntryExtras(UIViewController *vc) {
    @try {
        if (![vc isKindOfClass:[UIViewController class]]) { return; }
        if (!vc.isViewLoaded || !vc.view) { return; }

        UITableView *tv = nil;
        if ([vc respondsToSelector:@selector(tableView)]) {
            id t = nil;
            @try { t = [vc valueForKey:@"tableView"]; } @catch (NSException *e) { t = nil; }
            if ([t isKindOfClass:[UITableView class]]) { tv = t; }
        }
        if (!tv) {
            for (UIView *sub in vc.view.subviews) {
                if ([sub isKindOfClass:[UITableView class]]) { tv = (UITableView *)sub; break; }
            }
        }
        if (!tv || tv.tableFooterView) { return; }

        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        [btn setTitle:kArcPluginTitle forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor colorWithRed:0.07 green:0.79 blue:0.57 alpha:1.0]
                  forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightMedium];
        [btn addTarget:[ArcEntryOpener new] action:@selector(arcOpen:)
       forControlEvents:UIControlEventTouchUpInside];
        UIView *wrap = [[UIView alloc] initWithFrame:
                        CGRectMake(0, 0, UIScreen.mainScreen.bounds.size.width, 54.0)];
        btn.frame = wrap.bounds;
        btn.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [wrap addSubview:btn];
        tv.tableFooterView = wrap;
    } @catch (NSException *e) { }
}

#pragma mark - 插件入口触发点（页面驱动，全部参考 WBRound 的挂法）

// 注册时机策略（对齐参考实现的加载环境适配）：
//   1. 绝不在启动早期（ctor / DidFinishLaunching 之前）注册 —— 微信初始化
//      中途可能重建 WCPluginsMgr 的 _plugins 数组，早期注册会被静默冲掉；
//      且 TrollFools 注入点加载时机不保证，提前触碰微信单例风险大。
//   2. 注册由"页面出现"驱动，均在 %orig 之后执行，幂等 + 自动补注册：
//      设置根页(NewSettingViewController) / 我页(MoreViewController) 的
//      viewWillAppear，浮窗页(MinimizeViewController) 的 viewDidLoad。
//   3. 唯一例外：插件列表页(WCPluginsViewController) 在 %orig 之前注册 ——
//      它的 initData 会立刻读取 mgr.plugins 建数据源，深链打开时必须抢在前头。
#define ARC_DEFINE_ENTRY_VIEWDIDLOAD(unique) \
    static IMP gOrigEntry_##unique = NULL; \
    static void ArcEntryViewDidLoad_##unique(UIViewController *self, SEL _cmd) { \
        if (gOrigEntry_##unique) { ((void (*)(id, SEL))gOrigEntry_##unique)(self, _cmd); } \
        ArcRegisterPluginEntry(); \
    }

#define ARC_DEFINE_ENTRY_VIEWDIDLOAD_BEFORE(unique) \
    static IMP gOrigEntryB_##unique = NULL; \
    static void ArcEntryViewDidLoadBefore_##unique(UIViewController *self, SEL _cmd) { \
        ArcRegisterPluginEntry(); \
        if (gOrigEntryB_##unique) { ((void (*)(id, SEL))gOrigEntryB_##unique)(self, _cmd); } \
    }

#define ARC_DEFINE_ENTRY_VIEWWILLAPPEAR(unique) \
    static IMP gOrigEntryWLA_##unique = NULL; \
    static void ArcEntryViewWillAppear_##unique(UIViewController *self, SEL _cmd, BOOL animated) { \
        if (gOrigEntryWLA_##unique) { \
            ((void (*)(id, SEL, BOOL))gOrigEntryWLA_##unique)(self, _cmd, animated); \
        } \
        ArcRegisterPluginEntry(); \
    }

#define ARC_DEFINE_ENTRY_VIEWWILLAPPEAR_EXTRAS(unique) \
    static IMP gOrigEntryWLA_##unique = NULL; \
    static void ArcEntryViewWillAppear_##unique(UIViewController *self, SEL _cmd, BOOL animated) { \
        if (gOrigEntryWLA_##unique) { \
            ((void (*)(id, SEL, BOOL))gOrigEntryWLA_##unique)(self, _cmd, animated); \
        } \
        ArcRegisterPluginEntry(); \
        ArcInstallEntryExtras(self); \
    }

ARC_DEFINE_ENTRY_VIEWWILLAPPEAR_EXTRAS(NewSetting)  // 设置根页：注册 + 页脚按钮入口
ARC_DEFINE_ENTRY_VIEWWILLAPPEAR(More)               // 我页：仅注册（不加页脚，避免挤动该页布局）
ARC_DEFINE_ENTRY_VIEWDIDLOAD(Minimize)              // 参考 WBRound 同款触发点（幂等，无害）
ARC_DEFINE_ENTRY_VIEWDIDLOAD_BEFORE(Plugins)        // 插件列表页：initData 前注册（深链保底）

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

    // 插件收纳触发点（参考 WBRound 的页面驱动注册）：
    //   NewSettingViewController.viewWillAppear  — 设置根页，主入口 + 页脚按钮/双指轻点
    //   MoreViewController.viewWillAppear        — 我页，注册 + 双指轻点
    //   MinimizeViewController.viewDidLoad       — 参考 WBRound 同款触发点
    //   WCPluginsViewController.viewDidLoad      — 插件列表页深链保底（%orig 之前）
    // 每个 VC 用各自独立的 IMP 槽位 + 不同 hook 方法，不能共用。
    struct { NSString *name; SEL sel; IMP imp; IMP *slot; } const pluginEntries[] = {
        { @"NewSettingViewController", @selector(viewWillAppear:), (IMP)ArcEntryViewWillAppear_NewSetting, (IMP *)&gOrigEntryWLA_NewSetting },
        { @"MoreViewController",       @selector(viewWillAppear:), (IMP)ArcEntryViewWillAppear_More,       (IMP *)&gOrigEntryWLA_More },
        { @"MinimizeViewController",   @selector(viewDidLoad),     (IMP)ArcEntryViewDidLoad_Minimize,      &gOrigEntry_Minimize },
        { @"WCPluginsViewController",  @selector(viewDidLoad),     (IMP)ArcEntryViewDidLoadBefore_Plugins, &gOrigEntryB_Plugins },
    };
    for (NSUInteger i = 0; i < sizeof(pluginEntries) / sizeof(pluginEntries[0]); i++) {
        NSString *name = pluginEntries[i].name;
        if ([gHookedClasses containsObject:name]) { continue; }
        Class cls = NSClassFromString(name);
        if (!cls) { continue; }
        if (![cls instancesRespondToSelector:pluginEntries[i].sel]) { continue; }
        [gHookedClasses addObject:name];
        if (ArcHookInstance(cls, pluginEntries[i].sel, pluginEntries[i].imp, pluginEntries[i].slot)) {
            [[ArcStatus shared] noteHookedClass:name];
        }
    }

    // 强制圆角（视图类清单）
    [ArcForceRound install];

    // 横幅（折叠置顶聊天面板 + 第三方登录卡片）
    [ArcBannerRound install];
}

static void ArcInstallAll(void) {
    if (gHooksInstalled) { return; }
    gHooksInstalled = YES;

    ArcInstallUIKitHooks();
    ArcInstallWeChatHooks();

    // GoLive 之后仍可能有微信类晚注册，补两轮
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ ArcInstallWeChatHooks(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ ArcInstallWeChatHooks(); ArcRegisterPluginEntry(); });
}

#pragma mark - dylib 入口

// 生效开关：hook 安装 + 首次注册统一推迟到这里。
// 参考成熟实现（WBRound v1.1.13 注释）的经验：注入的 dylib 若在启动期就
// 开始改视图，会撞上微信首屏布局风暴（主线程跑满 → watchdog 杀进程）；
// 而 WCPluginsMgr 的登记簿也可能在微信自身初始化中途被重建。
// 所以 ctor 只做零风险初始化，生效动作全部推迟到启动完成之后。
static void ArcGoLive(void) {
    static BOOL live = NO;
    if (live) { return; }
    live = YES;

    (void)[ArcCardEngine shared];
    ArcInstallAll();
    ArcRegisterPluginEntry();
    NSLog(@"[ArcShapedWeChat] go live (v%@), hooks=%lu",
          kArcPluginVersion, (unsigned long)[ArcStatus shared].hookCount);
}

__attribute__((constructor))
static void ArcShapedWeChatEntry(void) {
    @autoreleasepool {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
        if (![bundleID isEqualToString:@"com.tencent.xin"]) {
            return;   // 只作用于微信主程序
        }

        (void)[ArcPrefs shared];   // 只读偏好，安全
        ArcStatus *status = [ArcStatus shared];
        status.dylibLoaded = YES;
        NSLog(@"[ArcShapedWeChat] dylib ctor loaded (v%@)", kArcPluginVersion);

        // TrollFools 注入点加载时机不保证，ctor 可能早于 UIApplicationMain。
        // 正常路径：监听启动完成通知，再延 3.5s 生效（给微信首屏留够时间）。
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidFinishLaunchingNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ ArcGoLive(); });
        }];
        // 兜底：没收到启动通知（注入点加载过晚/非标准启动流程）时 8s 强制生效
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ ArcGoLive(); });

        // 启动后的补注册序列：万一设置页一直没打开、注册又被冲掉，仍有机会补上
        static const NSTimeInterval delays[] = {12.0, 25.0, 45.0, 75.0};
        for (NSUInteger i = 0; i < sizeof(delays) / sizeof(delays[0]); i++) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delays[i] * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ ArcRegisterPluginEntry(); });
        }
    }
}

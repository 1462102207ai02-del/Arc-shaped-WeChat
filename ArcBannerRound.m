//
//  ArcBannerRound.m
//  Arc-shaped WeChat
//
//  横幅引擎实现。
//

#import "ArcBannerRound.h"
#import "ArcPrefs.h"
#import "ArcHook.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

// 用于关联原值快照：关闭总开关 / 该横幅被单独关闭时彻底还原
static const char kArcBannerOrigRadiusKey = 'a';
static const char kArcBannerOrigMasksKey  = 'b';
static const char kArcBannerOrigFrameXKey = 'c';
static const char kArcBannerOrigFrameWKey = 'd';

/// 横幅视图清单
///   - MultiDeviceCardLoginContentView : 第三方登录卡片（多设备扫码登录确认）
///   - MainFrameAggregationViewController.tableContainerView : 折叠置顶聊天的展开面板
static NSString *const kArcBannerViewClasses[] = {
    @"MultiDeviceCardLoginContentView",
};
static const NSUInteger kArcBannerViewClassCount =
    sizeof(kArcBannerViewClasses) / sizeof(kArcBannerViewClasses[0]);

/// 折叠置顶聊天的展开面板：特殊处理 — 不是 UIView 类，而是 MMUIViewController，
/// 我们 hook 它的 viewDidLayoutSubviews，再用 KVC 拿 tableContainerView。
static NSString *const kArcBannerPanelController = @"MainFrameAggregationViewController";

@interface ArcBannerRound ()
- (BOOL)isMasterEnabled;
- (CGFloat)radius;
- (CGFloat)horizontalInset;
- (void)applyToView:(UIView *)view;
@end

@implementation ArcBannerRound

+ (instancetype)shared {
    static ArcBannerRound *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [[ArcBannerRound alloc] init]; });
    return instance;
}

- (BOOL)isMasterEnabled {
    ArcPrefs *p = [ArcPrefs shared];
    return p.enabled && p.bannerEnabled;
}

- (CGFloat)radius { return [ArcPrefs shared].bannerRadius; }
- (CGFloat)horizontalInset { return [ArcPrefs shared].bannerInsetH; }

#pragma mark - 单个视图：圆角 + 水平缩进

- (void)snapshotIfNeeded:(UIView *)view {
    if (objc_getAssociatedObject(view, &kArcBannerOrigRadiusKey)) { return; }
    objc_setAssociatedObject(view, &kArcBannerOrigRadiusKey,
                             @(view.layer.cornerRadius),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kArcBannerOrigMasksKey,
                             @(view.layer.masksToBounds),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kArcBannerOrigFrameXKey,
                             @(view.frame.origin.x),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kArcBannerOrigFrameWKey,
                             @(view.frame.size.width),
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)restore:(UIView *)view {
    NSNumber *r = objc_getAssociatedObject(view, &kArcBannerOrigRadiusKey);
    if (!r) { return; }   // 从没改过
    view.layer.cornerRadius = [r doubleValue];
    NSNumber *m = objc_getAssociatedObject(view, &kArcBannerOrigMasksKey);
    view.layer.masksToBounds = m ? [m boolValue] : NO;

    CGRect f = view.frame;
    NSNumber *ox = objc_getAssociatedObject(view, &kArcBannerOrigFrameXKey);
    NSNumber *ow = objc_getAssociatedObject(view, &kArcBannerOrigFrameWKey);
    if (ox && ow) {
        f.origin.x = [ox doubleValue];
        f.size.width = [ow doubleValue];
        view.frame = f;
    }

    objc_setAssociatedObject(view, &kArcBannerOrigRadiusKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kArcBannerOrigMasksKey,  nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kArcBannerOrigFrameXKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kArcBannerOrigFrameWKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)applyToView:(UIView *)view {
    if (![view isKindOfClass:[UIView class]]) { return; }
    if (![self isMasterEnabled]) { [self restore:view]; return; }

    [self snapshotIfNeeded:view];

    CGRect f = view.frame;
    if (f.size.width < 1.0 || f.size.height < 1.0) { return; }

    // 1. 圆角
    CGFloat r = [self radius];
    if (r > 0) {
        CGFloat limit = MIN(f.size.width, f.size.height) / 2.0;
        view.layer.cornerRadius = MAX(0, MIN(r, limit));
        view.layer.masksToBounds = YES;
    }

    // 2. 水平缩进（仅对 top-level 容器类生效；避免和 cell 内部子视图打架）
    CGFloat inset = [self horizontalInset];
    if (inset > 0) {
        UIView *parent = view.superview;
        if (parent) {
            CGRect pb = parent.bounds;
            CGFloat newX = pb.origin.x + inset;
            CGFloat newW = pb.size.width - 2.0 * inset;
            // 父视图宽度太小就别缩，避免被压扁
            if (newW < 60.0) { return; }
            if (fabs(f.origin.x - newX) > 0.5 || fabs(f.size.width - newW) > 0.5) {
                f.origin.x = newX;
                f.size.width = newW;
                view.frame = f;
            }
        }
    }
}

#pragma mark - 安装 hook

+ (void)install {
    static NSMutableSet<NSString *> *installed = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ installed = [NSMutableSet set]; });

    // (1) 直接 hook UIView 子类的 layoutSubviews
    for (NSUInteger i = 0; i < kArcBannerViewClassCount; i++) {
        NSString *name = kArcBannerViewClasses[i];
        if ([installed containsObject:name]) { continue; }
        Class cls = NSClassFromString(name);
        if (!cls) { continue; }

        Method method = class_getInstanceMethod(cls, @selector(layoutSubviews));
        if (!method) { continue; }

        IMP original = method_getImplementation(method);
        SEL selector = @selector(layoutSubviews);

        IMP replacement = imp_implementationWithBlock(^(UIView *view) {
            @try {
                if (original) { ((void (*)(id, SEL))original)(view, selector); }
            } @catch (NSException *e) { }
            @try {
                [[ArcBannerRound shared] applyToView:view];
            } @catch (NSException *e) { }
        });

        const char *types = method_getTypeEncoding(method) ?: "v8@0:4";
        if (!class_addMethod(cls, selector, replacement, types)) {
            method_setImplementation(method, replacement);
        }
        [installed addObject:name];
        [[ArcStatus shared] noteHookedClass:name];
    }

    // (2) 折叠置顶聊天的展开面板：hook VC 的 viewDidLayoutSubviews，
    //     从 KVC 拿私有 tableContainerView 后应用圆角 + 缩进。
    if (![installed containsObject:kArcBannerPanelController]) {
        Class cls = NSClassFromString(kArcBannerPanelController);
        if (cls) {
            Method method = class_getInstanceMethod(cls, @selector(viewDidLayoutSubviews));
            if (method) {
                IMP original = method_getImplementation(method);
                SEL selector = @selector(viewDidLayoutSubviews);

                IMP replacement = imp_implementationWithBlock(^(UIViewController *vc) {
                    @try {
                        if (original) { ((void (*)(id, SEL))original)(vc, selector); }
                    } @catch (NSException *e) { }
                    @try {
                        UIView *panel = nil;
                        @try { panel = [vc valueForKey:@"tableContainerView"]; }
                        @catch (NSException *e) { panel = nil; }
                        if ([panel isKindOfClass:[UIView class]]) {
                            [[ArcBannerRound shared] applyToView:panel];
                        }
                    } @catch (NSException *e) { }
                });

                const char *types = method_getTypeEncoding(method) ?: "v8@0:4";
                if (!class_addMethod(cls, selector, replacement, types)) {
                    method_setImplementation(method, replacement);
                }
                [installed addObject:kArcBannerPanelController];
                [[ArcStatus shared] noteHookedClass:kArcBannerPanelController];
            }
        }
    }
}

@end
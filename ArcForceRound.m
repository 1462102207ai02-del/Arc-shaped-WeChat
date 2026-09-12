//
//  ArcForceRound.m
//  Arc-shaped WeChat
//
//  用 imp_implementationWithBlock 为每个目标类生成独立的 layoutSubviews 替换实现，
//  这样"原始 IMP"和"圆角类别"可以按类捕获进 block，不需要为每个类手写宏。
//  好处是目标类清单可以完全数据驱动（来自 ArcTargetClasses.h），加一个类只改一处。
//

#import "ArcForceRound.h"
#import "ArcPrefs.h"
#import "ArcClassConfig.h"
#import "ArcTargetClasses.h"
#import "ArcHook.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

static char kArcRoundSignatureKey;
static char kArcRoundBgKey;

/// 已经被卡片引擎接管背景的 cell，不再叠加 layer 圆角，避免二次裁剪
static BOOL ArcIsCardedCell(UIView *view) {
    if (![view isKindOfClass:[UITableViewCell class]]) { return NO; }
    UIView *bg = ((UITableViewCell *)view).backgroundView;
    return bg && [NSStringFromClass([bg class]) isEqualToString:@"ArcCardBackgroundView"];
}

@interface ArcForceRound ()
- (CGFloat)radiusForKind:(ArcRoundKind)kind
                    size:(CGSize)size
                  config:(nullable ArcClassConfig *)cfg;
@end

@implementation ArcForceRound

+ (instancetype)shared {
    static ArcForceRound *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ArcForceRound alloc] init];
    });
    return instance;
}

+ (void)install {
    // 刻意不用 dispatch_once：TrollFools 注入点加载时机不确定，
    // 目标类可能晚于 dylib 才注册，install 需要能被反复调用补齐。
    static NSMutableSet<NSString *> *installed = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ installed = [NSMutableSet set]; });

    struct { NSString *const *list; NSUInteger count; ArcRoundKind kind; } groups[] = {
        { kArcForceRoundClasses,     kArcForceRoundClassCount,     ArcRoundKindAvatar },
        { kArcForceRoundCellClasses, kArcForceRoundCellClassCount, ArcRoundKindSettingCell },
        { kArcForceRoundTableClasses,kArcForceRoundTableClassCount,ArcRoundKindTableView },
    };

    // 说明：清单里 [A] 组各类对应不同圆角类别，上面只给了三个数组，
    // 这里再按类名做一次精确映射，保证每个类拿到自己的类别。
    NSDictionary<NSString *, NSNumber *> *kindByName = @{
        @"MMHeadImageView":      @(ArcRoundKindAvatar),
        @"MMWebImageView":       @(ArcRoundKindImageView),
        @"WCImageView":          @(ArcRoundKindImageView),
        @"MMImageGridView":      @(ArcRoundKindImageGrid),
        @"MMUIButton":           @(ArcRoundKindButton),
        @"MMTransparentButton":  @(ArcRoundKindButton),
        @"MMUIView":             @(ArcRoundKindContainer),
        @"ColorGradientView":    @(ArcRoundKindContainer),
        @"MMTableViewCell":      @(ArcRoundKindSettingCell),
        @"SettingCell":          @(ArcRoundKindSettingCell),
        @"MMTableView":          @(ArcRoundKindTableView),
    };

    for (NSUInteger g = 0; g < sizeof(groups) / sizeof(groups[0]); g++) {
        for (NSUInteger i = 0; i < groups[g].count; i++) {
            NSString *name = groups[g].list[i];
            if ([installed containsObject:name]) { continue; }

            Class cls = NSClassFromString(name);
            if (!cls) { continue; }

            Method method = class_getInstanceMethod(cls, @selector(layoutSubviews));
            if (!method) { continue; }

            NSNumber *kindNumber = kindByName[name];
            ArcRoundKind kind = kindNumber ? (ArcRoundKind)kindNumber.unsignedIntegerValue : groups[g].kind;
            IMP original = method_getImplementation(method);
            SEL selector = @selector(layoutSubviews);

            IMP replacement = imp_implementationWithBlock(^(UIView *_Nonnull view) {
                @try {
                    if (original) { ((void (*)(id, SEL))original)(view, selector); }
                } @catch (NSException *exception) { }
                @try {
                    [[ArcForceRound shared] applyToView:view kind:kind];
                } @catch (NSException *exception) { }
            });

            const char *types = method_getTypeEncoding(method) ?: "v8@0:4";
            if (!class_addMethod(cls, selector, replacement, types)) {
                method_setImplementation(method, replacement);
            }
            [installed addObject:name];
        }
    }
}

- (BOOL)enabledForKind:(ArcRoundKind)kind {
    ArcPrefs *prefs = [ArcPrefs shared];
    if (!prefs.forceRoundEnabled) { return NO; }
    switch (kind) {
        case ArcRoundKindAvatar:      return prefs.roundAvatar;
        case ArcRoundKindImageView:   return prefs.roundImageView;
        case ArcRoundKindImageGrid:   return prefs.roundImageGrid;
        case ArcRoundKindButton:      return prefs.roundButton;
        case ArcRoundKindContainer:   return prefs.roundContainer;
        case ArcRoundKindSettingCell: return prefs.roundSettingCell;
        case ArcRoundKindTableView:   return prefs.roundTableView;
    }
    return NO;
}

- (CGFloat)radiusForKind:(ArcRoundKind)kind
                    size:(CGSize)size
                  config:(nullable ArcClassConfig *)cfg {
    ArcPrefs *prefs = [ArcPrefs shared];
    CGFloat radius = 0;

    // 视图类允许「强制正圆」单独开在类上
    BOOL circle = (kind == ArcRoundKindAvatar) && prefs.avatarCircle;
    if (cfg && cfg.hasForceCircle && cfg.forceCircle) { circle = YES; }

    switch (kind) {
        case ArcRoundKindAvatar:
            radius = circle ? MIN(size.width, size.height) / 2.0 : prefs.avatarRadius;
            break;
        case ArcRoundKindImageView:   radius = prefs.imageViewRadius; break;
        case ArcRoundKindImageGrid:   radius = prefs.imageGridRadius; break;
        case ArcRoundKindButton:      radius = prefs.buttonRadius; break;
        case ArcRoundKindContainer:   radius = prefs.containerRadius; break;
        case ArcRoundKindSettingCell: radius = prefs.settingCellRadius; break;
        case ArcRoundKindTableView:   radius = prefs.tableViewRadius; break;
    }

    // 类级圆角覆盖全局（正圆开关优先于半径）
    if (cfg && cfg.hasCornerRadius && !circle) { radius = cfg.cornerRadius; }

    CGFloat limit = MIN(size.width, size.height) / 2.0;
    return MAX(0, MIN(radius, limit));
}

- (void)applyToView:(UIView *)view kind:(ArcRoundKind)kind {
    if (!view || ![view isKindOfClass:[UIView class]]) { return; }

    // 按类配置优先：显式关闭则跳过；显式开启则绕过总开关
    ArcClassConfig *cfg = [[ArcClassConfigStore shared] configResolvingSuperclassForClass:[view class]];
    if (cfg.isExplicitlyDisabled) { return; }
    if (!cfg.isExplicitlyEnabled && ![self enabledForKind:kind]) { return; }

    CGSize size = view.bounds.size;
    if (size.width < 1.0 || size.height < 1.0) { return; }

    // 容器类（MMUIView / ColorGradientView）在微信里到处都是，
    // 太小的元素加圆角 + 裁剪容易把内容切坏，这里设一个下限
    if (kind == ArcRoundKindContainer && (size.width < 40.0 || size.height < 40.0)) {
        return;
    }
    if (kind == ArcRoundKindSettingCell && ArcIsCardedCell(view)) {
        return;
    }

    // 类级背景色（先于圆角处理，保证 radius=0 时也能上色）
    if (cfg.hasBackgroundColor) {
        NSString *hex = ArcColorHexString(cfg.backgroundColor);
        NSString *applied = objc_getAssociatedObject(view, &kArcRoundBgKey);
        if (![applied isEqualToString:hex]) {
            view.backgroundColor = cfg.backgroundColor;
            objc_setAssociatedObject(view, &kArcRoundBgKey, hex, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }

    CGFloat radius = [self radiusForKind:kind size:size config:cfg];
    if (radius <= 0.05) { return; }

    NSString *signature = [NSString stringWithFormat:@"%.2f|%.1f|%.1f", radius, size.width, size.height];
    NSString *applied = objc_getAssociatedObject(view, &kArcRoundSignatureKey);
    if (applied && [applied isEqualToString:signature]) { return; }

    CALayer *layer = view.layer;
    layer.masksToBounds = YES;
    layer.cornerRadius = radius;
    if ([ArcPrefs shared].continuousCorner) {
        if (@available(iOS 13.0, *)) {
            layer.cornerCurve = kCACornerCurveContinuous;
        }
    }

    objc_setAssociatedObject(view, &kArcRoundSignatureKey, signature, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end

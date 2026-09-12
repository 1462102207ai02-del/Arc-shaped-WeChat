//
//  ArcCardEngine.m
//  Arc-shaped WeChat
//

#import "ArcCardEngine.h"
#import "ArcPrefs.h"
#import "ArcClassConfig.h"
#import "ArcTargetClasses.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

#pragma mark - 关联对象 key

static char kArcCardedKey;        // BOOL 该 cell 已被卡片化
static char kArcTVStateKey;       // ArcTVState * 挂在 UITableView 上
static char kArcCellTVKey;        // UITableView * (assign) 挂在 cell 上做缓存
static char kArcOrigBgKey;        // UIColor * 原始背景色
static char kArcAppliedKey;       // NSDictionary * 上次应用的快照，避免重复计算

#pragma mark - 表格状态缓存

@interface ArcTVState : NSObject
@property (nonatomic, assign) NSInteger generation;
@property (nonatomic, assign) BOOL cardEnabled;
@property (nonatomic, assign) BOOL rowCardMode;
@property (nonatomic, assign) BOOL prepared;
@end

@implementation ArcTVState
@end

#pragma mark - 卡片底板

@interface ArcCardBackgroundView ()
@property (nonatomic, strong) CAShapeLayer *fillLayer;
@property (nonatomic, strong) CAShapeLayer *borderLayer;
@property (nonatomic, strong) CALayer *dividerLayer;
@end

@implementation ArcCardBackgroundView

@synthesize fillColor = _fillColor;
@synthesize borderColor = _borderColor;

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        self.userInteractionEnabled = NO;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

        _cardInsets = UIEdgeInsetsZero;
        _cornerRadius = 12.0;
        _corners = UIRectCornerAllCorners;
        _fillColor = [UIColor whiteColor];
        _borderColor = [UIColor clearColor];
        _borderWidth = 0.0;
        _showDivider = NO;
        _dividerInset = 16.0;
        _dividerColor = [UIColor colorWithRed:0.898 green:0.898 blue:0.918 alpha:1.0];

        _fillLayer = [CAShapeLayer layer];
        [self.layer addSublayer:_fillLayer];

        _borderLayer = [CAShapeLayer layer];
        _borderLayer.fillColor = [UIColor clearColor].CGColor;
        [self.layer addSublayer:_borderLayer];

        _dividerLayer = [CALayer layer];
        [self.layer addSublayer:_dividerLayer];
    }
    return self;
}

- (void)setFillColor:(UIColor *)fillColor {
    _fillColor = fillColor;
    _fillLayer.fillColor = fillColor.CGColor;
}

- (void)setBorderColor:(UIColor *)borderColor {
    _borderColor = borderColor;
    _borderLayer.strokeColor = borderColor.CGColor;
}

// 卡片底板靠 autoresizingMask 跟随 cell 尺寸，但需要在 bounds 变化时重画圆角路径
- (void)setBounds:(CGRect)bounds {
    [super setBounds:bounds];
    [self refresh];
}

- (void)refresh {
    CGRect cardRect = UIEdgeInsetsInsetRect(self.bounds, self.cardInsets);
    if (CGRectIsEmpty(cardRect) || cardRect.size.width <= 0 || cardRect.size.height <= 0) {
        self.fillLayer.path = NULL;
        self.borderLayer.path = NULL;
        self.dividerLayer.hidden = YES;
        return;
    }

    CGFloat radius = MIN(self.cornerRadius, MIN(cardRect.size.width, cardRect.size.height) / 2.0);
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:cardRect
                                               byRoundingCorners:self.corners
                                                     cornerRadii:CGSizeMake(radius, radius)];

    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    self.fillLayer.frame = self.bounds;
    self.fillLayer.path = path.CGPath;

    self.borderLayer.frame = self.bounds;
    self.borderLayer.lineWidth = self.borderWidth;
    self.borderLayer.path = (self.borderWidth > 0) ? path.CGPath : NULL;
    self.borderLayer.hidden = (self.borderWidth <= 0);

    CGFloat hairline = 1.0 / MAX(1.0, [UIScreen mainScreen].scale);
    if (self.showDivider) {
        self.dividerLayer.hidden = NO;
        self.dividerLayer.backgroundColor = self.dividerColor.CGColor;
        self.dividerLayer.frame = CGRectMake(CGRectGetMinX(cardRect) + self.dividerInset,
                                             CGRectGetMaxY(cardRect) - hairline,
                                             MAX(0, cardRect.size.width - self.dividerInset),
                                             hairline);
    } else {
        self.dividerLayer.hidden = YES;
    }

    [CATransaction commit];
}

@end

#pragma mark - 引擎

@interface ArcCardEngine ()
@property (nonatomic, assign) NSInteger generation;
@end

@implementation ArcCardEngine

+ (instancetype)shared {
    static ArcCardEngine *engine = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        engine = [[ArcCardEngine alloc] init];
    });
    return engine;
}

- (instancetype)init {
    if ((self = [super init])) {
        _generation = 1;
        [self loadPageLists];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(onPrefsChanged)
                                                     name:ArcPrefsChangedNotification
                                                   object:nil];
    }
    return self;
}

- (void)onPrefsChanged {
    // 让所有表格缓存失效，下一帧按新设置重算
    self.generation++;
}

#pragma mark - 页面清单

- (void)loadPageLists {
    // 清单一律取自 ArcTargetClasses.h（《微信圆角 dylib 逆向分析报告》第三节）
    self.whitelist = [NSMutableSet setWithCapacity:kArcWhitelistClassCount];
    for (NSUInteger i = 0; i < kArcWhitelistClassCount; i++) {
        [self.whitelist addObject:kArcWhitelistClasses[i]];
    }

    self.blacklist = [NSMutableSet setWithCapacity:kArcBlacklistClassCount];
    for (NSUInteger i = 0; i < kArcBlacklistClassCount; i++) {
        [self.blacklist addObject:kArcBlacklistClasses[i]];
    }

    self.rowCardPages = [NSMutableSet setWithCapacity:kArcRowCardClassCount];
    for (NSUInteger i = 0; i < kArcRowCardClassCount; i++) {
        [self.rowCardPages addObject:kArcRowCardClasses[i]];
    }
}

#pragma mark - 作用域判定

- (UIViewController *)owningViewControllerForView:(UIView *)view {
    UIResponder *responder = view;
    NSInteger guard = 0;
    while (responder && guard++ < 24) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            return (UIViewController *)responder;
        }
        responder = [responder nextResponder];
    }
    return nil;
}

/// 该表格所属控制器对应的类级配置（未自定义时返回 nil）
- (ArcClassConfig *)configForTableView:(UITableView *)tableView {
    if (!tableView) { return nil; }
    UIViewController *vc = [self owningViewControllerForView:tableView];
    NSString *name = vc ? NSStringFromClass([vc class]) : @"";
    if (name.length == 0) { return nil; }
    ArcClassConfig *cfg = [[ArcClassConfigStore shared] configForClassName:name];
    return cfg.isCustomized ? cfg : nil;
}

- (BOOL)classIsListed:(Class)cls inSet:(NSSet<NSString *> *)set {
    if (!cls) { return NO; }
    Class stop = [UIViewController class];
    Class current = cls;
    NSInteger guard = 0;
    while (current && current != stop && guard++ < 16) {
        if ([set containsObject:NSStringFromClass(current)]) {
            return YES;
        }
        current = class_getSuperclass(current);
    }
    return [set containsObject:NSStringFromClass(cls)];
}

- (BOOL)rowCardModeForTableView:(UITableView *)tableView {
    ArcTVState *state = [self stateForTableView:tableView];
    return state.rowCardMode;
}

- (ArcTVState *)stateForTableView:(UITableView *)tableView {
    if (!tableView) { return nil; }
    ArcTVState *state = objc_getAssociatedObject(tableView, &kArcTVStateKey);
    if (state) {
        if (state.generation == self.generation) {
            return state;
        }
        state.prepared = NO;   // 设置变了，底色需要重刷
    }
    if (!state) {
        state = [[ArcTVState alloc] init];
        objc_setAssociatedObject(tableView, &kArcTVStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    ArcPrefs *prefs = [ArcPrefs shared];
    state.generation = self.generation;

    UIViewController *vc = [self owningViewControllerForView:tableView];
    NSString *clsName = vc ? NSStringFromClass([vc class]) : @"";
    Class cls = vc ? [vc class] : Nil;

    BOOL enabled = prefs.enabled;
    if (enabled) {
        if (cls && [self classIsListed:cls inSet:self.blacklist]) {
            enabled = NO;
        } else if (prefs.scopeMode == ArcScopeModeGlobal) {
            enabled = YES;
        } else {
            enabled = (cls != Nil) && [self classIsListed:cls inSet:self.whitelist];
        }
    }

    // 类级配置优先级最高：可强制开 / 强制关
    ArcClassConfig *clsConfig = (clsName.length > 0)
        ? [[ArcClassConfigStore shared] configForClassName:clsName] : nil;
    if (clsConfig.isExplicitlyEnabled) { enabled = YES; }
    else if (clsConfig.isExplicitlyDisabled) { enabled = NO; }

    state.cardEnabled = enabled;
    state.rowCardMode = enabled && prefs.sessionRowCard &&
                        (clsName.length > 0) && [self.rowCardPages containsObject:clsName];
    return state;
}

- (BOOL)isCardEnabledForTableView:(UITableView *)tableView {
    if (![tableView isKindOfClass:[UITableView class]]) { return NO; }
    ArcTVState *state = [self stateForTableView:tableView];
    return state.cardEnabled;
}

#pragma mark - 缩进

- (UITableView *)cachedTableViewForCell:(UITableViewCell *)cell {
    UITableView *cached = objc_getAssociatedObject(cell, &kArcCellTVKey);
    if (cached) { return cached; }
    UIView *view = cell.superview;
    for (NSInteger i = 0; i < 6 && view; i++, view = view.superview) {
        if ([view isKindOfClass:[UITableView class]]) {
            objc_setAssociatedObject(cell, &kArcCellTVKey, view, OBJC_ASSOCIATION_ASSIGN);
            return (UITableView *)view;
        }
    }
    return nil;
}

- (CGRect)adjustedFrameForCell:(UITableViewCell *)cell frame:(CGRect)frame {
    if (CGRectIsEmpty(frame) || frame.size.width <= 0) { return frame; }

    UITableView *tableView = [self cachedTableViewForCell:cell];
    if (![self isCardEnabledForTableView:tableView]) { return frame; }

    ArcPrefs *prefs = [ArcPrefs shared];
    ArcClassConfig *cfg = [self configForTableView:tableView];

    CGFloat left  = (cfg.hasInsets) ? MAX(0, cfg.insetLeft)  : prefs.horizontalInset;
    CGFloat right = (cfg.hasInsets) ? MAX(0, cfg.insetRight) : prefs.horizontalInset;
    if (left <= 0 && right <= 0) { return frame; }

    // 缩进量不得超过可用宽度的 1/3，避免畸形布局
    CGFloat maxInset = floor(frame.size.width / 3.0);
    left  = MIN(left,  maxInset);
    right = MIN(right, maxInset);

    // 已经缩进过就不再叠加（防止某些 VC 反复 setFrame 造成累积）
    UITableView *tv = tableView;
    if (tv && fabs(frame.size.width - (tv.bounds.size.width - left - right)) < 0.5) {
        return frame;
    }

    CGRect result = frame;
    result.origin.x += left;
    result.size.width -= (left + right);
    return result;
}

#pragma mark - 位置计算

- (ArcCellPosition)positionForTableView:(UITableView *)tableView
                              indexPath:(NSIndexPath *)indexPath
                            rowCardMode:(BOOL)rowCardMode {
    if (!indexPath || !tableView) { return ArcCellPositionUnknown; }
    if (rowCardMode) { return ArcCellPositionSingle; }

    NSInteger section = indexPath.section;
    if (section < 0 || section >= [tableView numberOfSections]) { return ArcCellPositionUnknown; }

    NSInteger rows = [tableView numberOfRowsInSection:section];
    if (rows <= 1) { return ArcCellPositionSingle; }
    if (indexPath.row <= 0) { return ArcCellPositionFirst; }
    if (indexPath.row >= rows - 1) { return ArcCellPositionLast; }
    return ArcCellPositionMiddle;
}

static UIRectCorner ArcCornersForPosition(ArcCellPosition position) {
    switch (position) {
        case ArcCellPositionSingle: return UIRectCornerAllCorners;
        case ArcCellPositionFirst:  return UIRectCornerTopLeft | UIRectCornerTopRight;
        case ArcCellPositionLast:   return UIRectCornerBottomLeft | UIRectCornerBottomRight;
        default:                    return 0;
    }
}

#pragma mark - 主入口

- (void)applyCardToCell:(UITableViewCell *)cell
              tableView:(UITableView *)tableView
              indexPath:(NSIndexPath *)indexPath {
    if (!cell || !tableView) { return; }
    if (![self isCardEnabledForTableView:tableView]) {
        [self restoreCell:cell];
        return;
    }

    ArcTVState *state = [self stateForTableView:tableView];
    ArcPrefs *prefs = [ArcPrefs shared];

    [self prepareTableViewIfNeeded:tableView state:state];

    ArcCellPosition position = [self positionForTableView:tableView
                                                indexPath:indexPath
                                              rowCardMode:state.rowCardMode];
    if (position == ArcCellPositionUnknown) { return; }

    ArcClassConfig *clsConfig = [self configForTableView:tableView];

    CGFloat vPad = state.rowCardMode ? MAX(0, prefs.cardSpacing) / 2.0 : 0.0;
    // 类级缩进叠加在行卡垂直留白之上
    UIEdgeInsets extra = clsConfig.hasInsets ? clsConfig.insets : UIEdgeInsetsZero;
    UIEdgeInsets cardInsets = UIEdgeInsetsMake(vPad + extra.top,
                                               extra.left,
                                               vPad + extra.bottom,
                                               extra.right);
    UIRectCorner corners = ArcCornersForPosition(position);
    CGFloat radius = clsConfig.hasCornerRadius ? clsConfig.cornerRadius : prefs.cornerRadius;
    UIColor *cardColor = clsConfig.hasBackgroundColor
        ? clsConfig.backgroundColor
        : [prefs cardColorForTraitCollection:tableView.traitCollection];

    // —— 幂等短路：参数没变就只刷新几何 ——
    NSDictionary *snapshot = @{
        @"p": @(position), @"r": @(radius), @"i": NSStringFromUIEdgeInsets(cardInsets),
        @"c": @(corners), @"s": @(prefs.showDivider), @"g": @(self.generation),
        @"cbg": clsConfig.hasBackgroundColor ? ArcColorHexString(clsConfig.backgroundColor) : @"",
    };
    ArcCardBackgroundView *bg = (ArcCardBackgroundView *)cell.backgroundView;

    if (![bg isKindOfClass:[ArcCardBackgroundView class]]) {
        // 记录原始背景色，方便关闭时还原
        if (!objc_getAssociatedObject(cell, &kArcOrigBgKey) && cell.backgroundColor) {
            objc_setAssociatedObject(cell, &kArcOrigBgKey, cell.backgroundColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        bg = [[ArcCardBackgroundView alloc] initWithFrame:cell.bounds];
        cell.backgroundView = bg;

        ArcCardBackgroundView *selected = [[ArcCardBackgroundView alloc] initWithFrame:cell.bounds];
        cell.selectedBackgroundView = selected;
        objc_setAssociatedObject(cell, &kArcCardedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    ArcCardBackgroundView *selectedBg = (ArcCardBackgroundView *)cell.selectedBackgroundView;
    BOOL isDark = [prefs resolvedDark:tableView.traitCollection];
    UIColor *highlight = isDark ? [UIColor colorWithWhite:1.0 alpha:0.10]
                                : [UIColor colorWithWhite:0.0 alpha:0.08];

    [self configure:bg
           cardColor:cardColor
          cardInsets:cardInsets
              radius:radius
             corners:corners
         showDivider:(prefs.showDivider && position != ArcCellPositionLast && position != ArcCellPositionSingle)
        dividerColor:[prefs dividerColorForTraitCollection:tableView.traitCollection]
        dividerInset:prefs.dividerInset
         borderWidth:prefs.borderWidth
         borderColor:prefs.borderColor];

    if ([selectedBg isKindOfClass:[ArcCardBackgroundView class]]) {
        [self configure:selectedBg
              cardColor:highlight
             cardInsets:cardInsets
                 radius:radius
                corners:corners
            showDivider:NO
           dividerColor:[UIColor clearColor]
           dividerInset:0
            borderWidth:0
            borderColor:[UIColor clearColor]];
    }

    cell.backgroundColor = [UIColor clearColor];
    if (prefs.hideSystemSeparator) {
        [self hideSystemSeparatorsInCell:cell];
    }

    objc_setAssociatedObject(cell, &kArcAppliedKey, snapshot, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)configure:(ArcCardBackgroundView *)view
        cardColor:(UIColor *)cardColor
       cardInsets:(UIEdgeInsets)cardInsets
           radius:(CGFloat)radius
          corners:(UIRectCorner)corners
      showDivider:(BOOL)showDivider
     dividerColor:(UIColor *)dividerColor
     dividerInset:(CGFloat)dividerInset
      borderWidth:(CGFloat)borderWidth
      borderColor:(UIColor *)borderColor {
    view.fillColor = cardColor;
    view.cardInsets = cardInsets;
    view.cornerRadius = radius;
    view.corners = corners;
    view.showDivider = showDivider;
    view.dividerColor = dividerColor;
    view.dividerInset = dividerInset;
    view.borderWidth = borderWidth;
    view.borderColor = borderColor;
    [view refresh];
}

- (void)restoreCell:(UITableViewCell *)cell {
    if (!objc_getAssociatedObject(cell, &kArcCardedKey)) { return; }
    UIColor *origin = objc_getAssociatedObject(cell, &kArcOrigBgKey);
    cell.backgroundView = nil;
    cell.selectedBackgroundView = nil;
    cell.backgroundColor = origin ?: [UIColor clearColor];
    objc_setAssociatedObject(cell, &kArcCardedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(cell, &kArcAppliedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - 表格底色

- (void)prepareTableViewIfNeeded:(UITableView *)tableView state:(ArcTVState *)state {
    if (state.prepared) { return; }
    state.prepared = YES;

    ArcPrefs *prefs = [ArcPrefs shared];
    if (!prefs.tintTableViewBg) { return; }

    UIColor *pageColor = [prefs pageColorForTraitCollection:tableView.traitCollection];
    tableView.backgroundColor = pageColor;
    if (tableView.backgroundView) {
        tableView.backgroundView.backgroundColor = pageColor;
    }
}

#pragma mark - 系统分割线

- (void)hideSystemSeparatorsInCell:(UITableViewCell *)cell {
    CGFloat cellH = CGRectGetHeight(cell.bounds);
    CGFloat cellW = CGRectGetWidth(cell.bounds);
    if (cellH <= 0 || cellW <= 0) { return; }

    [self hideSeparatorsInView:cell cellHeight:cellH cellWidth:cellW];
    [self hideSeparatorsInView:cell.contentView cellHeight:cellH cellWidth:cellW];
}

- (void)hideSeparatorsInView:(UIView *)container cellHeight:(CGFloat)cellH cellWidth:(CGFloat)cellW {
    for (UIView *sub in container.subviews) {
        CGRect f = sub.frame;
        CGFloat h = f.size.height;
        CGFloat w = f.size.width;
        BOOL thin = (h > 0 && h <= 1.2);
        BOOL wide = (w >= cellW * 0.6);
        BOOL atTop = (f.origin.y <= 1.2);
        BOOL atBottom = (f.origin.y + h >= cellH - 1.2);
        if (thin && wide && (atTop || atBottom)) {
            sub.hidden = YES;
        }
    }
}

#pragma mark - 分组间距

- (CGFloat)extraSpacingForHeaderInTableView:(UITableView *)tableView {
    if (![self isCardEnabledForTableView:tableView]) { return 0; }
    return 0;   // 间距统一加在 footer 上，避免上下叠加翻倍
}

- (CGFloat)extraSpacingForFooterInTableView:(UITableView *)tableView {
    if (![self isCardEnabledForTableView:tableView]) { return 0; }
    ArcTVState *state = [self stateForTableView:tableView];
    if (state.rowCardMode) { return 0; }   // 行卡片模式靠 cardInsets 拉开，不改行高
    return MAX(0, [ArcPrefs shared].cardSpacing);
}

#pragma mark - 即时刷新

- (void)reloadAllVisibleTableViews {
    NSArray<UIWindow *> *windows = nil;
    UIApplication *app = [UIApplication sharedApplication];
    if ([app respondsToSelector:@selector(windows)]) {
        windows = [app windows];
    }
    if (windows.count == 0) {
        NSMutableArray *collected = [NSMutableArray array];
        if (@available(iOS 13.0, *)) {
            for (UIScene *scene in [app connectedScenes]) {
                if ([scene isKindOfClass:[UIWindowScene class]]) {
                    [collected addObjectsFromArray:((UIWindowScene *)scene).windows];
                }
            }
        }
        windows = collected;
    }
    for (UIWindow *window in windows) {
        [self reloadTableViewsIn:window];
    }
}

- (void)reloadTableViewsIn:(UIView *)root {
    if ([root isKindOfClass:[UITableView class]]) {
        [(UITableView *)root reloadData];
        return;   // 表格内部不再递归
    }
    for (UIView *sub in root.subviews) {
        [self reloadTableViewsIn:sub];
    }
}

@end

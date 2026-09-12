//
//  ArcClassConfig.m
//  Arc-shaped WeChat
//

#import "ArcClassConfig.h"
#import "ArcPrefs.h"
#import "ArcTargetClasses.h"
#import <objc/runtime.h>

#pragma mark - 颜色工具

NSString *ArcColorHexString(UIColor *color) {
    if (!color) { return @""; }
    CGFloat r = 0, g = 0, b = 0, a = 1;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        // 灰度色 / 系统动态色拿不到 RGB 时退回白/黑分量
        CGFloat w = 0;
        [color getWhite:&w alpha:&a];
        r = g = b = w;
    }
    return [NSString stringWithFormat:@"#%02X%02X%02X%02X",
            (int)round(MAX(0, MIN(1, r)) * 255),
            (int)round(MAX(0, MIN(1, g)) * 255),
            (int)round(MAX(0, MIN(1, b)) * 255),
            (int)round(MAX(0, MIN(1, a)) * 255)];
}

UIColor *ArcColorFromHexObject(id hex) {
    if (![hex isKindOfClass:[NSString class]]) { return nil; }
    NSString *clean = [((NSString *)hex) stringByReplacingOccurrencesOfString:@"#" withString:@""];
    clean = [clean stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (clean.length != 6 && clean.length != 8) { return nil; }

    unsigned long long value = 0;
    NSScanner *scanner = [NSScanner scannerWithString:clean];
    if (![scanner scanHexLongLong:&value]) { return nil; }

    CGFloat a = 1.0;
    if (clean.length == 8) {
        a = ((value >> 0) & 0xFF) / 255.0;
        value = value >> 8;
    }
    CGFloat r = ((value >> 16) & 0xFF) / 255.0;
    CGFloat g = ((value >> 8) & 0xFF) / 255.0;
    CGFloat b = (value & 0xFF) / 255.0;
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

#pragma mark - 存储路径

/// 与 ArcPrefs 同目录（App 容器内一定可写）
static NSString *ArcClassOverridesPath(void) {
    static NSString *path = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *dir = [[[ArcPrefs shared] filePath] stringByDeletingLastPathComponent];
        if (dir.length == 0) {
            NSArray<NSString *> *libs = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
            dir = [libs.firstObject stringByAppendingPathComponent:@"Preferences"] ?: NSTemporaryDirectory();
        }
        path = [dir stringByAppendingPathComponent:@"com.arcshaped.wechat.classoverrides.plist"];
    });
    return path;
}

/// 前向声明：ArcClassConfig 的 -save 需要调用，而 store 的实现在下方
@interface ArcClassConfigStore (ArcPersistence)
- (void)persistConfig:(ArcClassConfig *)config;
@end

#pragma mark - 单个类的配置

@implementation ArcClassConfig {
    NSString *_className;
    ArcClassKind _kind;
}

- (instancetype)initWithClassName:(NSString *)name kind:(ArcClassKind)kind {
    if ((self = [super init])) {
        _className = [name copy];
        _kind = kind;
        _enabledMode = ArcClassEnabledModeInherit;
        _hasBackgroundColor = NO;
        _hasCornerRadius = NO;
        _hasInsets = NO;
        _hasForceCircle = NO;
    }
    return self;
}

- (NSString *)className { return _className; }
- (ArcClassKind)kind { return _kind; }

- (BOOL)isExplicitlyDisabled { return self.enabledMode == ArcClassEnabledModeOff; }
- (BOOL)isExplicitlyEnabled  { return self.enabledMode == ArcClassEnabledModeOn; }

- (UIEdgeInsets)insets {
    return UIEdgeInsetsMake(self.insetTop, self.insetLeft, self.insetBottom, self.insetRight);
}

- (BOOL)isCustomized {
    return self.enabledMode != ArcClassEnabledModeInherit
        || self.hasBackgroundColor
        || self.hasCornerRadius
        || self.hasInsets
        || self.hasForceCircle;
}

- (NSDictionary *)serialized {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"enabled"] = @(self.enabledMode);
    if (self.hasBackgroundColor) { d[@"bg"] = ArcColorHexString(self.backgroundColor); }
    if (self.hasCornerRadius)    { d[@"radius"] = @(self.cornerRadius); }
    if (self.hasInsets) {
        d[@"insetTop"]    = @(self.insetTop);
        d[@"insetLeft"]   = @(self.insetLeft);
        d[@"insetBottom"] = @(self.insetBottom);
        d[@"insetRight"]  = @(self.insetRight);
    }
    if (self.hasForceCircle) { d[@"circle"] = @(self.forceCircle); }
    return d;
}

- (void)applyDictionary:(NSDictionary *)d {
    if (![d isKindOfClass:[NSDictionary class]]) { return; }
    id v;
    v = d[@"enabled"];
    if ([v respondsToSelector:@selector(integerValue)]) {
        NSInteger m = [v integerValue];
        if (m >= 0 && m <= 2) { _enabledMode = (ArcClassEnabledMode)m; }
    }
    v = d[@"bg"];
    if (v) {
        UIColor *c = ArcColorFromHexObject(v);
        if (c) { _backgroundColor = c; _hasBackgroundColor = YES; }
    }
    v = d[@"radius"];
    if ([v respondsToSelector:@selector(doubleValue)]) { _cornerRadius = [v doubleValue]; _hasCornerRadius = YES; }
    v = d[@"insetTop"];
    if ([v respondsToSelector:@selector(doubleValue)]) {
        _insetTop    = [d[@"insetTop"] doubleValue];
        _insetLeft   = [d[@"insetLeft"] doubleValue];
        _insetBottom = [d[@"insetBottom"] doubleValue];
        _insetRight  = [d[@"insetRight"] doubleValue];
        _hasInsets = YES;
    }
    v = d[@"circle"];
    if ([v respondsToSelector:@selector(boolValue)]) { _forceCircle = [v boolValue]; _hasForceCircle = YES; }
}

- (void)save {
    [[ArcClassConfigStore shared] persistConfig:self];
}

- (void)reset {
    _enabledMode = ArcClassEnabledModeInherit;
    _backgroundColor = nil; _hasBackgroundColor = NO;
    _cornerRadius = 0; _hasCornerRadius = NO;
    _insetTop = _insetLeft = _insetBottom = _insetRight = 0; _hasInsets = NO;
    _forceCircle = NO; _hasForceCircle = NO;
    [self save];
}

@end

#pragma mark - 仓库

@interface ArcClassConfigStore ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *raw;
@property (nonatomic, strong) NSMutableDictionary<NSString *, ArcClassConfig *> *cache;
@property (nonatomic, strong) NSArray<NSString *> *viewNames;
@property (nonatomic, strong) NSArray<NSString *> *controllerNames;
@property (nonatomic, strong) NSMutableSet<NSString *> *viewNameSet;
@end

@implementation ArcClassConfigStore

+ (instancetype)shared {
    static ArcClassConfigStore *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ArcClassConfigStore alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        [self buildNames];
        [self reload];
    }
    return self;
}

- (void)buildNames {
    NSMutableArray<NSString *> *views = [NSMutableArray array];
    NSMutableSet<NSString *> *set = [NSMutableSet set];

    for (NSUInteger i = 0; i < kArcForceRoundClassCount; i++) {
        NSString *n = kArcForceRoundClasses[i];
        if (![set containsObject:n]) { [set addObject:n]; [views addObject:n]; }
    }
    for (NSUInteger i = 0; i < kArcForceRoundCellClassCount; i++) {
        NSString *n = kArcForceRoundCellClasses[i];
        if (![set containsObject:n]) { [set addObject:n]; [views addObject:n]; }
    }
    for (NSUInteger i = 0; i < kArcForceRoundTableClassCount; i++) {
        NSString *n = kArcForceRoundTableClasses[i];
        if (![set containsObject:n]) { [set addObject:n]; [views addObject:n]; }
    }

    self.viewNameSet = set;
    self.viewNames = [views sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];

    NSMutableArray<NSString *> *ctrls = [NSMutableArray array];
    NSMutableSet<NSString *> *cset = [NSMutableSet set];
    for (NSUInteger i = 0; i < kArcWhitelistClassCount; i++) {
        NSString *n = kArcWhitelistClasses[i];
        if ([set containsObject:n] || [cset containsObject:n]) { continue; }
        [cset addObject:n];
        [ctrls addObject:n];
    }
    self.controllerNames = [ctrls sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

- (void)reload {
    NSDictionary *onDisk = [NSDictionary dictionaryWithContentsOfFile:ArcClassOverridesPath()];
    self.raw = [onDisk isKindOfClass:[NSDictionary class]] ? [onDisk mutableCopy] : [NSMutableDictionary dictionary];
    self.cache = [NSMutableDictionary dictionary];
}

- (void)persistConfig:(ArcClassConfig *)config {
    if (!config) { return; }
    if (config.isCustomized) {
        self.raw[config.className] = [config serialized];
    } else {
        [self.raw removeObjectForKey:config.className];
    }
    @try {
        [self.raw writeToFile:ArcClassOverridesPath() atomically:YES];
    } @catch (NSException *exception) { }

    self.cache[config.className] = config;
    // 让引擎缓存失效，立即生效
    [[NSNotificationCenter defaultCenter] postNotificationName:ArcPrefsChangedNotification object:nil];
}

- (ArcClassKind)kindForClassName:(NSString *)name {
    return [self.viewNameSet containsObject:name] ? ArcClassKindView : ArcClassKindController;
}

- (ArcClassConfig *)configForClassName:(NSString *)name {
    if (name.length == 0) { return [[ArcClassConfig alloc] initWithClassName:@"" kind:ArcClassKindController]; }
    ArcClassConfig *cached = self.cache[name];
    if (cached) { return cached; }

    ArcClassConfig *config = [[ArcClassConfig alloc] initWithClassName:name
                                                                kind:[self kindForClassName:name]];
    [config applyDictionary:self.raw[name]];
    self.cache[name] = config;
    return config;
}

- (ArcClassConfig *)configResolvingSuperclassForClass:(Class)cls {
    if (!cls) { return nil; }
    Class stop = [UIView class];
    Class current = cls;
    NSInteger guard = 0;
    while (current && guard++ < 14) {
        NSString *name = NSStringFromClass(current);
        ArcClassConfig *cfg = [self configForClassName:name];
        if (cfg.isCustomized) { return cfg; }
        if (current == stop) { break; }
        current = class_getSuperclass(current);
    }
    return nil;
}

- (NSUInteger)customizedCount {
    NSUInteger n = 0;
    for (NSString *key in self.raw) {
        if ([self.raw[key] isKindOfClass:[NSDictionary class]]) { n++; }
    }
    return n;
}

- (void)resetAll {
    [self.raw removeAllObjects];
    [self.cache removeAllObjects];
    @try {
        [self.raw writeToFile:ArcClassOverridesPath() atomically:YES];
    } @catch (NSException *exception) { }
    [[NSNotificationCenter defaultCenter] postNotificationName:ArcPrefsChangedNotification object:nil];
}

- (NSArray<NSString *> *)viewClassNames { return self.viewNames; }
- (NSArray<NSString *> *)controllerClassNames { return self.controllerNames; }

@end

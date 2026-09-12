//
//  ArcPrefs.m
//  Arc-shaped WeChat
//

#import "ArcPrefs.h"

NSString *const ArcPrefsChangedNotification = @"com.arcshaped.wechat.prefschanged.local";

#define kArcDomain @"com.arcshaped.wechat"

static NSString *const kEnabled           = @"Enabled";
static NSString *const kRadius            = @"CornerRadius";
static NSString *const kInset             = @"HorizontalInset";
static NSString *const kSpacing           = @"CardSpacing";
static NSString *const kBorderWidth       = @"BorderWidth";
static NSString *const kBorderColor       = @"BorderColor";
static NSString *const kShowDivider       = @"ShowDivider";
static NSString *const kDividerInset      = @"DividerInset";
static NSString *const kHideSysSep        = @"HideSystemSeparator";
static NSString *const kCardStyle         = @"CardStyle";
static NSString *const kScopeMode         = @"ScopeMode";
static NSString *const kSessionRow        = @"SessionRowCard";
static NSString *const kTintBg            = @"TintTableViewBg";

static NSString *const kForceRound        = @"ForceRoundEnabled";
static NSString *const kRoundAvatar       = @"RoundAvatar";
static NSString *const kAvatarCircle      = @"AvatarCircle";
static NSString *const kAvatarRadius      = @"AvatarRadius";
static NSString *const kRoundImageView    = @"RoundImageView";
static NSString *const kImageViewRadius   = @"ImageViewRadius";
static NSString *const kRoundImageGrid    = @"RoundImageGrid";
static NSString *const kImageGridRadius   = @"ImageGridRadius";
static NSString *const kRoundButton       = @"RoundButton";
static NSString *const kButtonRadius      = @"ButtonRadius";
static NSString *const kRoundContainer    = @"RoundContainer";
static NSString *const kContainerRadius   = @"ContainerRadius";
static NSString *const kRoundSettingCell  = @"RoundSettingCell";
static NSString *const kSettingCellRadius = @"SettingCellRadius";
static NSString *const kRoundTableView    = @"RoundTableView";
static NSString *const kTableViewRadius   = @"TableViewRadius";
static NSString *const kContinuousCorner  = @"ContinuousCorner";

/// TrollFools / 沙盒环境：写 App 自己的容器（一定可写）
/// 越狱环境：优先写 /var/mobile 下的共享位置，失败再回退容器
static NSString *ArcPrefsFilePath(void) {
    static NSString *path = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSFileManager *fm = [NSFileManager defaultManager];

        NSString *containerDir = nil;
        NSArray<NSString *> *libs = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
        if (libs.count > 0) {
            containerDir = [libs.firstObject stringByAppendingPathComponent:@"Preferences"];
        } else {
            containerDir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Preferences"];
        }

        NSArray<NSString *> *candidates = @[
            @"/var/jb/var/mobile/Library/Preferences",
            @"/var/mobile/Library/Preferences",
            containerDir,
        ];

        for (NSString *dir in candidates) {
            if (![fm fileExistsAtPath:dir]) {
                [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
            }
            NSString *candidate = [dir stringByAppendingPathComponent:[kArcDomain stringByAppendingString:@".plist"]];
            BOOL writable = YES;
            if (![fm fileExistsAtPath:candidate]) {
                writable = [@"{}" writeToFile:candidate atomically:YES encoding:NSUTF8StringEncoding error:nil];
            }
            if (writable) {
                path = candidate;
                break;
            }
        }
        path = path ?: [containerDir stringByAppendingPathComponent:[kArcDomain stringByAppendingString:@".plist"]];
    });
    return path;
}

@interface ArcPrefs ()
@property (nonatomic, strong) NSMutableDictionary *store;
@property (nonatomic, copy, readwrite) NSString *filePath;
@end

@implementation ArcPrefs

+ (instancetype)shared {
    static ArcPrefs *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ArcPrefs alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        _filePath = ArcPrefsFilePath();
        [self reload];
    }
    return self;
}

- (NSDictionary *)defaultValues {
    return @{
        // 列表卡片化
        kEnabled:       @YES,
        kRadius:        @12.0,
        kInset:         @12.0,
        kSpacing:       @10.0,
        kBorderWidth:   @0.0,
        kBorderColor:   @"#E5E5EA",
        kShowDivider:   @YES,
        kDividerInset:  @16.0,
        kHideSysSep:    @YES,
        kCardStyle:     @(ArcCardStyleSystem),
        kScopeMode:     @(ArcScopeModeWhitelist),
        kSessionRow:    @YES,
        kTintBg:        @YES,

        // 强制圆角
        kForceRound:       @YES,
        kRoundAvatar:      @YES,
        kAvatarCircle:     @YES,
        kAvatarRadius:     @8.0,
        kRoundImageView:   @YES,
        kImageViewRadius:  @8.0,
        kRoundImageGrid:   @YES,
        kImageGridRadius:  @8.0,
        kRoundButton:      @YES,
        kButtonRadius:     @10.0,
        kRoundContainer:   @YES,
        kContainerRadius:  @8.0,
        kRoundSettingCell: @YES,
        kSettingCellRadius: @10.0,
        kRoundTableView:   @NO,
        kTableViewRadius:  @12.0,
        kContinuousCorner: @YES,
    };
}

- (void)reload {
    NSDictionary *onDisk = [NSDictionary dictionaryWithContentsOfFile:self.filePath];
    NSMutableDictionary *merged = [[self defaultValues] mutableCopy];
    if ([onDisk isKindOfClass:[NSDictionary class]]) {
        [merged addEntriesFromDictionary:onDisk];
    }
    self.store = merged;
}

- (id)objectForKey:(NSString *)key {
    id value = self.store[key];
    if (value == nil) { value = [self defaultValues][key]; }
    return value;
}

- (void)setObject:(id)value forKey:(NSString *)key {
    if (value) { self.store[key] = value; }
    else { [self.store removeObjectForKey:key]; }
}

- (void)synchronize {
    @try {
        if (![self.store writeToFile:self.filePath atomically:YES]) {
            // 写失败（例如只读容器）时退回内存态，保证本次会话内设置仍然生效
        }
    } @catch (NSException *exception) { }
    [[NSNotificationCenter defaultCenter] postNotificationName:ArcPrefsChangedNotification object:nil];
}

- (void)resetToDefaults {
    self.store = [[self defaultValues] mutableCopy];
    [self synchronize];
}

#pragma mark - 列表卡片化

- (BOOL)enabled            { return [[self objectForKey:kEnabled] boolValue]; }
- (void)setEnabled:(BOOL)v { [self setObject:@(v) forKey:kEnabled]; }

- (CGFloat)cornerRadius            { return [[self objectForKey:kRadius] doubleValue]; }
- (void)setCornerRadius:(CGFloat)v { [self setObject:@(v) forKey:kRadius]; }

- (CGFloat)horizontalInset            { return [[self objectForKey:kInset] doubleValue]; }
- (void)setHorizontalInset:(CGFloat)v { [self setObject:@(v) forKey:kInset]; }

- (CGFloat)cardSpacing            { return [[self objectForKey:kSpacing] doubleValue]; }
- (void)setCardSpacing:(CGFloat)v { [self setObject:@(v) forKey:kSpacing]; }

- (CGFloat)borderWidth            { return [[self objectForKey:kBorderWidth] doubleValue]; }
- (void)setBorderWidth:(CGFloat)v { [self setObject:@(v) forKey:kBorderWidth]; }

- (UIColor *)borderColor            { return ArcColorFromHex([self objectForKey:kBorderColor]); }
- (void)setBorderColor:(UIColor *)c { [self setObject:ArcHexFromColor(c) forKey:kBorderColor]; }

- (BOOL)showDivider            { return [[self objectForKey:kShowDivider] boolValue]; }
- (void)setShowDivider:(BOOL)v { [self setObject:@(v) forKey:kShowDivider]; }

- (CGFloat)dividerInset            { return [[self objectForKey:kDividerInset] doubleValue]; }
- (void)setDividerInset:(CGFloat)v { [self setObject:@(v) forKey:kDividerInset]; }

- (BOOL)hideSystemSeparator            { return [[self objectForKey:kHideSysSep] boolValue]; }
- (void)setHideSystemSeparator:(BOOL)v { [self setObject:@(v) forKey:kHideSysSep]; }

- (ArcCardStyle)cardStyle            { return (ArcCardStyle)[[self objectForKey:kCardStyle] unsignedIntegerValue]; }
- (void)setCardStyle:(ArcCardStyle)v { [self setObject:@(v) forKey:kCardStyle]; }

- (ArcScopeMode)scopeMode            { return (ArcScopeMode)[[self objectForKey:kScopeMode] unsignedIntegerValue]; }
- (void)setScopeMode:(ArcScopeMode)v { [self setObject:@(v) forKey:kScopeMode]; }

- (BOOL)sessionRowCard            { return [[self objectForKey:kSessionRow] boolValue]; }
- (void)setSessionRowCard:(BOOL)v { [self setObject:@(v) forKey:kSessionRow]; }

- (BOOL)tintTableViewBg            { return [[self objectForKey:kTintBg] boolValue]; }
- (void)setTintTableViewBg:(BOOL)v { [self setObject:@(v) forKey:kTintBg]; }

#pragma mark - 强制圆角

- (BOOL)forceRoundEnabled            { return [[self objectForKey:kForceRound] boolValue]; }
- (void)setForceRoundEnabled:(BOOL)v { [self setObject:@(v) forKey:kForceRound]; }

- (BOOL)roundAvatar            { return [[self objectForKey:kRoundAvatar] boolValue]; }
- (void)setRoundAvatar:(BOOL)v { [self setObject:@(v) forKey:kRoundAvatar]; }

- (BOOL)avatarCircle            { return [[self objectForKey:kAvatarCircle] boolValue]; }
- (void)setAvatarCircle:(BOOL)v { [self setObject:@(v) forKey:kAvatarCircle]; }

- (CGFloat)avatarRadius            { return [[self objectForKey:kAvatarRadius] doubleValue]; }
- (void)setAvatarRadius:(CGFloat)v { [self setObject:@(v) forKey:kAvatarRadius]; }

- (BOOL)roundImageView            { return [[self objectForKey:kRoundImageView] boolValue]; }
- (void)setRoundImageView:(BOOL)v { [self setObject:@(v) forKey:kRoundImageView]; }

- (CGFloat)imageViewRadius            { return [[self objectForKey:kImageViewRadius] doubleValue]; }
- (void)setImageViewRadius:(CGFloat)v { [self setObject:@(v) forKey:kImageViewRadius]; }

- (BOOL)roundImageGrid            { return [[self objectForKey:kRoundImageGrid] boolValue]; }
- (void)setRoundImageGrid:(BOOL)v { [self setObject:@(v) forKey:kRoundImageGrid]; }

- (CGFloat)imageGridRadius            { return [[self objectForKey:kImageGridRadius] doubleValue]; }
- (void)setImageGridRadius:(CGFloat)v { [self setObject:@(v) forKey:kImageGridRadius]; }

- (BOOL)roundButton            { return [[self objectForKey:kRoundButton] boolValue]; }
- (void)setRoundButton:(BOOL)v { [self setObject:@(v) forKey:kRoundButton]; }

- (CGFloat)buttonRadius            { return [[self objectForKey:kButtonRadius] doubleValue]; }
- (void)setButtonRadius:(CGFloat)v { [self setObject:@(v) forKey:kButtonRadius]; }

- (BOOL)roundContainer            { return [[self objectForKey:kRoundContainer] boolValue]; }
- (void)setRoundContainer:(BOOL)v { [self setObject:@(v) forKey:kRoundContainer]; }

- (CGFloat)containerRadius            { return [[self objectForKey:kContainerRadius] doubleValue]; }
- (void)setContainerRadius:(CGFloat)v { [self setObject:@(v) forKey:kContainerRadius]; }

- (BOOL)roundSettingCell            { return [[self objectForKey:kRoundSettingCell] boolValue]; }
- (void)setRoundSettingCell:(BOOL)v { [self setObject:@(v) forKey:kRoundSettingCell]; }

- (CGFloat)settingCellRadius            { return [[self objectForKey:kSettingCellRadius] doubleValue]; }
- (void)setSettingCellRadius:(CGFloat)v { [self setObject:@(v) forKey:kSettingCellRadius]; }

- (BOOL)roundTableView            { return [[self objectForKey:kRoundTableView] boolValue]; }
- (void)setRoundTableView:(BOOL)v { [self setObject:@(v) forKey:kRoundTableView]; }

- (CGFloat)tableViewRadius            { return [[self objectForKey:kTableViewRadius] doubleValue]; }
- (void)setTableViewRadius:(CGFloat)v { [self setObject:@(v) forKey:kTableViewRadius]; }

- (BOOL)continuousCorner            { return [[self objectForKey:kContinuousCorner] boolValue]; }
- (void)setContinuousCorner:(BOOL)v { [self setObject:@(v) forKey:kContinuousCorner]; }

#pragma mark - 颜色

- (BOOL)resolvedDark:(UITraitCollection *)traits {
    switch (self.cardStyle) {
        case ArcCardStyleLight: return NO;
        case ArcCardStyleDark:  return YES;
        default: break;
    }
    if (@available(iOS 13.0, *)) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark;
    }
    return NO;
}

- (UIColor *)cardColorForTraitCollection:(UITraitCollection *)traits {
    if ([self resolvedDark:traits]) {
        return [UIColor colorWithRed:0.11 green:0.11 blue:0.118 alpha:1.0];
    }
    return [UIColor whiteColor];
}

- (UIColor *)pageColorForTraitCollection:(UITraitCollection *)traits {
    if ([self resolvedDark:traits]) {
        return [UIColor blackColor];
    }
    return [UIColor colorWithRed:0.957 green:0.957 blue:0.969 alpha:1.0];
}

- (UIColor *)dividerColorForTraitCollection:(UITraitCollection *)traits {
    if ([self resolvedDark:traits]) {
        return [UIColor colorWithWhite:1.0 alpha:0.10];
    }
    return [UIColor colorWithRed:0.898 green:0.898 blue:0.918 alpha:1.0];
}

#pragma mark - 颜色工具

static UIColor *ArcColorFromHex(id hex) {
    if (![hex isKindOfClass:[NSString class]] || ((NSString *)hex).length < 6) {
        return [UIColor colorWithRed:0.898 green:0.898 blue:0.918 alpha:1.0];
    }
    NSString *clean = [(NSString *)hex stringByReplacingOccurrencesOfString:@"#" withString:@""];
    if (clean.length == 8) { clean = [clean substringFromIndex:2]; }
    unsigned int rgb = 0;
    NSScanner *scanner = [NSScanner scannerWithString:clean];
    [scanner scanHexInt:&rgb];
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8) & 0xFF) / 255.0
                            blue:(rgb & 0xFF) / 255.0
                           alpha:1.0];
}

static NSString *ArcHexFromColor(UIColor *color) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [color getRed:&r green:&g blue:&b alpha:&a];
    return [NSString stringWithFormat:@"#%02X%02X%02X", (int)(r * 255), (int)(g * 255), (int)(b * 255)];
}

@end

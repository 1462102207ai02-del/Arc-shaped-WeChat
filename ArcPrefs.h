//
//  ArcPrefs.h
//  Arc-shaped WeChat
//
//  配置读写。
//
//  重要：TrollFools 注入场景下微信仍然运行在 App 沙盒里，
//  /var/mobile/Library/Preferences 不可写，所以配置一律写进 App 自己的容器。
//  设置页也跑在微信进程内，同进程读写，不需要跨进程共享。
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const ArcPrefsChangedNotification;

typedef NS_ENUM(NSUInteger, ArcScopeMode) {
    ArcScopeModeWhitelist = 0,   // 只对已验证页面生效
    ArcScopeModeGlobal    = 1,   // 全局生效
};

typedef NS_ENUM(NSUInteger, ArcCardStyle) {
    ArcCardStyleSystem = 0,
    ArcCardStyleLight  = 1,
    ArcCardStyleDark   = 2,
};

@interface ArcPrefs : NSObject

+ (instancetype)shared;

/// 配置文件实际路径（App 容器内），调试与排查用
@property (nonatomic, readonly) NSString *filePath;

#pragma mark - 列表卡片化

@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) CGFloat cornerRadius;
@property (nonatomic, assign) CGFloat horizontalInset;
@property (nonatomic, assign) CGFloat cardSpacing;
@property (nonatomic, assign) CGFloat borderWidth;
@property (nonatomic, strong) UIColor *borderColor;
@property (nonatomic, assign) BOOL showDivider;
@property (nonatomic, assign) CGFloat dividerInset;
@property (nonatomic, assign) BOOL hideSystemSeparator;
@property (nonatomic, assign) ArcCardStyle cardStyle;
@property (nonatomic, assign) ArcScopeMode scopeMode;
@property (nonatomic, assign) BOOL sessionRowCard;
@property (nonatomic, assign) BOOL tintTableViewBg;

#pragma mark - 强制圆角（对应逆向得到的视图类清单）

@property (nonatomic, assign) BOOL forceRoundEnabled;      // 总开关
@property (nonatomic, assign) BOOL roundAvatar;           // MMHeadImageView
@property (nonatomic, assign) BOOL avatarCircle;          // 头像强制正圆
@property (nonatomic, assign) CGFloat avatarRadius;
@property (nonatomic, assign) BOOL roundImageView;        // WCImageView / MMWebImageView
@property (nonatomic, assign) CGFloat imageViewRadius;
@property (nonatomic, assign) BOOL roundImageGrid;        // MMImageGridView
@property (nonatomic, assign) CGFloat imageGridRadius;
@property (nonatomic, assign) BOOL roundButton;           // MMUIButton / MMTransparentButton
@property (nonatomic, assign) CGFloat buttonRadius;
@property (nonatomic, assign) BOOL roundContainer;        // MMUIView / ColorGradientView
@property (nonatomic, assign) CGFloat containerRadius;
@property (nonatomic, assign) BOOL roundSettingCell;      // SettingCell / MMTableViewCell
@property (nonatomic, assign) CGFloat settingCellRadius;
@property (nonatomic, assign) BOOL roundTableView;        // MMTableView
@property (nonatomic, assign) CGFloat tableViewRadius;
@property (nonatomic, assign) BOOL continuousCorner;      // kCACornerCurveContinuous（苹果风格连续圆角）

#pragma mark - 横幅（折叠置顶聊天面板 / 第三方登录卡片）

@property (nonatomic, assign) BOOL bannerEnabled;          // 横幅总开关
@property (nonatomic, assign) CGFloat bannerRadius;        // 横幅圆角
@property (nonatomic, assign) CGFloat bannerInsetH;        // 横幅水平缩进

#pragma mark - 存取

- (void)reload;
- (void)setObject:(nullable id)value forKey:(NSString *)key;
- (void)synchronize;
- (void)resetToDefaults;

- (BOOL)resolvedDark:(nullable UITraitCollection *)traits;
- (UIColor *)cardColorForTraitCollection:(nullable UITraitCollection *)traits;
- (UIColor *)pageColorForTraitCollection:(nullable UITraitCollection *)traits;
- (UIColor *)dividerColorForTraitCollection:(nullable UITraitCollection *)traits;

@end

NS_ASSUME_NONNULL_END

//
//  ArcClassConfig.h
//  Arc-shaped WeChat
//
//  「按类配置」：逆向报告里每一个已知类都可以单独设置
//    - 是否启用（跟随全局 / 强制开启 / 强制关闭）
//    - 背景色（走系统 UIColorPickerViewController 取色，支持透明度）
//    - 圆角数值（自定义填写，pt）
//    - 缩进边距（上/左/下/右 自定义填写，pt）
//    - 视图类额外支持「强制正圆」
//
//  未自定义的项一律回落到全局设置，保证默认情况下行为和以前完全一致。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, ArcClassKind) {
    ArcClassKindView = 0,        // [A] 视图类（头像/图片/按钮/容器…）
    ArcClassKindController = 1,  // [B][C] 控制器与其它（列表卡片化）
};

typedef NS_ENUM(NSInteger, ArcClassEnabledMode) {
    ArcClassEnabledModeInherit = 0,  // 跟随全局
    ArcClassEnabledModeOn      = 1,  // 强制开启
    ArcClassEnabledModeOff     = 2,  // 强制关闭
};

/// 颜色与 HEX 互转（支持 #RRGGBB 与 #RRGGBBAA）
NSString *ArcColorHexString(UIColor *color);
UIColor *_Nullable ArcColorFromHexObject(id hex);

@interface ArcClassConfig : NSObject

@property (nonatomic, copy, readonly) NSString *className;
@property (nonatomic, assign, readonly) ArcClassKind kind;

/// 启用模式
@property (nonatomic, assign) ArcClassEnabledMode enabledMode;
- (BOOL)isExplicitlyDisabled;
- (BOOL)isExplicitlyEnabled;

/// 背景色（hasBackgroundColor == NO 时表示未设置，回落全局）
@property (nonatomic, strong, nullable) UIColor *backgroundColor;
@property (nonatomic, assign) BOOL hasBackgroundColor;

/// 圆角半径（pt）
@property (nonatomic, assign) CGFloat cornerRadius;
@property (nonatomic, assign) BOOL hasCornerRadius;

/// 缩进边距（pt）
@property (nonatomic, assign) CGFloat insetTop;
@property (nonatomic, assign) CGFloat insetLeft;
@property (nonatomic, assign) CGFloat insetBottom;
@property (nonatomic, assign) CGFloat insetRight;
@property (nonatomic, assign) BOOL hasInsets;
- (UIEdgeInsets)insets;

/// 视图类专用：忽略半径，按最短边取一半
@property (nonatomic, assign) BOOL forceCircle;
@property (nonatomic, assign) BOOL hasForceCircle;

/// 是否存在任何自定义项
- (BOOL)isCustomized;
- (void)save;
- (void)reset;

@end

#pragma mark - 配置仓库

@interface ArcClassConfigStore : NSObject

+ (instancetype)shared;

/// [A] 视图类（11）
- (NSArray<NSString *> *)viewClassNames;
/// [B][C] 控制器与其它（85）
- (NSArray<NSString *> *)controllerClassNames;

- (ArcClassKind)kindForClassName:(NSString *)name;

/// 精确按类名取配置（总是返回对象，未自定义时各项 has* 为 NO）
- (ArcClassConfig *)configForClassName:(NSString *)name;

/// 沿继承链向上查找：子类未配置时继承最近祖先的配置
- (ArcClassConfig *_Nullable)configResolvingSuperclassForClass:(Class)cls;

/// 已自定义的类数量
- (NSUInteger)customizedCount;

- (void)reload;
- (void)resetAll;

@end

NS_ASSUME_NONNULL_END

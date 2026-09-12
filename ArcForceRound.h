//
//  ArcForceRound.h
//  Arc-shaped WeChat
//
//  对逆向得到的"视图/单元/按钮/图片/控件类"清单做强制圆角。
//  清单来源：微信圆角 dylib 静态分析报告第三节 [A] 组（11 个类）
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, ArcRoundKind) {
    ArcRoundKindAvatar      = 0,   // MMHeadImageView
    ArcRoundKindImageView,          // WCImageView / MMWebImageView
    ArcRoundKindImageGrid,          // MMImageGridView
    ArcRoundKindButton,             // MMUIButton / MMTransparentButton
    ArcRoundKindContainer,          // MMUIView / ColorGradientView
    ArcRoundKindSettingCell,        // SettingCell / MMTableViewCell
    ArcRoundKindTableView,          // MMTableView
};

@interface ArcForceRound : NSObject

+ (instancetype)shared;

/// 安装所有目标类的 hook（幂等）
+ (void)install;

/// 该类别当前是否启用
- (BOOL)enabledForKind:(ArcRoundKind)kind;

/// 应用到某个视图（由 hook 调用，也可外部调用）
- (void)applyToView:(UIView *)view kind:(ArcRoundKind)kind;

@end

NS_ASSUME_NONNULL_END

//
//  ArcBannerRound.h
//  Arc-shaped WeChat
//
//  横幅专用引擎：对折叠置顶聊天的展开面板、第三方登录卡片等
//  "横幅/卡片" 类视图统一做圆角 + 水平缩进。
//
//  与 ArcForceRound 的区别：
//    - ForceRound 只改 layer.cornerRadius / masksToBounds；
//    - BannerRound 还会按"距父视图水平缩进"重新设置 frame，让横幅从屏幕/容器
//      边缘缩进一定距离，视觉上更像悬浮卡片。
//
//  通过 kArcPrefsBanner* 控制；总开关 prefs.enabled + prefs.bannerEnabled 同时开启才生效。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface ArcBannerRound : NSObject

+ (instancetype)shared;

/// 幂等安装；TrollFools 注入点加载时机不确定，可被反复调用补齐目标类。
+ (void)install;

@end

NS_ASSUME_NONNULL_END
//
//  ArcClassSettings.h
//  Arc-shaped WeChat
//
//  按类配置：列表 → 单个类的详细设置
//

#import <UIKit/UIKit.h>
#import "ArcClassConfig.h"

NS_ASSUME_NONNULL_BEGIN

/// 所有已知类的列表（分组 + 搜索）
@interface ArcClassListController : UIViewController
@end

/// 单个类的详细设置：启用模式 / 背景色 / 圆角 / 缩进
@interface ArcClassDetailController : UIViewController
- (instancetype)initWithClassName:(NSString *)className kind:(ArcClassKind)kind;
@end

NS_ASSUME_NONNULL_END

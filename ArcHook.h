//
//  ArcHook.h
//  Arc-shaped WeChat
//
//  零依赖的 Objective-C 运行时 Hook 工具。
//  不依赖 MobileSubstrate / libhooker / ElleKit —— TrollFools 场景下的关键约束：
//    1. TrollFools 虽然会附带注入 CydiaSubstrate，但对"加密的 App Store 应用"只支持
//       裸 dylib 注入，少一个依赖就少一个失败点。
//    2. 注入点可能是微信包内某个未加密的 framework，加载时机不确定，
//       不引入额外 dylib 依赖可以避免 dyld 加载顺序问题。
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

/// 替换类的实例方法。
/// @param cls       目标类（为 NULL 时安全返回 NO）
/// @param sel       目标 selector
/// @param newImp    新的实现
/// @param origPtr   用于接收原始 IMP。若原方法来自父类，这里返回父类实现（等价于 %orig）
/// @return 是否替换成功
BOOL ArcHookInstance(Class _Nullable cls, SEL sel, IMP newImp, IMP _Nullable * _Nullable origPtr);

/// 替换类方法（元类上的实例方法）
BOOL ArcHookClass(Class _Nullable cls, SEL sel, IMP newImp, IMP _Nullable * _Nullable origPtr);

NS_ASSUME_NONNULL_END

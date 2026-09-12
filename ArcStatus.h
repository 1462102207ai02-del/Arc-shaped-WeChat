//
//  ArcStatus.h
//  Arc-shaped WeChat
//
//  运行时自检状态：记录 dylib 是否加载、hook 是否装上、插件注册是否成功。
//  设置页底部会原样显示这些信息，方便在没有电脑的情况下判断插件到底有没有生效。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ArcStatus : NSObject

+ (instancetype)shared;

@property (nonatomic, assign) BOOL dylibLoaded;          // 构造函数已执行
@property (nonatomic, assign) BOOL mgrClassFound;        // 找到 WCPluginsMgr 类
@property (nonatomic, assign) BOOL sharedInstanceOK;     // 拿到 sharedInstance
@property (nonatomic, assign) BOOL registerSelectorOK;   // 响应注册方法
@property (nonatomic, assign) NSInteger registerAttempts;
@property (nonatomic, assign) BOOL registerSucceeded;
@property (nonatomic, copy, nullable) NSString *registerError;
@property (nonatomic, assign) NSInteger hookCount;
@property (nonatomic, strong) NSMutableSet<NSString *> *hookedClasses;

- (void)noteHookedClass:(nullable NSString *)name;

/// 多行诊断文本，直接展示给用户
- (NSString *)diagnosticText;

@end

NS_ASSUME_NONNULL_END

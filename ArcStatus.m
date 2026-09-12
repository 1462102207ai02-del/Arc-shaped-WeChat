//
//  ArcStatus.m
//  Arc-shaped WeChat
//

#import "ArcStatus.h"
#import "ArcPrefs.h"

@implementation ArcStatus

+ (instancetype)shared {
    static ArcStatus *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ArcStatus alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        _hookedClasses = [NSMutableSet set];
        _registerError = nil;
    }
    return self;
}

- (void)noteHookedClass:(NSString *)name {
    if (name.length == 0) { return; }
    if ([self.hookedClasses containsObject:name]) { return; }
    [self.hookedClasses addObject:name];
    _hookCount = (NSInteger)self.hookedClasses.count;
}

- (NSString *)yesNo:(BOOL)v {
    return v ? @"是" : @"否";
}

- (NSString *)diagnosticText {
    ArcPrefs *prefs = [ArcPrefs shared];
    NSMutableArray<NSString *> *lines = [NSMutableArray array];

    [lines addObject:[NSString stringWithFormat:@"插件已加载：%@", [self yesNo:self.dylibLoaded]]];
    [lines addObject:[NSString stringWithFormat:@"总开关：%@（关闭时所有改动都会还原）",
                      prefs.enabled ? @"开启" : @"关闭"]];
    [lines addObject:[NSString stringWithFormat:@"配置文件可写：%@",
                      [self yesNo:[self prefsWritable]]]];
    [lines addObject:@""];
    [lines addObject:@"—— 插件收纳入口 ——"];
    [lines addObject:[NSString stringWithFormat:@"找到 WCPluginsMgr：%@", [self yesNo:self.mgrClassFound]]];
    [lines addObject:[NSString stringWithFormat:@"拿到 sharedInstance：%@", [self yesNo:self.sharedInstanceOK]]];
    [lines addObject:[NSString stringWithFormat:@"响应注册方法：%@", [self yesNo:self.registerSelectorOK]]];
    [lines addObject:[NSString stringWithFormat:@"注册尝试次数：%ld", (long)self.registerAttempts]];
    [lines addObject:[NSString stringWithFormat:@"注册成功：%@", [self yesNo:self.registerSucceeded]]];
    if (self.registerError.length > 0) {
        [lines addObject:[NSString stringWithFormat:@"错误信息：%@", self.registerError]];
    }
    [lines addObject:@""];
    [lines addObject:[NSString stringWithFormat:@"已挂载 hook：%ld 个", (long)self.hookCount]];

    return [lines componentsJoinedByString:@"\n"];
}

- (BOOL)prefsWritable {
    NSString *path = [ArcPrefs shared].filePath;
    if (path.length == 0) { return NO; }
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) { return NO; }
    return [fm isWritableFileAtPath:path];
}

@end

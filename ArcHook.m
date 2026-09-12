//
//  ArcHook.m
//  Arc-shaped WeChat
//

#import "ArcHook.h"

BOOL ArcHookInstance(Class cls, SEL sel, IMP newImp, IMP *origPtr) {
    if (!cls || !sel || !newImp) {
        return NO;
    }

    Method method = class_getInstanceMethod(cls, sel);
    if (!method) {
        return NO;
    }

    const char *types = method_getTypeEncoding(method);
    IMP inherited = method_getImplementation(method);

    // 先尝试在本类新增方法。成功 => 说明本类原本没实现，inherited 是父类的实现，
    // 正好作为 %orig 使用。
    if (class_addMethod(cls, sel, newImp, types)) {
        if (origPtr) { *origPtr = inherited; }
        return YES;
    }

    // 本类已实现：直接替换，并把旧实现交回去
    IMP replaced = method_setImplementation(method, newImp);
    if (origPtr) { *origPtr = replaced ?: inherited; }
    return YES;
}

BOOL ArcHookClass(Class cls, SEL sel, IMP newImp, IMP *origPtr) {
    if (!cls) { return NO; }
    return ArcHookInstance(object_getClass((id)cls), sel, newImp, origPtr);
}

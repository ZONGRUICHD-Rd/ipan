#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Swift 无法捕获 Objective-C 异常（NSException）。AVFoundation 的部分接口在参数或调用时机不对时会直接抛异常，
/// 导致闪退；用这个包一层，失败时转成 Swift 的 Error。
@interface IPANObjC : NSObject

+ (BOOL)tryBlock:(NS_NOESCAPE void (^)(void))block error:(NSError * _Nullable * _Nullable)error
    NS_SWIFT_NAME(catching(_:));

@end

NS_ASSUME_NONNULL_END

#import "IPANObjC.h"

@implementation IPANObjC

+ (BOOL)tryBlock:(NS_NOESCAPE void (^)(void))block error:(NSError * _Nullable * _Nullable)error {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            NSString *reason = exception.reason ?: exception.name;
            *error = [NSError errorWithDomain:@"iPAN.ObjCException"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: reason,
                                                @"name": exception.name}];
        }
        return NO;
    }
}

@end

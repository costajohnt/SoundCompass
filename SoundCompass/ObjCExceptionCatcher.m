#import "ObjCExceptionCatcher.h"

@implementation ObjCExceptionCatcher

+ (nullable NSString *)tryBlock:(void (^)(void))block {
    @try {
        block();
        return nil;
    } @catch (NSException *exception) {
        return [NSString stringWithFormat:@"%@: %@ | %@",
                exception.name,
                exception.reason ?: @"(no reason)",
                [[exception.callStackSymbols subarrayWithRange:NSMakeRange(0, MIN(5, exception.callStackSymbols.count))] componentsJoinedByString:@"\n"]];
    }
}

@end

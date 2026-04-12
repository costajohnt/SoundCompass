#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ObjCExceptionCatcher : NSObject
/// Runs the block. Returns nil on success, or the exception description on failure.
+ (nullable NSString *)tryBlock:(void (^)(void))block;
@end

NS_ASSUME_NONNULL_END

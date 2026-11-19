#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

/// A virtual screen made through Apple's private CGVirtualDisplay interface,
/// looked up when it runs, so a macOS without it still builds the package.
/// The screen exists while this object lives; releasing it removes the screen.
@interface MSRVirtualScreen : NSObject

/// Whether this macOS has the private interface.
@property (class, readonly) BOOL isAvailable;

@property (readonly) CGDirectDisplayID displayID;

/// A screen with one mode at 1x and 60 Hz for each size (points as
/// CGSize in NSValue), the first one first; nil when macOS refuses it, such
/// as a second screen with the same vendor, product and serial number.
- (nullable instancetype)initWithName:(NSString *)name
                             vendorID:(uint32_t)vendorID
                            productID:(uint32_t)productID
                         serialNumber:(uint32_t)serialNumber
                                sizes:(NSArray<NSValue *> *)sizes;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

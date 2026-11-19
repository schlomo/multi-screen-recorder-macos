#import "VirtualScreen.h"

// The private interface's declarations, our own: the classes are looked up
// by name when this runs, never linked, so nothing here needs them to build.
@protocol MSRCGVirtualDisplayDescriptor <NSObject>
@property (retain, nonatomic) NSString *name;
@property (nonatomic) unsigned int maxPixelsWide;
@property (nonatomic) unsigned int maxPixelsHigh;
@property (nonatomic) CGSize sizeInMillimeters;
@property (nonatomic) unsigned int productID;
@property (nonatomic) unsigned int vendorID;
@property (nonatomic) unsigned int serialNum;
@property (retain, nonatomic) dispatch_queue_t queue;
@end

@protocol MSRCGVirtualDisplayMode <NSObject>
- (instancetype)initWithWidth:(unsigned int)width height:(unsigned int)height refreshRate:(double)refreshRate;
@end

@protocol MSRCGVirtualDisplaySettings <NSObject>
@property (retain, nonatomic) NSArray *modes;
@property (nonatomic) unsigned int hiDPI;
@end

@protocol MSRCGVirtualDisplay <NSObject>
- (instancetype)initWithDescriptor:(id<MSRCGVirtualDisplayDescriptor>)descriptor;
- (BOOL)applySettings:(id<MSRCGVirtualDisplaySettings>)settings;
@property (readonly, nonatomic) unsigned int displayID;
@end

static const double MSRMillimetresPerPoint = 25.4 / 96.0;

@implementation MSRVirtualScreen {
    id<MSRCGVirtualDisplay> _display;
}

+ (BOOL)isAvailable {
    return NSClassFromString(@"CGVirtualDisplay") && NSClassFromString(@"CGVirtualDisplayDescriptor")
        && NSClassFromString(@"CGVirtualDisplayMode") && NSClassFromString(@"CGVirtualDisplaySettings");
}

- (nullable instancetype)initWithName:(NSString *)name
                             vendorID:(uint32_t)vendorID
                            productID:(uint32_t)productID
                         serialNumber:(uint32_t)serialNumber
                                sizes:(NSArray<NSValue *> *)sizes {
    if (!(self = [super init]) || !MSRVirtualScreen.isAvailable || sizes.count == 0) {
        return nil;
    }
    unsigned int width = 0, height = 0;
    NSMutableArray *modes = [NSMutableArray array];
    for (NSValue *value in sizes) {
        CGSize size = value.sizeValue;
        width = MAX(width, (unsigned int)size.width);
        height = MAX(height, (unsigned int)size.height);
        [modes addObject:[(id<MSRCGVirtualDisplayMode>)[NSClassFromString(@"CGVirtualDisplayMode") alloc]
                             initWithWidth:(unsigned int)size.width height:(unsigned int)size.height refreshRate:60]];
    }
    id<MSRCGVirtualDisplayDescriptor> descriptor = [NSClassFromString(@"CGVirtualDisplayDescriptor") new];
    descriptor.name = name;
    descriptor.maxPixelsWide = width;
    descriptor.maxPixelsHigh = height;
    descriptor.sizeInMillimeters = CGSizeMake(width * MSRMillimetresPerPoint, height * MSRMillimetresPerPoint);
    descriptor.vendorID = vendorID;
    descriptor.productID = productID;
    descriptor.serialNum = serialNumber;
    descriptor.queue = dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0);

    id<MSRCGVirtualDisplay> display = [(id<MSRCGVirtualDisplay>)[NSClassFromString(@"CGVirtualDisplay") alloc]
        initWithDescriptor:descriptor];
    if (!display || display.displayID == kCGNullDirectDisplay) {
        return nil;
    }
    id<MSRCGVirtualDisplaySettings> settings = [NSClassFromString(@"CGVirtualDisplaySettings") new];
    settings.hiDPI = 0;
    settings.modes = modes;
    if (![display applySettings:settings]) {
        return nil;
    }
    _display = display;
    return self;
}

- (CGDirectDisplayID)displayID {
    return _display.displayID;
}

@end

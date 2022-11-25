#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>

@class Landmark;
@class HandTracker;

NS_ASSUME_NONNULL_BEGIN

typedef void(^DeactivateCallback)();

@interface Packet: NSObject
-(NSArray<NSData *> *)getArrayOfProtos;
@property (readonly) NSString *getTypeName;
@property (readonly) int64_t timestampMicroseconds;
@property (readonly) NSDate *date;
@end

@protocol HandTrackerDelegate <NSObject>
- (void)handTracker: (HandTracker*)handTracker didOutputPacket: (Packet *)packet forStream:(NSString *)streamName;
- (void)handTracker: (HandTracker*)handTracker didOutputPixelBuffer: (CVPixelBufferRef)pixelBuffer;
@end

@interface HandTracker : NSObject
- (instancetype)init;
- (void)startGraph;
- (void)processVideoFrame:(CVPixelBufferRef)imageBuffer;

- (void)enableImageOutputStream;
- (void)setNumberOfHands:(NSInteger)numberOfHands;
- (void)deactivateWithCompletionHandler:(nullable DeactivateCallback)handler;

- (void)addFrameOutputStreamNamed:(NSString *)streamName;

@property (weak, nonatomic) id <HandTrackerDelegate> delegate;
@end

NS_ASSUME_NONNULL_END

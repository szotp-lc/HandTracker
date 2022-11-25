#import "HandTracker.h"
#import "mediapipe/objc/MPPGraph.h"
#import "mediapipe/objc/MPPCameraInputSource.h"
#import "mediapipe/objc/MPPLayerRenderer.h"
#include "mediapipe/framework/formats/landmark.pb.h"
#include "mediapipe/framework/tool/sink.h"

static NSString* const kGraphName = @"hand_tracking_mobile_gpu";
static const char* kInputStream = "input_video";
static const char* kOutputStream = "output_video";
static const char* kLandmarksOutputStream = "hand_landmarks";
static const char* kVideoQueueLabel = "com.google.mediapipe.example.videoQueue";

static const char* kNumHandsInputSidePacket = "num_hands";

@interface HandTracker() <MPPGraphDelegate>
@property(nonatomic) MPPGraph* mediapipeGraph;
@end

@interface Packet ()
@property ::mediapipe::Packet packet;
@end
@implementation Packet

- (int64)timestampMicroseconds {
    return self.packet.Timestamp().Microseconds();
}

- (NSArray<NSData *> *)getArrayOfProtos {
    NSMutableArray *messages = [NSMutableArray new];
    auto vector = self.packet.GetVectorOfProtoMessageLitePtrs().value();
    
    std::string serialized;
    
    for(auto &message: vector) {
        auto serialized = message->SerializeAsString();
        [messages addObject:[NSData dataWithBytes:serialized.data() length:serialized.length()]];
        message->AppendToString(&serialized);
    }

    return messages;
}

- (NSString *)getTypeName {
    auto name = self.packet.GetTypeId().name();
    return [NSString stringWithCString:name.c_str() encoding:NSUTF8StringEncoding];
}

@end

@implementation HandTracker {
}

#pragma mark - Cleanup methods

- (void)deactivateWithCompletionHandler:(nullable DeactivateCallback)handler {
    self.mediapipeGraph.delegate = nil;
    [self.mediapipeGraph cancel];
    // Ignore errors since we're cleaning up.
    [self.mediapipeGraph closeAllInputStreamsWithError:nil];
    
    MPPGraph * graph = self.mediapipeGraph;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [graph waitUntilDoneWithError:nil];
        
        if (handler) {
            dispatch_async(dispatch_get_main_queue(), ^{
                handler();
            });
        }
    });
}

- (void)dealloc {
    if (self.mediapipeGraph) {
        [self deactivateWithCompletionHandler: nil];
    }
}

#pragma mark - MediaPipe graph methods

+ (MPPGraph*)loadGraphFromResource:(NSString*)resource {
    // Load the graph config resource.
    NSError* configLoadError = nil;
    NSBundle* bundle = [NSBundle bundleForClass:[self class]];
    if (!resource || resource.length == 0) {
        return nil;
    }
    NSURL* graphURL = [bundle URLForResource:resource withExtension:@"binarypb"];
    NSData* data = [NSData dataWithContentsOfURL:graphURL options:0 error:&configLoadError];
    if (!data) {
        NSLog(@"Failed to load MediaPipe graph config: %@", configLoadError);
        return nil;
    }
    
    // Parse the graph config resource into mediapipe::CalculatorGraphConfig proto object.
    mediapipe::CalculatorGraphConfig config;
    config.ParseFromArray(data.bytes, data.length);
    
    
    // Create MediaPipe graph with mediapipe::CalculatorGraphConfig proto object.
    MPPGraph* newGraph = [[MPPGraph alloc] initWithGraphConfig:config];
    return newGraph;
}

- (void)enableImageOutputStream {
    [self.mediapipeGraph addFrameOutputStream:kOutputStream outputPacketType:MPPPacketTypePixelBuffer];
}

- (void)addFrameOutputStreamNamed:(NSString *)streamName {
    std::string streamNameRaw([streamName UTF8String]);
    [self.mediapipeGraph addFrameOutputStream:streamNameRaw outputPacketType:MPPPacketTypeRaw];
}

- (void)setNumberOfHands:(NSInteger)numberOfHands {
    [self.mediapipeGraph setSidePacket:(mediapipe::MakePacket<int>(numberOfHands)) named:kNumHandsInputSidePacket];
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.mediapipeGraph = [[self class] loadGraphFromResource:kGraphName];
        [self enableImageOutputStream];
        self.mediapipeGraph.delegate = self;
        // Set maxFramesInFlight to a small value to avoid memory contention for real-time processing.
        self.mediapipeGraph.maxFramesInFlight = 2;
    }
    return self;
}

- (void)startGraph {
    // Start running self.mediapipeGraph.
    NSError* error;
    if (![self.mediapipeGraph startWithError:&error]) {
        NSLog(@"Failed to start graph: %@", error);
    }
}

#pragma mark - MPPGraphDelegate methods

// Receives CVPixelBufferRef from the MediaPipe graph. Invoked on a MediaPipe worker thread.
- (void)mediapipeGraph:(MPPGraph*)graph
  didOutputPixelBuffer:(CVPixelBufferRef)pixelBuffer
            fromStream:(const std::string&)streamName {
    
      if (streamName == kOutputStream) {
          [_delegate handTracker: self didOutputPixelBuffer: pixelBuffer];
      }
}

// Receives a raw packet from the MediaPipe graph. Invoked on a MediaPipe worker thread.
- (void)mediapipeGraph:(MPPGraph*)graph
       didOutputPacket:(const ::mediapipe::Packet&)packet
            fromStream:(const std::string&)streamName {

    NSString *streamNameParsed = [NSString stringWithUTF8String:streamName.c_str()];
    Packet *output = [Packet new];
    output.packet = packet;
    [_delegate handTracker:self didOutputPacket:output forStream:streamNameParsed];
}

- (void)processVideoFrame:(CVPixelBufferRef)imageBuffer {
    [self.mediapipeGraph sendPixelBuffer:imageBuffer
                              intoStream:kInputStream
                              packetType:MPPPacketTypePixelBuffer];
}

@end

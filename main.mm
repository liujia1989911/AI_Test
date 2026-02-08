#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <simd/simd.h>

#include <chrono>
#include <iostream>
#include <vector>

struct Vertex {
    simd::float2 position;
    simd::float3 color;
};

struct InstanceData {
    simd::float2 offset;
    float scale;
    float padding;
};

struct FrameUniforms {
    float time;
    simd::float2 viewportSize;
    float padding;
};

static std::vector<InstanceData> BuildInstances(size_t count) {
    std::vector<InstanceData> instances;
    instances.reserve(count);
    const float gridSize = static_cast<float>(std::ceil(std::sqrt(static_cast<double>(count))));
    const float spacing = 2.0f / gridSize;

    for (size_t i = 0; i < count; ++i) {
        const float x = static_cast<float>(i % static_cast<size_t>(gridSize));
        const float y = static_cast<float>(i / static_cast<size_t>(gridSize));
        const float offsetX = -1.0f + spacing * (x + 0.5f);
        const float offsetY = -1.0f + spacing * (y + 0.5f);
        InstanceData data;
        data.offset = {offsetX, offsetY};
        data.scale = spacing * 0.35f;
        data.padding = 0.0f;
        instances.push_back(data);
    }
    return instances;
}

@interface Renderer : NSObject <MTKViewDelegate>
@end

@implementation Renderer {
    id<MTLDevice> _device;
    id<MTLCommandQueue> _commandQueue;
    id<MTLRenderPipelineState> _pipelineState;
    id<MTLBuffer> _vertexBuffer;
    id<MTLBuffer> _instanceBuffer;
    id<MTLBuffer> _uniformBuffer;
    NSUInteger _instanceCount;
    std::chrono::steady_clock::time_point _startTime;
    std::chrono::steady_clock::time_point _lastFpsTime;
    uint64_t _frames;
}

- (instancetype)initWithMetalKitView:(MTKView *)mtkView instanceCount:(NSUInteger)instanceCount {
    if ((self = [super init])) {
        _device = mtkView.device;
        _commandQueue = [_device newCommandQueue];
        _instanceCount = instanceCount;
        _startTime = std::chrono::steady_clock::now();
        _lastFpsTime = _startTime;
        _frames = 0;

        NSError *error = nil;
        id<MTLLibrary> library = [_device newDefaultLibrary];
        if (!library) {
            std::cerr << "Failed to load default Metal library." << std::endl;
            return nil;
        }

        MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        pipelineDescriptor.vertexFunction = [library newFunctionWithName:@"vertex_main"];
        pipelineDescriptor.fragmentFunction = [library newFunctionWithName:@"fragment_main"];
        pipelineDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat;

        _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
        if (!_pipelineState) {
            std::cerr << "Failed to create pipeline state: "
                      << (error ? [[error localizedDescription] UTF8String] : "unknown")
                      << std::endl;
            return nil;
        }

        static const Vertex kVertices[] = {
            {{0.0f, 0.6f}, {1.0f, 0.2f, 0.3f}},
            {{-0.5f, -0.3f}, {0.2f, 0.8f, 0.4f}},
            {{0.5f, -0.3f}, {0.2f, 0.4f, 1.0f}},
        };

        _vertexBuffer = [_device newBufferWithBytes:kVertices
                                             length:sizeof(kVertices)
                                            options:MTLResourceStorageModeShared];
        if (!_vertexBuffer) {
            std::cerr << "Failed to create vertex buffer." << std::endl;
            return nil;
        }

        std::vector<InstanceData> instances = BuildInstances(instanceCount);
        _instanceBuffer = [_device newBufferWithBytes:instances.data()
                                               length:instances.size() * sizeof(InstanceData)
                                              options:MTLResourceStorageModeShared];
        if (!_instanceBuffer) {
            std::cerr << "Failed to create instance buffer." << std::endl;
            return nil;
        }

        _uniformBuffer = [_device newBufferWithLength:sizeof(FrameUniforms)
                                              options:MTLResourceStorageModeShared];
        if (!_uniformBuffer) {
            std::cerr << "Failed to create uniform buffer." << std::endl;
            return nil;
        }
    }
    return self;
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    (void)view;
    FrameUniforms *uniforms = (FrameUniforms *)[_uniformBuffer contents];
    uniforms->viewportSize = {(float)size.width, (float)size.height};
}

- (void)drawInMTKView:(MTKView *)view {
    @autoreleasepool {
        auto now = std::chrono::steady_clock::now();
        std::chrono::duration<float> elapsed = now - _startTime;

        FrameUniforms *uniforms = (FrameUniforms *)[_uniformBuffer contents];
        uniforms->time = elapsed.count();
        uniforms->viewportSize = {(float)view.drawableSize.width, (float)view.drawableSize.height};
        uniforms->padding = 0.0f;

        id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
        MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;
        if (!renderPassDescriptor) {
            return;
        }

        id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        [encoder setRenderPipelineState:_pipelineState];
        [encoder setVertexBuffer:_vertexBuffer offset:0 atIndex:0];
        [encoder setVertexBuffer:_instanceBuffer offset:0 atIndex:1];
        [encoder setVertexBuffer:_uniformBuffer offset:0 atIndex:2];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3 instanceCount:_instanceCount];
        [encoder endEncoding];

        [commandBuffer presentDrawable:view.currentDrawable];
        [commandBuffer commit];

        _frames += 1;
        std::chrono::duration<float> fpsElapsed = now - _lastFpsTime;
        if (fpsElapsed.count() >= 1.0f) {
            float fps = _frames / fpsElapsed.count();
            std::cout << "FPS: " << fps << " | Instances: " << _instanceCount << std::endl;
            _frames = 0;
            _lastFpsTime = now;
        }
    }
}

@end

static NSUInteger ParseInstanceCount(int argc, const char *argv[]) {
    const NSUInteger kDefaultInstances = 20000;
    for (int i = 1; i < argc; ++i) {
        if (std::string(argv[i]) == "--instances" && i + 1 < argc) {
            return static_cast<NSUInteger>(std::stoul(argv[i + 1]));
        }
    }
    return kDefaultInstances;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];

        NSUInteger instanceCount = ParseInstanceCount(argc, argv);
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) {
            std::cerr << "Metal is not supported on this system." << std::endl;
            return 1;
        }

        NSRect frame = NSMakeRect(0, 0, 960, 540);
        NSUInteger style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable;
        NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                       styleMask:style
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
        [window setTitle:@"Metal GPU Stress Test"]; 
        [window makeKeyAndOrderFront:nil];

        MTKView *view = [[MTKView alloc] initWithFrame:frame device:device];
        view.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
        view.clearColor = MTLClearColorMake(0.05, 0.05, 0.08, 1.0);
        view.preferredFramesPerSecond = 120;
        view.enableSetNeedsDisplay = NO;
        view.paused = NO;

        Renderer *renderer = [[Renderer alloc] initWithMetalKitView:view instanceCount:instanceCount];
        if (!renderer) {
            return 1;
        }
        view.delegate = renderer;
        [window setContentView:view];

        [app activateIgnoringOtherApps:YES];
        [app run];
    }
    return 0;
}

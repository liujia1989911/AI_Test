#include <metal_stdlib>
using namespace metal;

struct Vertex {
    float2 position [[attribute(0)]];
    float3 color [[attribute(1)]];
};

struct InstanceData {
    float2 offset;
    float scale;
    float padding;
};

struct FrameUniforms {
    float time;
    float2 viewportSize;
    float padding;
};

struct Varying {
    float4 position [[position]];
    float3 color;
};

vertex Varying vertex_main(uint vertexId [[vertex_id]],
                           uint instanceId [[instance_id]],
                           const device Vertex *vertices [[buffer(0)]],
                           const device InstanceData *instances [[buffer(1)]],
                           const device FrameUniforms &uniforms [[buffer(2)]]) {
    Vertex v = vertices[vertexId];
    InstanceData inst = instances[instanceId];

    float angle = uniforms.time * 0.5 + (float)instanceId * 0.001;
    float s = sin(angle);
    float c = cos(angle);
    float2 rotated = float2(v.position.x * c - v.position.y * s,
                            v.position.x * s + v.position.y * c);

    float2 position = rotated * inst.scale + inst.offset;

    Varying out;
    out.position = float4(position, 0.0, 1.0);
    out.color = v.color;
    return out;
}

fragment float4 fragment_main(Varying in [[stage_in]]) {
    float pulse = 0.5 + 0.5 * sin(in.color.r * 6.283 + in.position.x * 3.0);
    float3 color = mix(in.color, float3(pulse, 1.0 - pulse, 0.8), 0.35);
    return float4(color, 1.0);
}

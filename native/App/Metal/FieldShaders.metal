//  Drawing the particle field.
//
//  Unlike the powder grid, which is a picture the engine has already finished, the particle
//  field is drawn as geometry: a point per body, and a line per spring. That is the whole
//  reason the field can hold a million bodies — the GPU places them, and nothing on the
//  processor touches a pixel.
//
//  What is still not decided here is colour. The engine works out what shade each body should
//  be and hands over a finished value, so every colour rule stays where it can be compared
//  against the reference implementation. This file positions things and clips them to a disc.

#include <metal_stdlib>
using namespace metal;

struct FieldUniforms {
    // The simulation's own dimensions, which have nothing to do with the view's.
    float2 worldSize;
    // How wide a body is drawn, in screen pixels.
    float pointSize;
};

struct PointOut {
    float4 position [[position]];
    float size [[point_size]];
    half4 color;
};

// Unpacks the engine's colour, which is stored red-first with the alpha on top.
static inline half4 unpackColor(uint packed) {
    return half4(half(packed & 0xFFu),
                 half((packed >> 8) & 0xFFu),
                 half((packed >> 16) & 0xFFu),
                 half((packed >> 24) & 0xFFu)) / 255.0h;
}

// World coordinates into the space the GPU draws in.
//
// The world's vertical axis grows downward, the way a screen is described and the way every
// coordinate in the simulation is written. The GPU's grows upward. Hence the flip — getting it
// wrong draws the field upside down, which reads as a physics bug at first glance.
static inline float4 worldToClip(float2 world, float2 worldSize) {
    return float4((world.x / worldSize.x) * 2.0 - 1.0,
                  1.0 - (world.y / worldSize.y) * 2.0,
                  0.0,
                  1.0);
}

vertex PointOut particleVertex(uint index [[vertex_id]],
                               const device float2 *positions [[buffer(0)]],
                               const device uint *colors [[buffer(1)]],
                               constant FieldUniforms &uniforms [[buffer(2)]]) {
    PointOut out;
    out.position = worldToClip(positions[index], uniforms.worldSize);
    out.size = uniforms.pointSize;
    out.color = unpackColor(colors[index]);
    return out;
}

fragment half4 particleFragment(PointOut in [[stage_in]],
                                float2 coordinate [[point_coord]]) {
    // Clipped to a disc. A point arrives as a square, and a field of squares reads as a grid
    // of tiles rather than as a cloud of particles — especially where they overlap.
    float2 offset = coordinate - float2(0.5);
    if (length_squared(offset) > 0.25) {
        discard_fragment();
    }
    return in.color;
}

// Springs. Drawn as plain lines in one flat colour, because they are structure rather than
// substance — what matters is seeing which bodies are joined, not the joins themselves.
struct LineOut {
    float4 position [[position]];
};

vertex LineOut springVertex(uint index [[vertex_id]],
                            const device float2 *positions [[buffer(0)]],
                            constant FieldUniforms &uniforms [[buffer(2)]]) {
    LineOut out;
    out.position = worldToClip(positions[index], uniforms.worldSize);
    return out;
}

fragment half4 springFragment() {
    // The same near-white the interface uses for a hairline, at the same weight, so a cloth
    // reads as part of the lab rather than as something drawn on top of it.
    return half4(0.784h, 0.800h, 0.831h, 0.45h);
}

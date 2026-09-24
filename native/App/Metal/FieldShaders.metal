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


// Trails.
//
// A short polyline behind each moving body, in that body's own colour at a flat three-tenths
// opacity. Not a taper — the reference implementation strokes the whole length at one alpha, and
// a taper would look better and would not be what it does.
//
// Separate from the spring pipeline because these carry a colour per vertex, where a spring is
// one flat near-white for all of them.
struct TrailOut {
    float4 position [[position]];
    half4 color;
};

vertex TrailOut trailVertex(uint index [[vertex_id]],
                            const device float2 *positions [[buffer(0)]],
                            const device uint *colors [[buffer(1)]],
                            constant FieldUniforms &uniforms [[buffer(2)]]) {
    TrailOut out;
    out.position = worldToClip(positions[index], uniforms.worldSize);
    out.color = unpackColor(colors[index]);
    return out;
}

fragment half4 trailFragment(TrailOut in [[stage_in]]) {
    return in.color;
}

// The ring round your finger.
//
// Drawn as a screen-filling pair of triangles with the circle worked out per pixel, rather than as
// a point or a fan of triangles. Two reasons, and the first is the deciding one:
//
//   - At the top of its range the pull has no limit, and the ring is then drawn large enough to
//     cover the whole world — which can be several thousand pixels across. A point sprite has a
//     hardware size ceiling far below that, and a triangle fan would need enough segments to keep
//     a circle that large from looking like a polygon.
//   - The outline, the wash inside it and the centre dot are then one calculation each rather than
//     three separate pieces of geometry.

// The four-component colour comes first deliberately. It needs sixteen-byte alignment, so putting
// it after the single floats would leave a hole that both sides have to agree about the size of --
// and a disagreement there does not fail to compile, it silently reads the wrong fields and draws
// a ring somewhere unexpected. In this order the fields simply follow one another.
struct RingUniforms {
    float4 color;
    // Where the finger is, in world coordinates.
    float2 centre;
    float radius;
    // Thickness of the outline, in world units so it stays put as the view scales.
    float strokeWidth;
    float centreDotRadius;
    float strokeOpacity;
    float fillOpacity;
};

struct RingOut {
    float4 position [[position]];
    float2 world;
};

vertex RingOut ringVertex(uint index [[vertex_id]],
                          constant FieldUniforms &uniforms [[buffer(2)]]) {
    // Four corners from the vertex number alone, drawn as a triangle strip. No vertex buffer
    // needed for a shape that is always the whole screen.
    float2 corner = float2((index & 1) ? 1.0 : 0.0, (index & 2) ? 1.0 : 0.0);
    RingOut out;
    out.world = corner * uniforms.worldSize;
    out.position = worldToClip(out.world, uniforms.worldSize);
    return out;
}

fragment half4 ringFragment(RingOut in [[stage_in]],
                            constant RingUniforms &ring [[buffer(0)]]) {
    float distance = length(in.world - ring.centre);

    // The solid dot marking exactly where the finger is. Without it, a very large ring gives no
    // clue where its centre actually is.
    if (distance <= ring.centreDotRadius) {
        return half4(half3(ring.color.rgb), 1.0h);
    }

    // The outline. Compared against half the width either side of the radius so the line straddles
    // the true circle rather than sitting inside it.
    float edge = abs(distance - ring.radius);
    if (edge <= ring.strokeWidth * 0.5) {
        return half4(half3(ring.color.rgb), half(ring.strokeOpacity));
    }

    // The wash inside.
    if (distance < ring.radius) {
        return half4(half3(ring.color.rgb), half(ring.fillOpacity));
    }

    // Outside the ring entirely. Discarded rather than returned transparent, which would still cost
    // a blend for every pixel of the screen.
    discard_fragment();
    return half4(0.0h);
}


// The fading backdrop, which is what makes a trail look like motion.
//
// The reference implementation does not clear the picture between frames. It paints the background
// colour over it at a quarter opacity, so whatever was there before survives at three quarters and
// then a little over half, and so on — fading out over roughly a dozen frames. A trail is therefore
// much longer than the six positions a body actually remembers.
//
// Reproducing that needs a picture that survives between frames, which a screen's drawable does not:
// the system hands out a different one each time. So the field is drawn into a texture of its own
// that persists, and this is what dims it before each new frame goes on top.
//
// Reuses the ring's vertex function, which already covers the screen from the vertex number alone.
struct FadeUniforms {
    float4 color;
};

fragment half4 fadeFragment(RingOut in [[stage_in]],
                            constant FadeUniforms &fade [[buffer(0)]]) {
    // Blended over what is already there, so the alpha is the fraction of the old picture that is
    // replaced rather than kept.
    return half4(half3(fade.color.rgb), half(fade.color.a));
}

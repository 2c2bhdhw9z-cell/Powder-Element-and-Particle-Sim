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

// Laid out so every field sits on its natural alignment and there is no padding for the two sides
// to disagree about. Two-component floats want eight bytes, so they come first, in pairs; the plain
// floats fill the end. A disagreement here does not fail to compile — it reads the wrong fields and
// draws the field somewhere unexpected.
struct FieldUniforms {
    // The simulation's own dimensions, which have nothing to do with the view's.
    float2 worldSize;
    // The view's dimensions, in the same points the pan is measured in.
    float2 viewSize;
    // Sideways and vertical shift, in screen points.
    float2 pan;
    // Turn about the upright axis and tip toward the viewer, in radians.
    float2 orbit;
    // How wide a body is drawn, in screen pixels.
    float pointSize;
    // How far in the view is pushed.
    float zoom;
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

// How far the eye sits from the plane, and how close to it the maths may get before it stops
// dividing. Both have to match `ParticleCamera` exactly — the processor un-projects a touch with the
// same numbers, and a mismatch puts the brush somewhere other than where the finger is.
constant float kEyeDistance = 2.4;
constant float kNearLimit = 0.2;
constant float kMinDepthScale = 0.35;
constant float kMaxDepthScale = 2.8;

// World coordinates into the space the GPU draws in, through the camera.
//
// The world's vertical axis grows downward, the way a screen is described and the way every
// coordinate in the simulation is written. The GPU's grows upward. Hence the flip — getting it
// wrong draws the field upside down, which reads as a physics bug at first glance.
//
// The turn and tip are a real perspective over a flat plane, not a rotation of the finished picture:
// the plane is genuinely tilted in space and then divided through by depth, so the near half of it
// draws larger than the far half and a ring of bodies becomes a proper ellipse. There is one plane,
// at depth nought, and no depth buffer, so nothing occludes anything — which is deliberate, because
// tens of thousands of translucent points read better added together than sorted.
//
// `depthScale` comes back out because the body's drawn size has to follow it. The reference
// implementation clamped that on the graphics card and not on the processor, so its own two drawing
// paths disagreed about how big a tilted body was; here there is one rule and `ParticleCamera` holds
// the same one.
static inline float4 worldToClip(float2 world, constant FieldUniforms &u, thread float &depthScale) {
    float2 n = float2((world.x / max(u.worldSize.x, 1e-6)) * 2.0 - 1.0,
                      1.0 - (world.y / max(u.worldSize.y, 1e-6)) * 2.0);
    depthScale = 1.0;

    // Exactly the identity when nothing is turned, so leaving the camera alone leaves the picture
    // bit for bit as it was before the camera existed.
    if (abs(u.orbit.x) > 1e-9 || abs(u.orbit.y) > 1e-9) {
        float cy = cos(u.orbit.x), sy = sin(u.orbit.x);
        float cp = cos(u.orbit.y), sp = sin(u.orbit.y);

        // Turn about the upright axis. The plane sits at depth nought, so only sideways position
        // feeds depth.
        float x1 = n.x * cy;
        float z1 = -n.x * sy;
        // Then tip about the sideways axis.
        float y2 = n.y * cp - z1 * sp;
        float z2 = n.y * sp + z1 * cp;
        // And divide through by how far away it ended up.
        float perspective = kEyeDistance / max(kEyeDistance - z2, kNearLimit);
        n = float2(x1, y2) * perspective;
        depthScale = perspective;
    }

    // Zoom and pan last. Before the turn, and zooming in would also swing the view round, because
    // the turn happens about the middle of the world rather than the middle of what is on screen.
    // The vertical pan subtracts where the horizontal adds: down the screen is down the picture, and
    // the picture's vertical axis runs the other way.
    float2 half = max(u.viewSize * 0.5, float2(1e-6));
    n = n * u.zoom + float2(u.pan.x / half.x, -u.pan.y / half.y);

    return float4(n, 0.0, 1.0);
}

// For the pipelines that draw lines, which have no size to scale.
static inline float4 worldToClip(float2 world, constant FieldUniforms &u) {
    float ignored;
    return worldToClip(world, u, ignored);
}

vertex PointOut particleVertex(uint index [[vertex_id]],
                               const device float2 *positions [[buffer(0)]],
                               const device uint *colors [[buffer(1)]],
                               constant FieldUniforms &uniforms [[buffer(2)]]) {
    PointOut out;
    float depthScale;
    out.position = worldToClip(positions[index], uniforms, depthScale);
    // Zoomed in, bodies grow with the view; tilted, the near half of the plane grows and the far
    // half shrinks. Clamped, because a body drawn at a hundredth of a pixel is invisible and one
    // drawn at twelve times its size is a blob that hides everything behind it.
    out.size = max(1.0, uniforms.pointSize * uniforms.zoom
                        * clamp(depthScale, kMinDepthScale, kMaxDepthScale));
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
    out.position = worldToClip(positions[index], uniforms);
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
    out.position = worldToClip(positions[index], uniforms);
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
// Measured in screen pixels rather than world units, now that there is a camera.
//
// It used to be world units, because the world was the screen and the two were the same thing. They
// are not any more: a ring specified in world units would be transformed along with the bodies, and
// under a tilt a circle does not stay a circle — the ring would arrive as a lopsided egg drawn round
// a finger that is perfectly round. So the centre and the radius are put through the camera on the
// processor and handed over already in screen pixels, and the outline keeps a constant thickness on
// screen however far the view is zoomed, which is what an interface affordance should do.
struct RingUniforms {
    float4 color;
    // Where the finger is, in screen pixels measured from the top left.
    float2 centre;
    float radius;
    // Thickness of the outline, in screen pixels.
    float strokeWidth;
    float centreDotRadius;
    float strokeOpacity;
    float fillOpacity;
};

struct RingOut {
    float4 position [[position]];
    // Screen pixels, from the top left, matching the ring's own units.
    float2 screen;
};

// Covers the whole screen, straight in the space the GPU draws in.
//
// Deliberately not routed through the camera. This quad and the fading backdrop that shares it both
// need to cover the view exactly — a quad built in world coordinates and then transformed would shrink,
// slide or rotate with the view, and the fade would stop reaching the corners. Trails would then smear
// permanently round the outside of a tilted field, which is the sort of fault that looks like a
// graphics driver problem rather than a wrong quad.
vertex RingOut ringVertex(uint index [[vertex_id]],
                          constant FieldUniforms &uniforms [[buffer(2)]]) {
    // Four corners from the vertex number alone, drawn as a triangle strip. No vertex buffer
    // needed for a shape that is always the whole screen.
    float2 corner = float2((index & 1) ? 1.0 : 0.0, (index & 2) ? 1.0 : 0.0);
    RingOut out;
    out.screen = corner * uniforms.viewSize;
    out.position = float4(corner.x * 2.0 - 1.0, 1.0 - corner.y * 2.0, 0.0, 1.0);
    return out;
}

fragment half4 ringFragment(RingOut in [[stage_in]],
                            constant RingUniforms &ring [[buffer(0)]]) {
    float distance = length(in.screen - ring.centre);

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

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
    // Which silhouette to draw. The numbers are `ParticleShape.shaderIdentifier`.
    int shape;
    // Nothing, and here on purpose.
    //
    // Without it the struct ends on a four-byte boundary and both languages pad the tail out to
    // eight on their own. They agree today, and neither is required to — and a disagreement about
    // trailing padding does not fail to compile, it silently reads the wrong fields. Filling the gap
    // explicitly means there is nothing left to agree about.
    int reserved;
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
    // Not named `half`: that is a type in this language, and using it as a variable fails to compile
    // with four errors that name neither the word nor the reason.
    float2 halfView = max(u.viewSize * 0.5, float2(1e-6));
    n = n * u.zoom + float2(u.pan.x / halfView.x, -u.pan.y / halfView.y);

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

// How far outside the chosen silhouette a point is, and where that silhouette's edge sits.
//
// **This mirrors `ParticleShape.metric(x:y:)` in `CrucibleCore`, formula for formula.** That file is
// the one to change first: it is ordinary arithmetic, so the silhouettes are tested there — a ring
// must be hollow, a triangle must widen downward, no two shapes may be identical — and none of that
// can be checked from inside a shader.
//
// Three of these were wrong when first written and all three were found by drawing them out as text
// and looking at them: the star came out as a filled square with a star-shaped hole, the hexagon
// overran its box and arrived with the top and bottom sliced flat, and the spark was a plain diamond
// with an invisible cross inside it. The reference implementation ships all three of those faults.
//
// Everything is measured in a square running from minus one to one with **y pointing up**. The
// gradient that comes back says how fast this shape's measurement moves compared with a plain
// radius, so that one piece of edge-softening can serve all ten.
static inline void shapeMetric(float2 p, int shape,
                               thread float &distance, thread float &edge, thread float &gradient) {
    gradient = 1.0;
    edge = 1.0;

    switch (shape) {
    case 1:  // square
        distance = max(abs(p.x), abs(p.y));
        return;

    case 2: {  // ring — a band three tenths wide about a circle of radius seven tenths
        float radius = length(p);
        distance = abs(radius - 0.7) * (1.0 / 0.3);
        gradient = 1.0 / 0.3;
        return;
    }

    case 3:  // diamond — the axes added rather than compared
        distance = abs(p.x) + abs(p.y);
        return;

    case 4: {  // triangle, point upward, base cut off flat
        float halfWidth = 0.85 * (1.0 - p.y) / 1.7;
        distance = max(-p.y - 0.72, abs(p.x) - halfWidth);
        edge = 0.0;
        return;
    }

    case 5: {  // star — five points, folded by reflection rather than by taking an angle
        const float cos36 = 0.8090169943749475;
        const float sin36 = 0.5877852522924731;
        float2 q = float2(abs(p.x), p.y);

        float first = q.x * cos36 - q.y * sin36;
        if (first > 0.0) { q -= 2.0 * first * float2(cos36, -sin36); }
        float second = -q.x * cos36 - q.y * sin36;
        if (second > 0.0) { q += 2.0 * second * float2(cos36, sin36); }
        q.x = abs(q.x);
        q.y -= 1.0;

        float2 e = float2(0.38 * sin36, 0.38 * cos36 - 1.0);
        float along = clamp(dot(q, e) / dot(e, e), 0.0, 1.0);
        float gap = length(q - e * along);
        float side = q.x * e.y - q.y * e.x;
        distance = side > 0.0 ? -gap : gap;
        edge = 0.0;
        return;
    }

    case 6:  // hexagon, points up and down, fitting the box exactly
        distance = max(abs(p.x), abs(p.x) * 0.5 + abs(p.y) * 0.8660254037844386);
        edge = 0.8660254037844386;
        return;

    case 7:  // cross — two long thin boxes, joined
        distance = min(max(3.2 * abs(p.x), abs(p.y)), max(3.2 * abs(p.y), abs(p.x)));
        gradient = 3.2;
        return;

    case 8:  // spark — four points with sides bent inward by adding square roots
        distance = sqrt(abs(p.x)) + sqrt(abs(p.y));
        gradient = 1.4;
        return;

    case 9: {  // heart — a circle whose centre lifts the further out it goes
        float shifted = p.y + 0.28;
        float across = abs(p.x);
        float lift = shifted - 0.5 * sqrt(across);
        distance = across * across + lift * lift;
        edge = 0.62;
        gradient = 1.6;
        return;
    }

    default:  // circle
        distance = length(p);
        return;
    }
}

fragment half4 particleFragment(PointOut in [[stage_in]],
                                float2 coordinate [[point_coord]],
                                constant FieldUniforms &uniforms [[buffer(0)]]) {
    // A point arrives as a square. Turned into a square running from minus one to one with y upward,
    // matching what `ParticleShape` describes — the vertical flip is because the coordinate a point
    // hands over grows downward, and two of the ten shapes have a top and a bottom.
    float2 p = float2(coordinate.x * 2.0 - 1.0, 1.0 - coordinate.y * 2.0);

    float distance, edge, gradient;
    shapeMetric(p, uniforms.shape, distance, edge, gradient);

    // The faded edge, one pixel wide whatever size the body is drawn. The square is always two units
    // across, so one pixel is two divided by the size — which means the fade is worked out from the
    // real drawn size rather than being a fixed fraction of it.
    //
    // The reference implementation uses a fixed fraction, so its edges are invisible on a small body
    // and a blur several pixels wide on a large one. This is also strictly better than what the field
    // did before, which was no softening at all: a plain hard cut, which at two or three pixels across
    // gives every body a visible staircase.
    float softness = min(0.5, 2.0 / max(in.size, 1.0)) * max(gradient, 1e-6);

    float coverage;
    if (softness > 1e-9) {
        coverage = clamp((edge - distance) / softness, 0.0, 1.0);
    } else {
        coverage = distance <= edge ? 1.0 : 0.0;
    }

    // Discarded rather than returned transparent: a fully faded fragment still costs a blend, and at
    // a million bodies most of every point sprite is outside its shape.
    if (coverage <= 0.004) {
        discard_fragment();
    }

    half4 color = in.color;
    color.a *= half(coverage);
    return color;
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



// MARK: - The background
//
// The field has always sat on flat near-black. These are the alternatives, and all of them are worked
// out per pixel rather than drawn from a picture — a starfield with no texture, a nebula with no
// bitmap — so they cost nothing to carry around and stay sharp at any size.
//
// Drawn *behind* the particles, which is worth saying because the reference implementation this was
// merged from does the opposite: its backgrounds are separate web-page elements laid over the top of
// the canvas, relying on a blending mode to look as though they are underneath. That works until
// something needs to be genuinely in front of them.

struct BackgroundUniforms {
    // Which one. 0 none, 1 starfield, 2 gradient, 3 nebula.
    int kind;
    int reserved;
    // Seconds, for the twinkle.
    float time;
    // How bright the whole thing is.
    float strength;
};

// A repeatable pseudo-random number from a pair of whole numbers.
//
// The usual trick: multiply by a couple of awkward constants, take the sine, and keep the fractional
// part. It is not a good random number by any measure that matters to statistics, but it is a fixed
// function of its input — so a star is in the same place every frame without anything having to
// remember where it was.
static inline float hash21(float2 p) {
    float h = dot(p, float2(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fragment half4 backgroundFragment(RingOut in [[stage_in]],
                                  constant FieldUniforms &uniforms [[buffer(2)]],
                                  constant BackgroundUniforms &background [[buffer(0)]]) {
    float2 view = max(uniforms.viewSize, float2(1.0));
    // Nought to one across the screen, and the aspect kept so a round thing stays round.
    float2 uv = in.screen / view;
    float aspect = view.x / max(view.y, 1.0);
    float3 colour = float3(0.0);

    if (background.kind == 1) {
        // Starfield.
        //
        // The screen is cut into a grid of cells and each cell holds at most one star, placed
        // somewhere inside it by the hash. That is what makes the stars spread evenly without ever
        // clumping — and it means finding the star near a pixel is a handful of arithmetic rather
        // than a search through a list.
        //
        // Three passes at different sizes of cell, so there are a few large bright stars among many
        // small faint ones. A single pass gives a field of identical dots, which reads as a texture
        // rather than as a sky.
        const int layers = 3;
        for (int layer = 0; layer < layers; layer++) {
            float density = 26.0 * float(layer + 1);
            float2 grid = float2(uv.x * aspect, uv.y) * density;
            float2 cell = floor(grid);
            float2 within = fract(grid);

            float exists = hash21(cell + float2(float(layer) * 37.0, 0.0));
            // Only some cells hold a star, and fewer in the coarser layers — otherwise the big bright
            // ones outnumber the small ones and the sky looks like a spill.
            float chance = 0.42 - 0.1 * float(layer);
            if (exists > chance) { continue; }

            float2 where = float2(
                hash21(cell + float2(11.3, 5.7 + float(layer))),
                hash21(cell + float2(3.1, 19.7 + float(layer)))
            );
            float distance = length(within - where);

            // A soft point of light. The falloff is steep, so a star is a point with a faint halo
            // rather than a disc.
            float size = (0.045 - 0.012 * float(layer)) * (0.5 + exists);
            float brightness = smoothstep(size, 0.0, distance);

            // Twinkling, at a rate of its own per star, and never all the way out — a star that
            // blinks to nothing reads as a fault rather than as air.
            float rate = 0.6 + hash21(cell + float2(71.0, 13.0)) * 1.8;
            float phase = hash21(cell + float2(29.0, 47.0)) * 6.283185;
            float twinkle = 0.62 + 0.38 * sin(background.time * rate + phase);

            // Faintly coloured: most stars white, a few warm or cold. Sampled from the hash so a
            // given star keeps its colour.
            float tint = hash21(cell + float2(5.0, 91.0));
            float3 starColour = mix(
                float3(0.86, 0.90, 1.0),
                tint > 0.72 ? float3(1.0, 0.86, 0.72) : float3(0.78, 0.88, 1.0),
                tint
            );
            colour += starColour * brightness * twinkle * (0.55 + 0.45 * exists);
        }
    } else if (background.kind == 2) {
        // A gradient: cool at the top, warm at the bottom, clear through the middle so the field
        // itself is what draws the eye.
        float3 top = float3(0.102, 0.153, 0.267);
        float3 bottom = float3(0.102, 0.063, 0.063);
        float towardEdges = abs(uv.y - 0.5) * 2.0;
        float3 mixed = uv.y < 0.5 ? top : bottom;
        colour = mixed * smoothstep(0.1, 1.0, towardEdges);
    } else if (background.kind == 3) {
        // A nebula: two soft clouds of colour, drifting. The reference implementation's version of
        // this is two fixed shapes with no movement at all despite the name; this one turns slowly,
        // which is the difference between a backdrop and a wallpaper.
        float drift = background.time * 0.04;
        float2 first = float2(0.38 + sin(drift) * 0.04, 0.32 + cos(drift * 0.8) * 0.03);
        float2 second = float2(0.72 + cos(drift * 0.7) * 0.05, 0.68 + sin(drift) * 0.04);

        float2 toFirst = (uv - first) * float2(aspect, 1.0);
        float2 toSecond = (uv - second) * float2(aspect, 1.0);
        float cloudA = smoothstep(0.55, 0.0, length(toFirst));
        float cloudB = smoothstep(0.5, 0.0, length(toSecond));
        colour = float3(0.275, 0.431, 0.745) * cloudA * 0.35
               + float3(0.549, 0.235, 0.471) * cloudB * 0.28;
    }

    colour *= max(background.strength, 0.0);
    // Opaque, because this is the bottom layer — everything else is composited over it.
    return half4(half3(colour), 1.0h);
}


// MARK: - Glow
//
// Bright things bleeding into the space around them. A field of particles without it looks like a
// scatter plot; with it, it looks lit.
//
// Three passes, and the arrangement is the point:
//
//   1. **Pick out what is bright**, at a quarter of the width and height. Quarter size because a
//      glow is a blurred thing and blurring something that has already been shrunk is sixteen times
//      less work for a result nobody can tell apart.
//   2. **Blur sideways**, then **blur downward**. Two passes of nine samples each rather than one
//      pass of eighty-one, which is the standard way and gives the same answer.
//   3. **Add it back** over the field.
//
// The reference implementation does it in one pass at full size with twenty samples arranged in
// rings, no centre sample, and no shrinking — so it costs sixteen times as much per unit of blur and
// produces visible rings rather than a smooth falloff, because twenty scattered samples cannot make a
// smooth curve. Its blur width is also tied to its strength slider, so asking for a brighter glow
// makes a wider one, which is why turning it up reads as a haze rather than as brightness.

struct GlowUniforms {
    // How far apart the samples are, in whole pixels of the texture being read.
    float2 step;
    // Anything dimmer than this does not glow at all.
    float threshold;
    // How bright the glow is when added back.
    float strength;
};

// The nine weights of a Gaussian blur, normalised so they add to one.
//
// Written out rather than worked out, and separated into the middle plus four pairs, because that is
// how they are used: the shape is symmetric, so each pair is one weight applied twice.
constant float kGlowWeights[5] = { 0.2270270270, 0.1945945946, 0.1216216216, 0.0540540541, 0.0162162162 };

fragment half4 glowBrightFragment(RingOut in [[stage_in]],
                                  constant FieldUniforms &uniforms [[buffer(2)]],
                                  constant GlowUniforms &glow [[buffer(0)]],
                                  texture2d<float> source [[texture(0)]],
                                  sampler smooth [[sampler(0)]]) {
    float2 uv = in.screen / max(uniforms.viewSize, float2(1.0));
    float4 sampled = source.sample(smooth, uv);

    // How bright it is, weighted the way an eye weighs the three channels — green counts for most,
    // blue for least.
    float brightness = dot(sampled.rgb, float3(0.2126, 0.7152, 0.0722));
    // A soft knee rather than a hard cut. A hard cut makes the glow appear and disappear along a
    // visible contour as something brightens, which looks like a fault in the picture.
    float over = smoothstep(glow.threshold, glow.threshold + 0.25, brightness);
    return half4(half3(sampled.rgb * over), 1.0h);
}

fragment half4 glowBlurFragment(RingOut in [[stage_in]],
                                constant FieldUniforms &uniforms [[buffer(2)]],
                                constant GlowUniforms &glow [[buffer(0)]],
                                texture2d<float> source [[texture(0)]],
                                sampler smooth [[sampler(0)]]) {
    float2 uv = in.screen / max(uniforms.viewSize, float2(1.0));
    float3 total = source.sample(smooth, uv).rgb * kGlowWeights[0];
    for (int tap = 1; tap < 5; tap++) {
        float2 offset = glow.step * float(tap);
        total += source.sample(smooth, uv + offset).rgb * kGlowWeights[tap];
        total += source.sample(smooth, uv - offset).rgb * kGlowWeights[tap];
    }
    return half4(half3(total), 1.0h);
}

// Lays the field over whatever is behind it.
//
// The field's own texture holds each colour already multiplied by its opacity, which is what the
// blending that filled it produces. So laying it over the background is not a mix of two colours — it
// is "keep all of this, and however much of what is underneath is still showing through". The pipeline
// is set up to do exactly that, which is why this function simply hands the sample back.
fragment half4 fieldOverFragment(RingOut in [[stage_in]],
                                 constant FieldUniforms &uniforms [[buffer(2)]],
                                 texture2d<float> field [[texture(0)]],
                                 sampler smooth [[sampler(0)]]) {
    float2 uv = in.screen / max(uniforms.viewSize, float2(1.0));
    return half4(field.sample(smooth, uv));
}

// Adds the glow on top of everything.
fragment half4 glowAddFragment(RingOut in [[stage_in]],
                               constant FieldUniforms &uniforms [[buffer(2)]],
                               constant GlowUniforms &glow [[buffer(0)]],
                               texture2d<float> glowSource [[texture(0)]],
                               sampler smooth [[sampler(0)]]) {
    float2 uv = in.screen / max(uniforms.viewSize, float2(1.0));
    float3 bloom = glowSource.sample(smooth, uv).rgb * max(glow.strength, 0.0);
    // Alpha of one with an adding pipeline, so the glow brightens what is there and never dims it.
    return half4(half3(bloom), 1.0h);
}

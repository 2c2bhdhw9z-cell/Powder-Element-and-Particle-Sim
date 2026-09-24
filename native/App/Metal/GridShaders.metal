//  Drawing the simulation grid.
//
//  There is deliberately almost nothing here. Every decision about what colour a cell
//  should be — grain speckling, mist blending, heat tinting, the overlay modes — lives in
//  the engine, where it compiles on any machine and is compared cell by cell against the
//  reference implementation. By the time the pixels reach the GPU they are finished.
//
//  So this is a stretch-a-picture-over-the-screen shader and nothing more. That is the
//  point: shader code is the hardest code in the project to test, so it should be the code
//  with the fewest decisions in it.

#include <metal_stdlib>
using namespace metal;

struct GridVertex {
    float4 position [[position]];
    float2 textureCoordinate;
};

// A full-screen quad generated from the vertex index, so no vertex buffer is needed.
//
// Four vertices drawn as a triangle strip. The texture's first row is the top of the world,
// while in the coordinates the GPU draws in the top of the screen is +1 — hence the vertical
// flip between the two tables below. Getting that wrong renders the world upside down, which
// is the sort of thing that looks like a physics bug at first glance.
vertex GridVertex gridVertex(uint vertexIndex [[vertex_id]]) {
    const float2 corners[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    const float2 coordinates[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
    };

    GridVertex out;
    out.position = float4(corners[vertexIndex], 0.0, 1.0);
    out.textureCoordinate = coordinates[vertexIndex];
    return out;
}

fragment float4 gridFragment(GridVertex in [[stage_in]],
                             texture2d<float> grid [[texture(0)]]) {
    // Nearest-neighbour, never smoothed. One cell is one pixel of the texture, and the whole
    // look of a falling-sand world depends on individual grains staying crisp when the
    // texture is stretched over a much larger screen. Linear filtering turns it to mush.
    constexpr sampler cellSampler(filter::nearest, address::clamp_to_edge);
    return grid.sample(cellSampler, in.textureCoordinate);
}

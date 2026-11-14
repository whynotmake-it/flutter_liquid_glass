// The geometry of glass that is one shape, worked out where the fragment
// is: the shape's distance and normal from the functions the atlas's strips
// evaluate (gpu/sdf.glsl), as the texel they write (gpu/matte_encoding.glsl).
// An atlas is a cache of this function for glass of several shapes; glass of
// one shape needs none, so it is never tiled, drawn into a page or
// submitted, whether it rests or moves.
//
// Included by liquid_glass_final_render_core.glsl after its float uniforms.
// impellerc gives every uniform declaration its own Metal buffer slot and
// Metal has 31; these three fit because the core packs its optional effects
// into uEffects.
//
// The shape is highp, as the strips shade it; the core's mediump returns
// after it. A whole highp shader holds 64 work registers on a Mali-G78,
// half its occupancy.
precision highp float;

#define MAX_SHAPES 1
// The shape's rows are plain uniforms here, not the strips' block.
#define GEOMETRY_UNIFORMS_GLSL
// One shape blends with none, so its own short side sizes its lens, and
// its normals are its edge's: glass whose normals lean to its center is
// drawn from an atlas (geometryKindOf), which leaves this shader its work
// registers.
#define SHAPE_ALONE

// The shape's primitive, inverse basis and placement, in the geometry
// buffer's pixels, as gpu/sdf.glsl reads them.
uniform vec4 uShapeData[3];
// Its three rounded superellipse rows, then a pair's bottom-half rows.
uniform vec4 uRseData[6];
// A rounded box the shape holds, in its own axes: half its width and height
// and its corner radius; w is the shape's distance scale, 0 where no box is
// known to lie inside it (Tiling.innerBoxOf).
uniform vec4 uShapeInner;
// gpu/sdf.glsl's scene functions read shape bounds; one shape never calls
// them.
vec4 uShapeBounds[1];

#include "gpu/sdf.glsl"
#include "gpu/matte_encoding.glsl"

// A lower bound of how deep p lies inside the shape, in buffer pixels: its
// depth in the rounded box the shape holds. Negative or 0 where it says
// nothing.
float shapeDepthBound(vec2 p) {
    vec2 delta = p - uShapeData[2].xy;
    vec2 local = abs(vec2(
        dot(uShapeData[1].xy, delta),
        dot(uShapeData[1].zw, delta)
    ));
    vec2 corner = local - (uShapeInner.xy - uShapeInner.z);
    float outside = length(max(corner, 0.0)) +
        min(max(corner.x, corner.y), 0.0) - uShapeInner.z;
    return -outside * uShapeInner.w;
}

// The geometry texel at buffer pixel position p. Deeper inside than
// readDepth the final pass only checks that the distance is past it, so
// there the texel is some depth past it with no normal, as a deep tile of
// an atlas is. The glass is drawn over the shape's own box, so few pixels
// lie far outside it; a test for them would double the registers.
vec4 shapeTexel(vec2 p, float readDepth) {
    float depth = shapeDepthBound(p);
    if (depth > readDepth) {
        return vec4(depth, 0.0, 0.0, 0.0);
    }
    SceneSample scene = getShapeSampleFromArray(0, p, false);
    return encodeMatte(scene.distance, scene.opticalNormal, scene.halfMinor);
}

precision mediump float;

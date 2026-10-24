// Copyright 2025, Tim Lehmann for whynotmake.it
//
// Geometry pass, run with Flutter GPU. It renders a smooth field on a coarse
// lattice, one texel per `scale` (2 or 4) matte pixels, which the final pass
// interpolates through the sampler's hardware bilinear filtering and turns back
// into crisp edges, normals and displacement (see liquid_glass_final_render_core.glsl).
//
// The target is RGBA16F; every channel is a smooth function of position
// (apart from the creases deep inside a shape, which nothing reads), so it
// interpolates well:
//   R: signed inward edge distance in matte pixels, positive inside. Linear
//      across a straight edge, so the interpolated silhouette is exact there.
//   G, B: the optical surface normal (unit, with the geometry pass's rounded
//      corners) scaled by sqrt(clamp(|gradient|, 0, 1)), the factor that
//      shortens refraction where the distance field does (smooth-union
//      bridges, stretched shapes). The final pass recovers the direction by
//      interpolating and normalizing, and the factor by interpolating the
//      lengths.
//   A: the half short side of the shape (blended like the distance in a
//      group), which sets the bevel profile.
// Everything else the full matte stores (refraction displacement, antialiased
// coverage, the exterior contour support) is a function of these, so the final
// pass evaluates it per pixel instead of reading it quantized.

precision highp float;

#define MAX_SHAPES 16

layout(std140) uniform GeometryUniforms {
    vec2 uOffset;
    vec2 uTextureSize;
    vec4 uOpticalProps;
    vec4 uContourProps;
    vec4 uShapeData[MAX_SHAPES * 3];
    vec4 uRseData[MAX_SHAPES * 3];
    vec4 uShapeTints[MAX_SHAPES];
    vec4 uShapeResponses[MAX_SHAPES];
    vec4 uShapeBounds[MAX_SHAPES];
    // x: matte pixels per lattice texel. Appended after the members the other
    // geometry shaders declare, so their layout is a prefix of this one.
    vec4 uLowRes;
} geometryUniforms;

#define uOffset geometryUniforms.uOffset
#define uOpticalProps geometryUniforms.uOpticalProps
#define uContourProps geometryUniforms.uContourProps
#define uNumShapes (uOpticalProps.w)
#define uShapeData geometryUniforms.uShapeData
#define uRseData geometryUniforms.uRseData
#define uShapeBounds geometryUniforms.uShapeBounds

#include "sdf.glsl"

out vec4 fragColor;

// Texels no shape can reach hold this inward distance: far outside, and still
// a finite fp16. The renderer clears the texture to the same value so it can
// shade only the occupied part. Keep in sync with kLowResFarInward there.
const float kFarInward = -4096.0;
// Inward distances saturate here, well inside fp16 range, so a hidden shape's
// 1e9 distance cannot become an infinity that poisons interpolation.
const float kInwardLimit = 16000.0;
// Matte pixels from a pixel's corner to its center.
const float kLatticePhase = 0.5;

void main() {
    float scale = geometryUniforms.uLowRes.x;
    // Lattice texel (i, j) sits on the center of matte pixel (i, j) * scale,
    // so the lattice texels are evaluated where the full matte would be, and
    // a shape centered on a pixel corner is never sampled at its exact axis
    // (the superellipse solver is degenerate there). One more texel than
    // `size / scale` covers the far edge. Keep kLatticePhase in sync with the
    // final shader.
    vec2 position = (gl_FragCoord.xy - 0.5) * scale + uOffset + kLatticePhase;

    // Beyond the contour and the interpolation footprint (two lattice cells)
    // nothing is visible, and the distance is only ever compared against
    // thresholds nearer than that. The box distance bounds the shape distance
    // from below.
    vec2 outsideBounds = sceneBoundsOutsideSquared(position, int(uNumShapes));
    float reach = uContourProps.x + 2.0 * scale + 2.0 + outsideBounds.y;
    if (outsideBounds.x > reach * reach) {
        fragColor = vec4(kFarInward, 0.0, 0.0, 0.0);
        return;
    }

    SceneSample scene = sceneSample(position, int(uNumShapes));
    float gradientLength = length(scene.opticalNormal);
    vec2 normal = gradientLength > 0.0001
        ? scene.opticalNormal / gradientLength
        : vec2(0.0);
    float refractionScale = sqrt(clamp(gradientLength, 0.0, 1.0));
    fragColor = vec4(
        clamp(-scene.distance, -kInwardLimit, kInwardLimit),
        normal * refractionScale,
        scene.halfMinor
    );
}

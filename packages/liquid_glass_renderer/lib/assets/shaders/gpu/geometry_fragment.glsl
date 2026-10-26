// Copyright 2025, Tim Lehmann for whynotmake.it
//
// Geometry pass, run with Flutter GPU. It draws the low-res matte: one texel
// for every `scale` x `scale` block of matte pixels (scale is 2 or 4). The
// final pass reads it with linear filtering, which blends the four nearest
// texels, and turns the result back into sharp edges, normals and refraction
// (see liquid_glass_final_render_core.glsl).
//
// The texture is RGBA16F. Each channel changes smoothly across the shape, so
// blending neighboring texels gives the right value in between:
//   R: distance to the edge in matte pixels, positive inside. It grows in a
//      straight line across a straight edge, so the blended edge lands exactly
//      where it should.
//   G, B: the direction the surface faces (a unit vector), made shorter where
//      refraction should be weaker: where blended shapes join and where
//      shapes are stretched. The final pass gets the direction back by
//      normalizing and the strength from the length.
//   A: half of the shape's shorter side (blended like the distance in a
//      group). It sets how wide the bevel is.
// Everything else the final pass needs (refraction offset, antialiased edge,
// outer border) is computed from these four values for each pixel.

precision highp float;

#define MAX_SHAPES 16

layout(std140) uniform GeometryUniforms {
    vec2 uOffset;
    vec2 uTextureSize;
    vec4 uOpticalProps;
    vec4 uContourProps;
    vec4 uShapeData[MAX_SHAPES * 3];
    // Each shape's three rows, then from MAX_SHAPES * 3 each pair's
    // bottom-half rows (sdf.glsl).
    vec4 uRseData[MAX_SHAPES * 6];
    vec4 uShapeTints[MAX_SHAPES];
    vec4 uShapeResponses[MAX_SHAPES];
    vec4 uShapeBounds[MAX_SHAPES];
    // x: how many matte pixels one low-res matte texel covers in each
    // direction. It comes last, so the other geometry shaders, which leave it
    // out, share the same layout for everything before it.
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

// The distance stored in texels far away from every shape. It is far outside
// and still fits in a 16-bit float. The renderer clears the texture to the
// same value, so the pass only has to draw the part near the shapes. Keep in
// sync with kLowResFarInward in the renderer.
const float kFarInward = -4096.0;
// Distances are capped here, well within 16-bit float range. A hidden shape
// reports a distance of 1e9, which would otherwise become infinity and break
// the blending between texels.
const float kInwardLimit = 16000.0;
// The distance from a pixel's corner to its center, in matte pixels.
const float kPixelCenter = 0.5;

void main() {
    float scale = geometryUniforms.uLowRes.x;
    // Texel (i, j) is computed at the center of matte pixel (i * scale,
    // j * scale), the same point the full-resolution matte used. Using pixel
    // centers also keeps it off the exact center line of a shape that is
    // centered on a pixel corner, where the superellipse solver breaks down.
    // The texture has one extra texel per row and column to cover the far
    // edge. Keep kPixelCenter in sync with the final shader.
    vec2 position = (gl_FragCoord.xy - 0.5) * scale + uOffset + kPixelCenter;

    // Texels farther outside than the border, the blend radius and two more
    // texels can't affect any visible pixel, so they skip the shape math. The
    // distance to the shapes' bounding boxes is never larger than the distance
    // to the shapes themselves, so it is safe to test against.
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

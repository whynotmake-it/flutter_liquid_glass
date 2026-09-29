// Geometry matte generation implemented directly with Flutter GPU.
// Geometry encoding revision 5: the shared uniform layout carries the compact
// appearance lookup table used by the low-resolution material pass.
// Refraction model 2: quarter-circle bevel displacement (height + amount).
// continuous superellipse SDF. Keep this marker in the top-level asset because Flutter's
// shader depfile does not reliably invalidate changes made only in includes.
// Changes:
// - Removed #include <flutter/runtime_effect.glsl>
// - Replaced FlutterFragCoord().xy with gl_FragCoord.xy
// - Uniforms declared in a named uniform block instead of layout(location=N)
// - Removed dead screenUV code (Y-flip was unused)

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
} geometryUniforms;

#define uOffset geometryUniforms.uOffset
#define uTextureSize geometryUniforms.uTextureSize
#define uOpticalProps geometryUniforms.uOpticalProps
#define uContourProps geometryUniforms.uContourProps
#define uNumShapes (uOpticalProps.w)
#define uShapeData geometryUniforms.uShapeData
#define uRseData geometryUniforms.uRseData

#include "displacement_encoding.glsl"

// Included after uShapeData so the SDF helpers can read the uniform directly.
#include "sdf.glsl"

float uRefractionHeight = uOpticalProps.x;
float uEdgeDistanceRange = uOpticalProps.z;
float uRefractionAmount = uTextureSize.y;
float uContourExtent = uContourProps.x;
out vec4 fragColor;

void main() {
    // Flutter 3.47's Impeller backends expose the same render-target
    // orientation, including Flutter GPU passes on GLES.
    vec2 fragCoord = gl_FragCoord.xy + uOffset;

    // Most of a shared layer's matte can be empty when spatially separate
    // groups reuse one backdrop. Reject those pixels before running Flutter's
    // iterative superellipse/ellipse solvers for every shape.
    if (uNumShapes > 1.0) {
        vec2 outsideBounds = sceneBoundsOutsideSquared(
            fragCoord,
            int(uNumShapes)
        );
        float emptyThreshold =
            uContourExtent + 2.0 + outsideBounds.y;
        if (outsideBounds.x > emptyThreshold * emptyThreshold) {
            fragColor = vec4(0.0);
            return;
        }
    }
    SceneSample scene = sceneSample(fragCoord, int(uNumShapes));
    float sd = scene.distance;

    // Match Flutter 3.47's centered signed-distance antialiasing: the
    // coverage transition is half a physical pixel on either side of the
    // mathematical boundary, rather than a fixed two-pixel fade entirely
    // inside the shape. This keeps the contour position independent of scale.
    float dx = dFdx(sd);
    float dy = dFdy(sd);
    float pixelSize = length(vec2(dx, dy));
    float fade = clamp(uOpticalProps.y, 0.0, 1.0) * max(pixelSize, 1e-4);
    float materialAlpha = 1.0 - smoothstep(-fade, fade, sd);
    // Keep geometry alive only as far as the final pass can draw an attached
    // contour. The final shader reconstructs material AA from the signed SDF,
    // so expanding this support does not expand the glass body itself.
    float contourSupport = 1.0 - smoothstep(
        max(uContourExtent - fade, 0.0),
        uContourExtent,
        sd
    );
    float effectSupport = max(materialAlpha, contourSupport);
    if (effectSupport < 0.01) {
        fragColor = vec4(0.0);
        return;
    }

    vec2 surfaceGradient = vec2(dx, dy);
    float surfaceGradientLength = length(surfaceGradient);
    vec2 surfaceNormal = surfaceGradientLength > 0.0001
        ? surfaceGradient / surfaceGradientLength
        : vec2(0.0);

    // A flat face with a quarter-circle bevel: only the bevel refracts, and
    // its displacement joins the undisplaced face with zero slope. Shapes
    // narrower than two bevels scale the whole lens so the displacement
    // reaches zero at the medial axis instead of flipping direction there.
    // The exterior half of the AA ramp keeps the silhouette's displacement.
    float lensScale = min(
        1.0,
        scene.halfMinor / max(uRefractionHeight, 0.001)
    );
    float bevel = uRefractionHeight * lensScale;
    float bevelX = 1.0 - clamp(max(-sd, 0.0) / max(bevel, 0.001), 0.0, 1.0);
    float displacementMagnitude = bevel > 0.001
        ? -uRefractionAmount * lensScale *
            (1.0 - sqrt(1.0 - bevelX * bevelX))
        : 0.0;

    fragColor = encodeDisplacementData(
        surfaceNormal,
        displacementMagnitude,
        max(uRefractionAmount, 0.001),
        -sd,
        4.0 * uEdgeDistanceRange,
        uContourExtent
    );
}

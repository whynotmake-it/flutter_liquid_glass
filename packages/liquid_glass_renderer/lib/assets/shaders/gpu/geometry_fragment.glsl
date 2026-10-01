// Copyright 2025, Tim Lehmann for whynotmake.it
//
// Geometry pass, run with Flutter GPU: renders the signed distance field of
// every shape in a layer into the layer's matte (12-bit surface normal angle,
// signed edge distance and 12-bit displacement, packed by
// displacement_encoding.glsl). Normals are analytic; corner normals come from
// a 1.5x corner radius, and refraction uses a quarter-circle bevel that can
// fit the shape.

// The matte packs 12-bit integer codes; fp16 cannot represent them exactly.
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
} geometryUniforms;

#define uOffset geometryUniforms.uOffset
#define uTextureSize geometryUniforms.uTextureSize
#define uOpticalProps geometryUniforms.uOpticalProps
#define uContourProps geometryUniforms.uContourProps
#define uNumShapes (uOpticalProps.w)
#define uShapeData geometryUniforms.uShapeData
#define uRseData geometryUniforms.uRseData
#define uShapeBounds geometryUniforms.uShapeBounds

#include "displacement_encoding.glsl"

// Included after uShapeData so the SDF helpers can read the uniform directly.
#include "sdf.glsl"

float uRefractionHeight = uOpticalProps.x;
float uEdgeDistanceRange = uOpticalProps.z;
float uRefractionAmount = uTextureSize.y;
float uRefractionFitsShape = uTextureSize.x;
float uContourExtent = uContourProps.x;
out vec4 fragColor;

void main() {
    // Flutter 3.47's Impeller backends expose the same render-target
    // orientation, including Flutter GPU passes on GLES.
    vec2 fragCoord = gl_FragCoord.xy + uOffset;

    // Most of a shared layer's matte can be empty when spatially separate
    // groups reuse one backdrop, and a single shape's texture is padded to
    // its size bucket. Reject those pixels with the matte-space boxes before
    // running Flutter's iterative superellipse/ellipse solvers.
    vec2 outsideBounds = sceneBoundsOutsideSquared(
        fragCoord,
        int(uNumShapes)
    );
    float emptyThreshold = uContourExtent + 2.0 + outsideBounds.y;
    if (outsideBounds.x > emptyThreshold * emptyThreshold) {
        fragColor = vec4(0.0);
        return;
    }
    SceneSample scene = sceneSample(fragCoord, int(uNumShapes));
    float sd = scene.distance;

    // Match Flutter 3.47's centered signed-distance antialiasing: the
    // coverage transition is half a physical pixel on either side of the
    // mathematical boundary, rather than a fixed two-pixel fade entirely
    // inside the shape. This keeps the contour position independent of scale.
    // Analytic gradient rather than dFdx/dFdy of the distance, which many
    // GPUs share across a 2x2 quad (see getShapeGradients).
    float dx = scene.opticalNormal.x;
    float dy = scene.opticalNormal.y;
    float pixelSize = length(scene.opticalNormal);
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
    // its displacement joins the undisplaced face with zero slope. The
    // exterior half of the AA ramp keeps the silhouette's displacement.
    float bevel;
    float amount;
    if (uRefractionFitsShape > 0.5) {
        // iOS 27 regular glass: the bevel spans at most half of the half
        // short side and the rim samples no deeper than the center line.
        bevel = min(uRefractionHeight, 0.5 * scene.halfMinor);
        amount = min(uRefractionAmount, scene.halfMinor);
    } else {
        // Clear glass keeps its lens until the bevel would pass the center
        // line, then scales the whole lens so displacement never flips there.
        float lensScale = min(
            1.0,
            scene.halfMinor / max(uRefractionHeight, 0.001)
        );
        bevel = uRefractionHeight * lensScale;
        amount = uRefractionAmount * lensScale;
    }
    float bevelX = 1.0 - clamp(max(-sd, 0.0) / max(bevel, 0.001), 0.0, 1.0);
    float displacementMagnitude = bevel > 0.001
        ? -amount * (1.0 - sqrt(1.0 - bevelX * bevelX))
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

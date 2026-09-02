// Geometry matte generation implemented directly with Flutter GPU.
// Geometry encoding revision 3: widened edge-distance field, profile reach,
// and a shared displacement codec scale.
// continuous superellipse SDF. Keep this marker in the top-level asset because Flutter's
// shader depfile does not reliably invalidate changes made only in includes.
// Changes:
// - Removed #include <flutter/runtime_effect.glsl>
// - Replaced FlutterFragCoord().xy with gl_FragCoord.xy
// - Uniforms declared in a named uniform block instead of layout(location=N)
// - Removed dead screenUV code (Y-flip was unused)

#define MAX_SHAPES 16

#ifndef MATERIAL_OUTPUT
#define MATERIAL_OUTPUT 0
#endif

layout(std140) uniform GeometryUniforms {
    vec2 uOffset;
    vec2 uTextureSize;
    vec4 uOpticalProps;
    vec4 uContourProps;
    vec4 uShapeData[MAX_SHAPES * 3];
    vec4 uRseData[MAX_SHAPES * 3];
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

#if MATERIAL_OUTPUT
#include "material_sdf.glsl"
#endif

float uThickness = uOpticalProps.z;
float uRefractiveIndex = uOpticalProps.x;
float uRefractionSpread = uTextureSize.x;
float uContourExtent = uContourProps.x;
#if MATERIAL_OUTPUT
layout(location = 0) out vec4 fragColor;
layout(location = 1) out vec4 materialColor;
#else
out vec4 fragColor;
#endif

void main() {
    // Flutter 3.47's Impeller backends expose the same render-target
    // orientation, including Flutter GPU passes on GLES.
    vec2 fragCoord = gl_FragCoord.xy + uOffset;

    float spread = clamp(uRefractionSpread, 0.0, 1.0);
    bool hasFaceSpread = spread > 0.0;
    #if MATERIAL_OUTPUT
    MaterialSceneSample scene = materialSceneSample(
        fragCoord,
        int(uNumShapes)
    );
    materialColor = encodeMaterialContributors(scene);
    #else
    SceneSample scene = sceneSample(fragCoord, int(uNumShapes));
    #endif
    float sd = scene.distance;

    // Match Flutter 3.47's centered signed-distance antialiasing: the
    // coverage transition is half a physical pixel on either side of the
    // mathematical boundary, rather than a fixed two-pixel fade entirely
    // inside the shape. This keeps the contour position independent of scale.
    float pixelSize = length(vec2(dFdx(sd), dFdy(sd)));
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
        #if MATERIAL_OUTPUT
        materialColor = vec4(0.0);
        #endif
        return;
    }

    // Keep the centered coverage on both sides of the mathematical edge, but
    // clamp optical depth to the filled side. The exterior half of the AA
    // ramp carries zero displacement and only supplies the correct silhouette
    // coverage; rejecting sd >= 0 here would silently turn centered AA back
    // into an inside-only fade.
    if (uThickness <= 0.0) {
        fragColor = vec4(0.0);
        #if MATERIAL_OUTPUT
        materialColor = vec4(0.0);
        #endif
        return;
    }

    float surfaceSd = min(sd, 0.0);
    float dx = dFdx(sd);
    float dy = dFdy(sd);

    // Spread extends the same circular edge profile toward the shape's
    // center. Its reach is shape-relative, so thickness cannot accidentally
    // become a proxy for coverage on large lenses.
    float reach = hasFaceSpread
        ? mix(uThickness, max(uThickness, scene.halfMinor), spread)
        : uThickness;
    float inwardDistance = max(-surfaceSd, 0.0);
    float profileX = min(inwardDistance, reach);
    float normalizedProfile = profileX / max(reach, 0.001);
    // Circular-cap profile: the height and its normal are derived from the
    // same surface, so the transmitted displacement remains a coherent lens
    // rather than an independently-shaped color warp.
    float profileHeight = sqrt(
        max(0.0, normalizedProfile * (2.0 - normalizedProfile))
    );
    float height = uThickness * profileHeight;
    // Keep the homogeneous normal form. It is the stable form of the
    // derivative-derived cap normal: dividing by profileHeight would create a
    // false finite slope at the exact rim and can reduce the requested peak
    // displacement for large reaches.
    float slopeScale = uThickness / max(reach, 0.001);
    vec3 normal = normalize(vec3(
        dx * slopeScale * (1.0 - normalizedProfile),
        dy * slopeScale * (1.0 - normalizedProfile),
        profileHeight
    ));

    float baseHeight = uThickness * 8.0;
    vec3 incident = vec3(0.0, 0.0, -1.0);

    float invRefractiveIndex = 1.0 / uRefractiveIndex;
    vec3 baseRefract = refract(incident, normal, invRefractiveIndex);
    float baseRefractLength = (height + baseHeight) / max(0.001, abs(baseRefract.z));
    vec2 refractedDisplacement = baseRefract.xy * baseRefractLength;

    // Spread is expressed entirely by the generalized SDF/profile field
    // above. Do not add a center-relative affine scale here: that merely
    // enlarges the backdrop and reads as a zoomed pill rather than refraction.
    vec2 displacement = refractedDisplacement;
    vec2 surfaceGradient = vec2(dx, dy);
    float surfaceGradientLength = length(surfaceGradient);
    vec2 surfaceNormal = surfaceGradientLength > 0.0001
        ? surfaceGradient / surfaceGradientLength
        : vec2(0.0);
    float displacementMagnitude = dot(displacement, surfaceNormal);
    float signedEdgeDistance = -sd;
    fragColor = encodeDisplacementData(
        surfaceNormal,
        displacementMagnitude,
        max(uTextureSize.y, 0.001),
        signedEdgeDistance,
        uThickness,
        uContourExtent
    );
}

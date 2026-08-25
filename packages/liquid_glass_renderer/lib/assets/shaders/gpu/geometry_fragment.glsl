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

layout(std140) uniform GeometryUniforms {
    vec2 uOffset;
    vec2 uTextureSize;
    vec4 uOpticalProps;
    vec4 uShapeData[MAX_SHAPES * 3];
    vec4 uRseData[MAX_SHAPES * 3];
} geometryUniforms;

#define uOffset geometryUniforms.uOffset
#define uTextureSize geometryUniforms.uTextureSize
#define uOpticalProps geometryUniforms.uOpticalProps
#define uNumShapes (uOpticalProps.w)
#define uShapeData geometryUniforms.uShapeData
#define uRseData geometryUniforms.uRseData

#include "displacement_encoding.glsl"

// Included after uShapeData so the SDF helpers can read the uniform directly.
#include "sdf.glsl"

float uThickness = uOpticalProps.z;
float uRefractiveIndex = uOpticalProps.x;
float uRefractionSpread = uTextureSize.x;
out vec4 fragColor;

void main() {
    // Flutter 3.47's Impeller backends expose the same render-target
    // orientation, including Flutter GPU passes on GLES.
    vec2 fragCoord = gl_FragCoord.xy + uOffset;

    float spread = clamp(uRefractionSpread, 0.0, 1.0);
    // The normal material has no face-spread lens. Keep its established SDF
    // path free of the loupe metadata traversal; the extra shape metadata is
    // only needed by controls that explicitly opt into refraction spread.
    bool hasFaceSpread = spread > 0.001;
    SceneSample scene;
    float sd;
    if (hasFaceSpread) {
        scene = sceneSample(fragCoord, int(uNumShapes));
        sd = scene.distance;
    } else {
        sd = sceneSDF(fragCoord, int(uNumShapes));
    }

    // Match Flutter 3.47's centered signed-distance antialiasing: the
    // coverage transition is half a physical pixel on either side of the
    // mathematical boundary, rather than a fixed two-pixel fade entirely
    // inside the shape. This keeps the contour position independent of scale.
    float pixelSize = length(vec2(dFdx(sd), dFdy(sd)));
    float fade = clamp(uOpticalProps.y, 0.0, 1.0) * max(pixelSize, 1e-4);
    float foregroundAlpha = 1.0 - smoothstep(-fade, fade, sd);
    if (foregroundAlpha < 0.01) {
        fragColor = vec4(0.0);
        return;
    }

    // Keep the centered coverage on both sides of the mathematical edge, but
    // clamp optical depth to the filled side. The exterior half of the AA
    // ramp carries zero displacement and only supplies the correct silhouette
    // coverage; rejecting sd >= 0 here would silently turn centered AA back
    // into an inside-only fade.
    if (uThickness <= 0.0) {
        fragColor = vec4(0.0);
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
    float profileHeight = sqrt(max(0.0, normalizedProfile * (2.0 - normalizedProfile)));
    float height = uThickness * profileHeight;
    float n_cos = 1.0 - clamp(inwardDistance / max(reach, 0.001), 0.0, 1.0);
    float n_sin = sqrt(max(0.0, 1.0 - n_cos * n_cos));
    float slopeScale = uThickness / max(reach, 0.001);
    vec3 normal = normalize(vec3(dx * n_cos * slopeScale, dy * n_cos * slopeScale, n_sin));

    float baseHeight = uThickness * 8.0;
    vec3 incident = vec3(0.0, 0.0, -1.0);

    float invRefractiveIndex = 1.0 / uRefractiveIndex;
    vec3 baseRefract = refract(incident, normal, invRefractiveIndex);
    float baseRefractLength = (height + baseHeight) / max(0.001, abs(baseRefract.z));
    vec2 refractedDisplacement = baseRefract.xy * baseRefractLength;

    // The loupe has a low-power affine lens through its body in addition to
    // the circular edge refraction. Blend it only with spread; spread=0 keeps
    // the established toolbar path unchanged. The field is center-relative,
    // so it generalizes across capsules without another pass or texture.
    vec2 displacement = refractedDisplacement;
    if (hasFaceSpread) {
        float edgePeak = 8.0 * uThickness * sqrt(
            max(uRefractiveIndex * uRefractiveIndex - 1.0, 0.0)
        );
        float lensGain = clamp(
            edgePeak / max(scene.halfMajor, 0.001),
            0.0,
            0.9
        );
        vec2 affineLens = -(fragCoord - scene.center) * lensGain;
        displacement = mix(refractedDisplacement, affineLens, spread);
    }

    float maxDisplacement = uThickness * 10.0;
    float edgeDistance = max(-sd, 0.0);

    fragColor = encodeDisplacementData(
        displacement,
        max(uTextureSize.y, maxDisplacement),
        edgeDistance,
        uThickness,
        foregroundAlpha
    );
}

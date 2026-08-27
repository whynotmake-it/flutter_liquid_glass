// Ported from liquid_glass_geometry_blended.frag for flutter_gpu.
// Changes:
// - Removed #include <flutter/runtime_effect.glsl>
// - Replaced FlutterFragCoord().xy with gl_FragCoord.xy
// - Uniforms declared in a named uniform block instead of layout(location=N)
// - Removed dead screenUV code (Y-flip was unused)

#define MAX_SHAPES 16

layout(std140) uniform GeometryUniforms {
    vec2 uSize;
    vec4 uOpticalProps;
    float uNumShapes;
    float uShapeData[MAX_SHAPES * 6];
};

#include "displacement_encoding.glsl"

// Included after uShapeData so the SDF helpers can read the uniform directly.
#include "sdf.glsl"

float uThickness = uOpticalProps.z;
float uRefractiveIndex = uOpticalProps.x;
float uBlend = uOpticalProps.w;

out vec4 fragColor;

void main() {
    vec2 fragCoord = gl_FragCoord.xy;

    float sd = sceneSDF(fragCoord, int(uNumShapes), uBlend);

    float foregroundAlpha = 1.0 - smoothstep(-2.0, 0.0, sd);
    if (foregroundAlpha < 0.01) {
        fragColor = vec4(0.0);
        return;
    }

    float dx = 0.0;
    float dy = 0.0;

    float n_cos = max(uThickness + sd, 0.0) / uThickness;
    float n_sin = sqrt(max(0.0, 1.0 - n_cos * n_cos));

    vec3 normal = normalize(vec3(dx * n_cos, dy * n_cos, n_sin));

    if (sd >= 0.0 || uThickness <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }

    float x = uThickness + sd;
    float sqrtTerm = sqrt(max(0.0, uThickness * uThickness - x * x));
    float height = mix(sqrtTerm, uThickness, float(sd < -uThickness));

    float baseHeight = uThickness * 8.0;
    vec3 incident = vec3(0.0, 0.0, -1.0);

    float invRefractiveIndex = 1.0 / uRefractiveIndex;
    vec3 baseRefract = refract(incident, normal, invRefractiveIndex);
    float baseRefractLength = (height + baseHeight) / max(0.001, abs(baseRefract.z));
    vec2 displacement = baseRefract.xy * baseRefractLength;

    float maxDisplacement = uThickness * 10.0;
    float edgeDistance = -sd;

    fragColor = encodeDisplacementData(
        displacement,
        maxDisplacement,
        edgeDistance,
        uThickness,
        foregroundAlpha
    );
}

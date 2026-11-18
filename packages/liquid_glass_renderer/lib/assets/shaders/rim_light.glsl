#ifndef RIM_LIGHT_GLSL
#define RIM_LIGHT_GLSL

#include "shader_constants.glsl"

float lightAxisTangency(vec2 normal) {
    return abs(dot(normal, vec2(-kLightDirection.y, kLightDirection.x)));
}

float lightFacing(vec2 normal) {
    return dot(normal, -kLightDirection);
}

float contourDirection(vec2 normal, float directionality) {
    return mix(
        1.0,
        lightAxisTangency(normal),
        clamp(directionality, 0.0, 1.0)
    );
}

float glintProfile(float inward, float width) {
    float depth = inward / width;
    return clamp(1.0 - depth, 0.0, 1.0) +
        kGlintBleed * clamp(1.0 - depth / kGlintBleedReach, 0.0, 1.0);
}

float rimGlint(float intensity, vec2 normal, float profile) {
    float lobe = pow(
        max(1.0 - lightAxisTangency(normal), 0.0),
        exp2(2.0 - 4.0 * kGlintWrap)
    );
    float returnWeight = lightFacing(normal) >= 0.0
        ? 1.0
        : kGlintOppositeStrength;
    return clamp(
        max(intensity, 0.0) * kGlintPeak * lobe * returnWeight * profile,
        0.0,
        1.0
    );
}

float seamlessFacing(float facing) {
    return smoothstep(0.0, 1.0, facing * 0.5 + 0.5);
}

float bevelShadow(
    float inward,
    vec2 normal,
    float depth,
    float offset,
    float strength
) {
    float facing = lightFacing(normal);
    float shift = max(offset, 0.0) * facing;
    float penumbra = 2.0 * shift;
    float leadingEdge = penumbra > 0.001
        ? smoothstep(0.0, penumbra, inward)
        : 1.0;
    float falloff = 1.0 - smoothstep(0.0, max(depth, 0.001), inward - shift);
    float direction = mix(
        1.0,
        seamlessFacing(facing),
        kBevelShadowDirectionality
    );
    return clamp(leadingEdge * falloff * direction * strength, 0.0, 1.0);
}

#endif

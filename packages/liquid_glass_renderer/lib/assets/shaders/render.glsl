// Copyright 2025, Tim Lehmann for whynotmake.it
//
// Shared color utilities for the final liquid-glass render pass. Optics and
// lighting live in the geometry and final shaders; keep this include limited
// to code the final pass uses.

#include "shader_constants.glsl"

vec3 applySaturation(vec3 color, float saturation) {
    float luminance = dot(color, LUMA_WEIGHTS);
    float chroma = max(max(color.r, color.g), color.b) -
        min(min(color.r, color.g), color.b);
    // A linear ramp preserves the fitted vivid-material response while
    // avoiding the extra polynomial work of smoothstep in this hot pass.
    float chromaWeight = clamp((chroma - 0.15) / 0.65, 0.0, 1.0);
    float effectiveSaturation = saturation + 0.4 * chromaWeight;
    vec3 saturatedColor = mix(vec3(luminance), color, effectiveSaturation);
    return clamp(saturatedColor, 0.0, 1.0);
}

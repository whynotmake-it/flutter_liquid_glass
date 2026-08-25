// Copyright 2025, Tim Lehmann for whynotmake.it
//
// Shared color utilities for the final liquid-glass render pass.
//
// The renderer's optical field and lighting are implemented by the dedicated
// geometry/final shaders. Keep this include limited to code used by that pass;
// the old standalone refraction/lighting pipeline was an unreferenced second
// material model and made it too easy for the two paths to drift.

const vec3 LUMA_WEIGHTS = vec3(0.299, 0.587, 0.114);

vec3 applySaturation(vec3 color, float saturation) {
    float luminance = dot(color, LUMA_WEIGHTS);
    vec3 saturatedColor = mix(vec3(luminance), color, saturation);
    return clamp(saturatedColor, 0.0, 1.0);
}

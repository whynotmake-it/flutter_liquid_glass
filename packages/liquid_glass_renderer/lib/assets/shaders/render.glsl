// Copyright 2025, Tim Lehmann for whynotmake.it
//
// Shared color utilities for the final liquid-glass render pass.
//
// The renderer's optical field and lighting are implemented by the dedicated
// geometry/final shaders. Keep this include limited to code used by that pass;
// the old standalone refraction/lighting pipeline was an unreferenced second
// material model and made it too easy for the two paths to drift.

// Use the Rec.709 primaries for the material luminance basis. The host-Metal
// color-card fit shows lower blue/cyan transfer error than the legacy Rec.601
// weights, while preserving the neutral and solid-face guards.
const vec3 LUMA_WEIGHTS = vec3(0.2126, 0.7152, 0.0722);

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

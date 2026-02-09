// Copyright 2025, Tim Lehmann for whynotmake.it
//
// Simple color + saturation shader for FakeGlass.
// Applied as an ImageFilter.shader so it only runs on the clipped region,
// unlike a ColorFilter which would be evaluated for every backdrop pixel.

#version 460 core
precision mediump float;

#include <flutter/runtime_effect.glsl>

// Luma weights (Rec. 709)
const vec3 LUMA_WEIGHTS = vec3(0.299, 0.587, 0.114);

uniform vec2 uSize;
uniform vec4 uGlassColor; // r, g, b, a
uniform float uSaturation;

uniform sampler2D uBackgroundTexture;

layout(location = 0) out vec4 fragColor;

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 uv = fragCoord / uSize;

    #ifdef IMPELLER_TARGET_OPENGLES
        uv.y = 1.0 - uv.y;
    #endif

    vec4 bg = texture(uBackgroundTexture, uv);

    vec3 color = mix(bg.rgb, uGlassColor.rgb, uGlassColor.a);

    // --- Apply saturation boost ---
    float luminance = dot(color, LUMA_WEIGHTS);
    color = clamp(mix(vec3(luminance), color, uSaturation), 0.0, 1.0);

    fragColor = vec4(color, bg.a);
}

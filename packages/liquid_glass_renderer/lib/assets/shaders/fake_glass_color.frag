// Copyright 2025, Tim Lehmann for whynotmake.it
//
// Fused tint + saturation path for Impeller. FakeGlass falls back to a canvas
// tint and color matrix when ImageFilter.shader is unavailable (for Skia).

#version 460 core
precision mediump float;

#include <flutter/runtime_effect.glsl>

const vec3 LUMA_WEIGHTS = vec3(0.299, 0.587, 0.114);

uniform vec2 uSize;
uniform vec4 uGlassColor;
uniform float uSaturation;
uniform sampler2D uBackgroundTexture;

layout(location = 0) out vec4 fragColor;

void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;
    vec4 background = texture(uBackgroundTexture, uv);
    vec3 color = mix(background.rgb, uGlassColor.rgb, uGlassColor.a);
    float luminance = dot(color, LUMA_WEIGHTS);
    color = clamp(mix(vec3(luminance), color, uSaturation), 0.0, 1.0);
    fragColor = vec4(color, background.a);
}

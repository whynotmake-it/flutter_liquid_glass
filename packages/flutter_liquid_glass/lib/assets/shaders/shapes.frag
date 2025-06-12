#version 320 es
precision highp float;

#include <flutter/runtime_effect.glsl>

layout(location = 0) uniform vec2 uSize;

layout(location = 1) uniform vec2 squircle1Center;
layout(location = 2) uniform vec2 squircle1Size;
layout(location = 3) uniform float squircle1CornerRadius;

layout(location = 4) uniform vec2 squircle2Center;
layout(location = 5) uniform vec2 squircle2Size;
layout(location = 6) uniform float squircle2CornerRadius;

layout(location = 7) uniform float uBlend;

layout(location = 0) out vec4 fragColor;

mat2 rotate2d(float angle) {
    return mat2(cos(angle), -sin(angle), sin(angle), cos(angle));
}

float sdfRRect( in vec2 p, in vec2 b, in float r ) {
    vec2 q = abs(p)-b+r;
    return min(max(q.x,q.y),0.0) + length(max(q,0.0)) - r;
}

float sdfEllipse(vec2 p, vec2 r) {
    r = max(r, 1e-4);
    float k1 = length(p / r);
    float k2 = length(p / (r * r));
    return (k1 * (k1 - 1.0)) / max(k2, 1e-4);
}

float opSmoothUnion(float d1, float d2, float k) {
    float h = clamp(0.5 + 0.5 * (d2 - d1) / k, 0.0, 1.0);
    return mix(d2, d1, h) - k * h * (1.0 - h);
}

void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;
    vec2 p = FlutterFragCoord().xy;

    float d1 = sdfRRect(p - squircle1Center, squircle1Size, squircle1CornerRadius);
    float d2 = sdfRRect(p - squircle2Center, squircle2Size, squircle2CornerRadius);

    float d = opSmoothUnion(d1, d2, uBlend);

    float alpha = 1.0 - smoothstep(0.0, 1.5, d);

    fragColor = vec4(0.0, 1.0, 1.0, alpha);
}

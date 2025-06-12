#version 300 es
precision mediump float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform sampler2D shapeLookupTable;
uniform int uShapeCount;

out vec4 fragColor;

const int SHAPE_TYPE_ELLIPSE = 0;
const int SHAPE_TYPE_RRECT = 1;

mat2 rotate2d(float angle) {
    return mat2(cos(angle), -sin(angle), sin(angle), cos(angle));
}

float sdfRRect(vec2 p, vec2 b, float r) {
    return length(max(abs(p) - b, 0.0)) - r;
}

float sdfEllipse(vec2 p, vec2 r) {
    r = max(r, 1e-4);
    float k1 = length(p / r);
    float k2 = length(p / (r * r));
    return (k1 * (k1 - 1.0)) / max(k2, 1e-4);
}

void main() {
    vec2 p = FlutterFragCoord().xy;
    float d = 1e20;

    for (int i = 0; i < uShapeCount; i++) {
        float textureWidth = float(uShapeCount * 2);
        vec2 uv1 = vec2((float(i * 2) + 0.5) / textureWidth, 0.5);
        vec2 uv2 = vec2((float(i * 2 + 1) + 0.5) / textureWidth, 0.5);

        vec4 data1 = texture(shapeLookupTable, uv1);
        vec4 data2 = texture(shapeLookupTable, uv2);

        float type = data1.r;
        vec2 position = data1.gb * uSize;
        vec2 size = vec2(data1.a * uSize.x, data2.r * uSize.y);
        float rotation = data2.g;

        vec2 q = p - position;
        q = rotate2d(-rotation) * q;

        float current_d;
        if (type < 0.5) {
            current_d = sdfEllipse(q, size);
        } else {
            float cornerRadius = data2.b * min(uSize.x, uSize.y);
            current_d = sdfRRect(q, size, cornerRadius);
        }

        d = min(d, current_d);
    }

    float alpha = 1.0 - smoothstep(0.0, 2.0, d);

    if (alpha > 0.0) {
        fragColor = vec4(1.0, 1.0, 1.0, alpha);
    } else {
        discard;
    }
}

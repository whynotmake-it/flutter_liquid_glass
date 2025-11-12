// Copyright 2025, Tim Lehmann for whynotmake.it
//
// Color-only pass for liquid glass with pre-computed geometry
// This shader outputs a solid color overlay with the geometry matte alpha
// and glass color opacity, for use with blend modes

#version 460 core
precision mediump float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform vec2 uOffset;

uniform vec4 uGlassColor;

uniform sampler2D uGeometryTexture;

layout(location = 0) out vec4 fragColor;

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;

    vec2 geometryUV = (fragCoord - uOffset) / uSize;
    #ifdef IMPELLER_TARGET_OPENGLES
        geometryUV.y = 1.0 - geometryUV.y;
    #endif

    vec4 geometryData = texture(uGeometryTexture, geometryUV);

    if (geometryData.a < 0.01) {
        fragColor = vec4(0);
        return;
    }

    // Combine geometry matte alpha with glass color opacity
    float alpha = geometryData.a * uGlassColor.a;
    fragColor = vec4(uGlassColor.rgb * alpha, alpha);
}

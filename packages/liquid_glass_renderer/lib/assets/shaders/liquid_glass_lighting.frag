// Copyright 2025, Tim Lehmann for whynotmake.it
//
// Lighting pass shader for liquid glass edges
// This shader computes rim lighting on glass edges based on the geometry texture
// and outputs with alpha for blend mode composition

#version 460 core
precision mediump float;

#define DEBUG_EDGES 0

#include <flutter/runtime_effect.glsl>
#include "displacement_encoding.glsl"

layout(location = 0) uniform vec2 uSize;
layout(location = 1) uniform vec2 uOffset;
layout(location = 2) uniform float uThickness;
layout(location = 3) uniform vec4 uLightConfig;

float uLightIntensity = uLightConfig.x;
float uAmbientStrength = uLightConfig.y;
vec2 uLightDirection = uLightConfig.zw;

uniform sampler2D uGeometryTexture;

layout(location = 0) out vec4 fragColor;

void main() {
    vec2 fragCoord = FlutterFragCoord().xy - uOffset;

    // We invert screenUV Y on OpenGL to sample the textures correctly
    #ifdef IMPELLER_TARGET_OPENGLES
        vec2 screenUV = vec2(fragCoord.x / uSize.x, 1.0 - (fragCoord.y / uSize.y));
    #else
        vec2 screenUV = vec2(fragCoord.x / uSize.x, fragCoord.y / uSize.y);
    #endif

    // Sample geometry texture to get displacement and normal
    vec4 geoData = texture(uGeometryTexture, screenUV);

    vec2 displacement = decodeDisplacement(geoData, uThickness);
    float height = geoData.b * uThickness;
    float alpha = geoData.a;

    if (alpha < 0.01) {
        fragColor = vec4(0.0);
        return;
    }

    float normalizedHeight = geoData.b;
    
    float edgeFactor = 1.0 - smoothstep(0.0, 0.5, normalizedHeight);

    if (edgeFactor < 0.01) {
        fragColor = vec4(0.0);
        return;
    }

    vec2 normalXY = normalize(displacement);

    float mainLight = max(0.0, dot(normalXY, uLightDirection));
    float oppositeLight = max(0.0, dot(normalXY, -uLightDirection));
    
    float totalInfluence = mainLight + oppositeLight * 0.8;

    float directional = (totalInfluence * totalInfluence) * uLightIntensity * 2.0 * 0.7;
    float ambient = uAmbientStrength * 0.4;
    
    float brightness = (directional + ambient) * edgeFactor;

    fragColor = vec4(vec3(brightness), brightness * alpha);
}
    
// Copyright 2025, Tim Lehmann for whynotmake.it
//
// Lighting-only pass for liquid glass with pre-computed geometry
// This shader reads displacement data from a pre-computed texture and outputs
// only the lighting effect (no background sampling) for use with blend modes

#version 460 core
precision mediump float;

#include <flutter/runtime_effect.glsl>
#include "displacement_encoding.glsl"
#include "render.glsl"

uniform vec2 uSize;
uniform vec2 uOffset;


uniform vec3 uLightConfig;
uniform vec2 uLightDirection;

float uLightIntensity = uLightConfig.x;
float uAmbientStrength = uLightConfig.y;
float uThickness = uLightConfig.z;

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

    float maxDisplacement = uThickness * 10.0;
    vec2 displacement = decodeDisplacement(geometryData, maxDisplacement);

    // Compute edge lighting
    float normalizedHeight = geometryData.b;

    float thicknessScale = clamp(40.0 / max(uThickness, 1.0), 1.0, 4.0);
    float edgeThreshold = mix(0.8, 0.5, 1.0 / thicknessScale);
    float edgeFactor = 1.0 - smoothstep(0.0, edgeThreshold, normalizedHeight);

    if (edgeFactor < 0.01) {
        fragColor = vec4(0);
        return;
    }

    vec2 normalXY = normalize(displacement);

    float mainLight = max(0.0, dot(normalXY, uLightDirection));
    float oppositeLight = max(0.0, dot(normalXY, -uLightDirection));

    float totalInfluence = mainLight + oppositeLight * 0.8;

    float directional = pow(totalInfluence, 1.5) * uLightIntensity * 3.0;
    float ambient = uAmbientStrength * 0.5;

    float brightness = (directional + ambient) * edgeFactor * thicknessScale * 0.8;

    // Output white light with brightness as intensity
    vec3 lightColor = vec3(1.0);

    float alpha = geometryData.a * brightness;
    fragColor = vec4(lightColor * alpha , alpha);
}

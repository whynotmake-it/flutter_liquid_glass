// Copyright 2025, Tim Lehmann for whynotmake.it
//
// Final rendering pass for liquid glass with pre-computed geometry
// This shader reads displacement data from a pre-computed texture and applies
// the liquid glass effect efficiently

#version 460 core
precision mediump float;

#define DEBUG_GEOMETRY 0

#include <flutter/runtime_effect.glsl>
#include "displacement_encoding.glsl"
#include "render.glsl"

uniform vec2 uSize;
uniform vec4 uGeometryTextureRect;
uniform mat4 uGeometryTransform;
uniform float uDevicePixelRatio;

uniform vec4 uGlassColor;
uniform vec3 uOpticalProps;
uniform vec3 uLightConfig;
uniform vec2 uLightDirection;


float uRefractiveIndex = uOpticalProps.x;
float uChromaticAberration = uOpticalProps.y;
float uThickness = uOpticalProps.z;
float uLightIntensity = uLightConfig.x;
float uAmbientStrength = uLightConfig.y;
float uSaturation = uLightConfig.z;

uniform sampler2D uBackgroundTexture;
uniform sampler2D uGeometryTexture;

layout(location = 0) out vec4 fragColor;

void main() {
    // FlutterFragCoord() returns logical pixels, but our geometry texture is in physical pixels
    // So we need to scale by devicePixelRatio to work in physical pixel space
    vec2 fragCoord = FlutterFragCoord().xy;

    vec2 geometryFragCoord = (uGeometryTransform * vec4(fragCoord, 0.0, 1.0)).xy ;
    
    vec2 screenUV = vec2(fragCoord.x / uSize.x, fragCoord.y / uSize.y);
    vec2 geometryUv = (geometryFragCoord - uGeometryTextureRect.xy) / uGeometryTextureRect.zw;
        
        
    #ifdef IMPELLER_TARGET_OPENGLES
        screenUV.y = 1.0 - screenUV.y;
        geometryUv.y = 1.0 - geometryUv.y;
    #endif


    if (geometryUv.x < 0.0 || geometryUv.x > 1.0 || geometryUv.y < 0.0 || geometryUv.y > 1.0) {
        fragColor = vec4(0.0);
        return;
    }
    vec4 geometryData = texture(uGeometryTexture, geometryUv);
    
    #if DEBUG_GEOMETRY
        fragColor = geometryData;
        return;
    #endif
    
    if (geometryData.a < 0.01) {
        fragColor = vec4(0);
        return;
    }
    
    float maxDisplacement = uThickness * 10.0;
    vec2 displacement = decodeDisplacement(geometryData, maxDisplacement);
    
    vec2 invUSize = 1.0 / uSize;
    
    vec4 refractColor;
    if (uChromaticAberration < 0.01) {
        vec2 refractedUV = screenUV + displacement * invUSize;
        refractColor = texture(uBackgroundTexture, refractedUV);
    } else {
        float dispersionStrength = uChromaticAberration * 0.5;
        vec2 redOffset = displacement * (1.0 + dispersionStrength);
        vec2 blueOffset = displacement * (1.0 - dispersionStrength);
        
        vec2 redUV = screenUV + redOffset * invUSize;
        vec2 greenUV = screenUV + displacement * invUSize;
        vec2 blueUV = screenUV + blueOffset * invUSize;
        
        float red = texture(uBackgroundTexture, redUV).r;
        vec4 greenSample = texture(uBackgroundTexture, greenUV);
        float blue = texture(uBackgroundTexture, blueUV).b;
        
        refractColor = vec4(red, greenSample.g, blue, greenSample.a);
    }
    
    vec4 finalColor = applyGlassColor(refractColor, uGlassColor);
    finalColor.rgb = applySaturation(finalColor.rgb, uSaturation);

    // Compute edge lighting
    float normalizedHeight = geometryData.b;
    float edgeFactor = 1.0 - smoothstep(0.0, 0.6, normalizedHeight);
    
    if (edgeFactor > 0.01) {
        vec2 normalXY = normalize(displacement);
        
        float mainLight = max(0.0, dot(normalXY, uLightDirection));
        float oppositeLight = max(0.0, dot(normalXY, -uLightDirection));
        
        float totalInfluence = mainLight + oppositeLight * 0.8;
        
        float directional = (totalInfluence * totalInfluence) * uLightIntensity * 2.0 * 0.7;
        float ambient = uAmbientStrength * 0.4;
        
        float brightness = (directional + ambient) * edgeFactor;
        
        // Mix lighting with the background pixel
        finalColor.rgb = mix(finalColor.rgb, vec3(1.0), brightness);
    }

    float alpha = geometryData.a;
    fragColor = vec4(finalColor.rgb * alpha, alpha);
}

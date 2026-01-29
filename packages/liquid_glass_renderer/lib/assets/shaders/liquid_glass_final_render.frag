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
uniform vec2 uGeometryOffset;
uniform vec2 uGeometrySize;

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
    
    vec2 screenUV = vec2(fragCoord.x / uSize.x, fragCoord.y / uSize.y);        
        
    #ifdef IMPELLER_TARGET_OPENGLES
        screenUV.y = 1.0 - screenUV.y;
    #endif

    vec2 geometryUV = (fragCoord - uGeometryOffset) / uGeometrySize;
    #ifdef IMPELLER_TARGET_OPENGLES
        geometryUV.y = 1.0 - geometryUV.y;
    #endif

    vec4 geometryData = texture(uGeometryTexture, geometryUV);
    
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
    
    // Apply glass color using alpha blending
    vec4 finalColor;
    finalColor.rgb = uGlassColor.rgb * uGlassColor.a + refractColor.rgb * (1.0 - uGlassColor.a);
    finalColor.a = refractColor.a;
    finalColor.rgb = applySaturation(finalColor.rgb, uSaturation);

    // Compute edge lighting using PROFILE-INDEPENDENT and THICKNESS-INDEPENDENT specular
    // B channel contains normalized signed distance: 0 = at edge, 1 = 10px inside
    // Encoding uses 10px range (SPECULAR_ENCODING_RANGE) to allow natural falloff
    float normalizedSd = geometryData.b;

    // Fixed-width rim specular using rational approximation: 1/(1+k*x^2)
    // With 10px encoding range, k=40 gives half-intensity at ~1.5px (matching kube.io)
    // At 1.5px: normalizedSd=0.15, rimFactor=1/(1+40*0.0225)=0.53
    // At 3px: normalizedSd=0.3, rimFactor=0.22
    // At 6px: normalizedSd=0.6, rimFactor=0.065
    float k = 40.0;
    float rimFactor = 1.0 / (1.0 + k * normalizedSd * normalizedSd);

    // Smoothly fade in the entire lighting effect based on thickness
    // Very thin glass (< 5px) gets reduced highlights to avoid visual noise
    float thicknessFade = clamp((uThickness - 5.0) * 0.2, 0.0, 1.0);

    float dispLen = length(displacement);
    if (rimFactor > 0.01 && thicknessFade > 0.01 && dispLen > 0.1) {
        // Use displacement direction for light angle (normalized)
        vec2 normalXY = displacement / dispLen;

        float mainLight = max(0.0, dot(normalXY, uLightDirection));
        float oppositeLight = max(0.0, dot(normalXY, -uLightDirection));

        float totalInfluence = mainLight + oppositeLight * 0.8;

        // Thickness-independent brightness calculation
        float directional = pow(totalInfluence, 1.5) * uLightIntensity * 2.5;
        float ambient = uAmbientStrength * 0.4;

        float brightness = (directional + ambient) * rimFactor * thicknessFade;

        vec3 bgColor = refractColor.rgb;
        float bgLuminance = dot(bgColor, LUMA_WEIGHTS);

        vec3 saturatedBg = bgColor / max(bgLuminance, 0.001);
        saturatedBg = mix(bgColor, saturatedBg, 0.8);
        float colorfulness = length(bgColor - vec3(bgLuminance));
        float colorMix = clamp(colorfulness * 1.0 + 0.5, 0.5, 1.0);
        vec3 highlightColor = mix(vec3(1.0), saturatedBg, colorMix);

        finalColor.rgb = mix(finalColor.rgb, highlightColor, brightness);
    }

    float alpha = geometryData.a;
    fragColor = vec4(finalColor.rgb * alpha, alpha);
}

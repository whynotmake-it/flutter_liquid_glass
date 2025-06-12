#version 320 es
precision highp float;

#include <flutter/runtime_effect.glsl>

layout(location = 0) uniform sampler2D uBackgroundTexture;
layout(location = 1) uniform sampler2D uDisplacementTexture;
layout(location = 2) uniform vec2 uSize;
layout(location = 3) uniform float uDisplacementScale = 1.0;

layout(location = 4) uniform vec4 uGlassColor = vec4(1.0, 1.0, 1.0, 1.0);

layout(location = 0) out vec4 fragColor;

#define ENCODING_SCALE 0.01


void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;
    
    vec4 displacementData = texture(uDisplacementTexture, uv);
    
    // Check if we're outside the liquid glass area
    if (displacementData.a == 0.0) {
        discard;
    }
    
    // Extract encoded displacement from red and green channels
    vec2 encodedDisplacement = vec2(displacementData.r, displacementData.g);
    
    // Extract normal.z from blue channel for reflection
    float normalZ = displacementData.b;
    
    // Decode displacement values from 0-1 range back to original range
    vec2 decodedDisplacement = (encodedDisplacement - 0.5) * 2.0;
    
    
    vec2 refractionDisplacement = (decodedDisplacement / ENCODING_SCALE) * uDisplacementScale;
    
    // Apply displacement more aggressively - multiply by a factor to make it visible
    vec2 displacementUV = refractionDisplacement / uSize;
    vec2 refractedUV = uv + displacementUV;
    
    // Sample the refracted background
    vec4 refractColor = texture(uBackgroundTexture, refractedUV);
    
    // Calculate reflection effect - much more subtle
    vec4 reflectColor = vec4(0.0);
    
    // Create subtle reflection pattern based on normal orientation
    float reflectionIntensity = clamp(abs(refractionDisplacement.x - refractionDisplacement.y) * 0.001, 0.0, 0.3);
    reflectColor = vec4(reflectionIntensity, reflectionIntensity, reflectionIntensity, 0.0);
    
    // Mix refraction and reflection based on normal.z (surface angle)
    vec4 liquidColor = mix(refractColor, reflectColor, (1.0 - normalZ) * 0.2);
    

    vec4 finalColor = mix(liquidColor, uGlassColor, uGlassColor.a);
    
    // Sample original background for falloff areas
    vec4 originalBgColor = texture(uBackgroundTexture, uv);
    
    // Create falloff effect for areas outside the main liquid glass
    float falloff = clamp(length(refractionDisplacement) / 100.0, 0.0, 1.0) * 0.1 + 0.9;
    vec4 falloffColor = mix(vec4(0.0), originalBgColor, falloff);
    
    // Use displacement alpha to control the liquid glass effect
    float liquidAlpha = 1.0 - displacementData.a;
    
    // Final mix: displaced liquid color where alpha is low, falloff background where alpha is high
    finalColor = clamp(finalColor, 0.0, 1.0);
    falloffColor = clamp(falloffColor, 0.0, 1.0);
    fragColor = mix(finalColor, falloffColor, liquidAlpha);
}

#version 320 es
precision highp float;

#include <flutter/runtime_effect.glsl>

layout(location = 0) uniform sampler2D uBackgroundTexture;
layout(location = 1) uniform sampler2D uDisplacementTexture;
layout(location = 2) uniform vec2 uSize;
layout(location = 3) uniform float uDisplacementScale = 1.0;
layout(location = 4) uniform float uChromaticAberration = 0.0;
layout(location = 5) uniform vec4 uGlassColor = vec4(1.0, 1.0, 1.0, 1.0);
layout(location = 6) uniform float uLightAngle = 0.785398; // 45 degrees in radians

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
    
    // Chromatic aberration: sample each color channel with slightly different offsets
    vec4 refractColor;
    if (uChromaticAberration > 0.0) {
        // Calculate chromatic aberration strength based on displacement magnitude
        float displacementMagnitude = length(refractionDisplacement);
        float chromaticStrength = displacementMagnitude * uChromaticAberration * 0.001;
        
        // Only apply chromatic aberration if there's significant displacement
        if (chromaticStrength > 0.0001) {
            // Calculate chromatic aberration offsets for each color channel
            vec2 chromaticOffset = normalize(displacementUV) * chromaticStrength;
            
            // Sample red channel with positive offset
            vec2 redUV = refractedUV + chromaticOffset;
            float red = texture(uBackgroundTexture, redUV).r;
            
            // Sample green channel with no additional offset
            float green = texture(uBackgroundTexture, refractedUV).g;
            
            // Sample blue channel with negative offset
            vec2 blueUV = refractedUV - chromaticOffset;
            float blue = texture(uBackgroundTexture, blueUV).b;
            
            // Get alpha from the center sample
            float alpha = texture(uBackgroundTexture, refractedUV).a;
            
            refractColor = vec4(red, green, blue, alpha);
        } else {
            // No significant displacement - sample normally
            refractColor = texture(uBackgroundTexture, refractedUV);
        }
    } else {
        // No chromatic aberration - sample normally
        refractColor = texture(uBackgroundTexture, refractedUV);
    }
    
    // Calculate edge highlights based on light angle and surface normals
    vec2 lightDirection = vec2(cos(uLightAngle), sin(uLightAngle));
    
    // Reconstruct approximate surface normal from displacement
    vec2 surfaceNormal = normalize(refractionDisplacement);
    
    // Calculate fresnel-like effect for edge highlights
    float viewDot = abs(dot(surfaceNormal, vec2(0.0, 1.0))); // View direction approximation
    float lightDot = dot(surfaceNormal, lightDirection);
    
    // Create edge highlight based on surface curvature and light direction
    float edgeHighlight = 0.0;
    if (length(refractionDisplacement) > 0.1) {
        // Calculate edge intensity based on displacement magnitude (edge detection)
        float edgeIntensity = smoothstep(0.0, 3.0, length(refractionDisplacement) * 0.01);
        
        // Fresnel-like falloff for realistic edge lighting
        float fresnelFactor = pow(1.0 - viewDot, 2.0);
        
        // Light reflection based on surface normal and light direction
        // Create highlights on both light-facing and opposite sides
        float frontLight = max(0.0, lightDot);
        float backLight = max(0.0, -lightDot); // Rim lighting on opposite side
        
        // Combine front and back lighting with different intensities
        float reflectionFactor = frontLight * 0.8 + backLight * 0.6 + 0.3;
        
        // Combine factors for final edge highlight
        edgeHighlight = edgeIntensity * fresnelFactor * reflectionFactor;
        
        // Make highlights more prominent and create falloff
        edgeHighlight = pow(edgeHighlight, 0.8) * 1;
    }
    
    // Create highlight color that bleeds inward
    vec4 highlightColor = vec4(1.0, 1.0, 1.0, edgeHighlight);
    
    // Calculate reflection effect - much more subtle
    vec4 reflectColor = vec4(0.0);
    
    // Create subtle reflection pattern based on normal orientation
    float reflectionIntensity = clamp(abs(refractionDisplacement.x - refractionDisplacement.y) * 0.001, 0.0, 0.3);
    reflectColor = vec4(reflectionIntensity, reflectionIntensity, reflectionIntensity, 0.0);
    
    // Mix refraction and reflection based on normal.z (surface angle)
    vec4 liquidColor = mix(refractColor, reflectColor, (1.0 - normalZ) * 0.2);
    
    // Add edge highlights to the liquid color
    liquidColor.rgb = mix(liquidColor.rgb, highlightColor.rgb, highlightColor.a);
    
    // Apply realistic glass color influence
    vec4 finalColor = liquidColor;
    
    if (uGlassColor.a > 0.0) {
        // Calculate luminance of glass color to determine if it's light or dark
        float glassLuminance = dot(uGlassColor.rgb, vec3(0.299, 0.587, 0.114));
        
        // For realistic glass behavior:
        // - Dark glass colors should darken the refracted light (multiply)
        // - Light glass colors should tint while preserving brightness (overlay/screen)
        if (glassLuminance < 0.5) {
            // Dark glass: use multiply blending to darken
            vec3 darkened = liquidColor.rgb * (uGlassColor.rgb * 2.0);
            finalColor.rgb = mix(liquidColor.rgb, darkened, uGlassColor.a);
        } else {
            // Light glass: use screen blending to lighten and tint
            vec3 invLiquid = vec3(1.0) - liquidColor.rgb;
            vec3 invGlass = vec3(1.0) - uGlassColor.rgb;
            vec3 screened = vec3(1.0) - (invLiquid * invGlass);
            
            // Blend between original and screened result
            finalColor.rgb = mix(liquidColor.rgb, screened, uGlassColor.a * 0.8);
        }
        
        // Preserve the original alpha
        finalColor.a = liquidColor.a;
    }
    
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

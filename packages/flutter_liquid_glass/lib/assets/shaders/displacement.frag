#version 320 es
precision highp float;

#include <flutter/runtime_effect.glsl>
#include "common.glsl"

layout(location = 0) uniform sampler2D uBackgroundTexture;
layout(location = 1) uniform sampler2D uDisplacementTexture;
layout(location = 2) uniform vec2 uSize;
layout(location = 3) uniform float uChromaticAberration = 0.0;
layout(location = 4) uniform vec4 uGlassColor = vec4(1.0, 1.0, 1.0, 1.0);
layout(location = 5) uniform float uLightAngle = 0.785398;
layout(location = 6) uniform float uLightIntensity = 1.0;
layout(location = 7) uniform float uAmbientStrength = 0.1;
layout(location = 8) uniform float uOutlineIntensity = 3.3;
layout(location = 9) uniform float uThickness;
layout(location = 10) uniform float uRefractiveIndex = 1.2;
layout(location = 11) uniform vec2 uViewportSize;
layout(location = 12) uniform vec2 uViewportOffset;

layout(location = 0) out vec4 fragColor;

// Calculate lighting effects based on displacement data
vec3 calculateLighting(vec2 uv, vec4 displacementData, vec2 refractionDisplacement) {
    float alpha = 1.0 - displacementData.a;
    
    // Create a shape mask based on alpha
    float shape = smoothstep(0.1, 0.9, alpha);
    
    // Calculate distance from edge for ambient lighting
    // Use displacement magnitude as a proxy for distance from edge
    float displacementMag = length(refractionDisplacement);
    float edgeDistance = smoothstep(0.0, 50.0, displacementMag);
    
    // Ambient lighting - subtle glow throughout the shape
    float ambientLight = shape * smoothstep(0.2, 0.8, edgeDistance) * uAmbientStrength;
    
    // Calculate light direction (matching reference shader)
    vec2 lightDir = normalize(vec2(cos(uLightAngle), sin(uLightAngle)));
    
    // Use normalized displacement as surface normal approximation
    vec2 surfaceNormal = length(refractionDisplacement) > 0.001 ? 
                        normalize(refractionDisplacement) : vec2(0.0, 1.0);
    
    // Diffuse lighting for outline effect
    float diffuseLight = uOutlineIntensity * dot(surfaceNormal, lightDir);
    diffuseLight *= shape * smoothstep(0.3, 0.0, edgeDistance) * 0.3;
    
    // Combine lighting effects
    vec3 lighting = vec3(ambientLight + abs(diffuseLight));
    
    // Add subtle rim lighting based on normal.z for extra definition
    float normalZ = displacementData.b;
    float rimLight = pow(1.0 - normalZ, 2.0) * shape * 0.05;
    lighting += vec3(rimLight);
    
    return lighting * uLightIntensity;
}


void main() {
    vec2 screenUV = FlutterFragCoord().xy / uSize;
    

    
    vec4 normalHeightData = texture(uDisplacementTexture, screenUV);
    
    // Check if we're outside the liquid glass area
    if (normalHeightData.a == 0.0) {
        discard;
    }
    
    // Decode normal from RGB channels (map from [0,1] back to [-1,1])
    vec3 normal = (normalHeightData.rgb - 0.5) * 2.0;    
    normal = normalize(normal);
   
    float normalizedHeight = normalHeightData.a;; // Extract height
    float height = normalizedHeight * uThickness;
    
    // Calculate refraction using the decoded normal and height
    float baseHeight = uThickness * 8.0;
    vec3 incident = vec3(0.0, 0.0, -1.0);
    vec3 refractVec = refract(incident, normal, 1.0 / uRefractiveIndex);
    
    float refractLength = (height + baseHeight) / max(0.001, dot(vec3(0.0, 0.0, -1.0), refractVec));
    
    // Calculate the 2D refraction displacement
    vec2 refractionDisplacement = refractVec.xy * refractLength;
    
    // Apply displacement to UV coordinates, scaling by viewport size
    vec2 displacementUV = refractionDisplacement / uSize;
    vec2 refractedUV = screenUV + displacementUV;
    
    
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
            float bgAlpha = texture(uBackgroundTexture, refractedUV).a;
            
            refractColor = vec4(red, green, blue, bgAlpha);
        } else {
            // No significant displacement - sample normally
            refractColor = texture(uBackgroundTexture, refractedUV);
        }
    } else {
        // No chromatic aberration - sample normally
        refractColor = texture(uBackgroundTexture, refractedUV);
    }
    
    // Calculate reflection effect - much more subtle
    vec4 reflectColor = vec4(0.0);
    
    // Create subtle reflection pattern based on normal orientation
    float reflectionIntensity = clamp(abs(refractionDisplacement.x - refractionDisplacement.y) * 0.001, 0.0, 0.3);
    reflectColor = vec4(reflectionIntensity, reflectionIntensity, reflectionIntensity, 0.0);
    
    // Mix refraction and reflection based on normal.z (surface angle)
    vec4 liquidColor = mix(refractColor, reflectColor, (1.0 - normal.z) * 0.2);
    
    // Calculate lighting effects
    vec3 lighting = calculateLighting(screenUV, normalHeightData, refractionDisplacement);
    
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
            finalColor.rgb = mix(liquidColor.rgb, screened, uGlassColor.a);
        }
        
        // Preserve the original alpha
        finalColor.a = liquidColor.a;
    }
    
    // Add lighting effects to final color
    finalColor.rgb += lighting;
    
    // Sample original background for falloff areas
    vec4 originalBgColor = texture(uBackgroundTexture, screenUV);
    
    // Create falloff effect for areas outside the main liquid glass
    float falloff = clamp(length(refractionDisplacement) / 100.0, 0.0, 1.0) * 0.1 + 0.9;
    vec4 falloffColor = mix(vec4(0.0), originalBgColor, falloff);
    

    
    // Final mix: displaced liquid color where alpha is low, falloff background where alpha is high
    finalColor = clamp(finalColor, 0.0, 1.0);
    falloffColor = clamp(falloffColor, 0.0, 1.0);
    fragColor = mix(finalColor, falloffColor, 0);
}

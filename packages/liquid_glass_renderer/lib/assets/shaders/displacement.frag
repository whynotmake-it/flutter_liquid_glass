#version 320 es
precision highp float;

#include <flutter/runtime_effect.glsl>
#include "common.glsl"

layout(location = 0) uniform sampler2D uBackgroundTexture;
layout(location = 1) uniform vec2 uSize;
layout(location = 2) uniform float uChromaticAberration = 0.0;
layout(location = 3) uniform vec4 uGlassColor = vec4(1.0, 1.0, 1.0, 1.0);
layout(location = 4) uniform float uLightAngle = 0.785398;
layout(location = 5) uniform float uLightIntensity = 1.0;
layout(location = 6) uniform float uAmbientStrength = 0.1;
layout(location = 7) uniform float uOutlineIntensity = 3.3;
layout(location = 8) uniform float uThickness;
layout(location = 9) uniform float uRefractiveIndex = 1.2;

// Shape uniforms
layout(location = 10) uniform float uShape1Type;
layout(location = 11) uniform vec2 uShape1Center;
layout(location = 12) uniform vec2 uShape1Size;
layout(location = 13) uniform float uShape1CornerRadius;
layout(location = 14) uniform float uShape2Type;
layout(location = 15) uniform vec2 uShape2Center;
layout(location = 16) uniform vec2 uShape2Size;
layout(location = 17) uniform float uShape2CornerRadius;
layout(location = 18) uniform float uBlend;

layout(location = 0) out vec4 fragColor;

// Shape generation functions from shapes.frag
mat2 rotate2d(float angle) {
    return mat2(cos(angle), -sin(angle), sin(angle), cos(angle));
}

float sdfRRect( in vec2 p, in vec2 b, in float r ) {
    float shortest = min(b.x, b.y);
    r = min(r, shortest);
    vec2 q = abs(p)-b+r;
    return min(max(q.x,q.y),0.0) + length(max(q,0.0)) - r;
}

float sdfRect(vec2 p, vec2 b) {
    vec2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float sdfSquircle(vec2 p, vec2 b, float r, float k) {
    if (r < 0.001) {
        return sdfRect(p, b);
    }

    float shortest = min(b.x, b.y);
    r = min(r, shortest);

    vec2 d = abs(p) - b + r;
    float s = max(d.x, d.y);
    
    if (s <= 0.0) {
        // Inside the shape
        return s - r;
    }

    // In corner region - apply squircle shaping
    vec2 q = max(d, 0.0);
    float cornerDist = pow(pow(q.x/r, k) + pow(q.y/r, k), 1.0/k);
    return (cornerDist - 1.0) * r;
}

float sdfEllipse(vec2 p, vec2 r) {
    r = max(r, 1e-4);
    float k1 = length(p / r);
    float k2 = length(p / (r * r));
    return (k1 * (k1 - 1.0)) / max(k2, 1e-4);
}

float smoothUnion(float d1, float d2, float k) {
    float e = max(k - abs(d1 - d2), 0.0);
    return min(d1, d2) - e * e * 0.25 / k;
}

float getShapeSDF(float type, vec2 p, vec2 center, vec2 size, float r) {
    if (type == 1.0) { // squircle
        return sdfSquircle(p - center, size / 2.0, r, 2.0);
    }
    if (type == 2.0) { // ellipse
        return sdfEllipse(p - center, size / 2.0);
    }
    if (type == 3.0) { // rounded rectangle
        return sdfRRect(p - center, size / 2.0, r);
    }
    return 1e9; // none
}

float sceneSDF(vec2 p) {
    float d1 = getShapeSDF(uShape1Type, p, uShape1Center, uShape1Size, uShape1CornerRadius);
    float d2 = getShapeSDF(uShape2Type, p, uShape2Center, uShape2Size, uShape2CornerRadius);
    return smoothUnion(d1, d2, uBlend);
}

// Calculate 3D normal using derivatives
vec3 getNormal(float sd, float thickness) {
    float dx = dFdx(sd);
    float dy = dFdy(sd);
    
    // The cosine and sine between normal and the xy plane
    float n_cos = max(thickness + sd, 0.0) / thickness;
    float n_sin = sqrt(max(0.0, 1.0 - n_cos * n_cos));
    
    // Return the normal directly without encoding
    return normalize(vec3(dx * n_cos, dy * n_cos, n_sin));
}

// Calculate height/depth of the liquid surface
float getHeight(float sd, float thickness) {
    if (sd >= 0.0 || thickness <= 0.0) {
        return 0.0;
    }
    if (sd < -thickness) {
        return thickness;
    }
    
    float x = thickness + sd;
    return sqrt(max(0.0, thickness * thickness - x * x));
}

// Calculate lighting effects based on displacement data
vec3 calculateLighting(vec2 uv, vec3 normal, float height, vec2 refractionDisplacement, float thickness) {
    // Basic shape mask
    float normalizedHeight = thickness > 0.0 ? height / thickness : 0.0;
    float shape = smoothstep(0.0, 0.9, 1.0 - normalizedHeight);

    // If we're outside the shape, no lighting.
    if (shape < 0.01) {
        return vec3(0.0);
    }
    
    vec3 viewDir = vec3(0.0, 0.0, 1.0);

    // --- Rim lighting (Fresnel) ---
    // This creates a constant, soft outline.
    float fresnel = pow(1.0 - max(0.0, dot(normal, viewDir)), 3.0);
    vec3 rimLight = vec3(fresnel * uOutlineIntensity * 0.5);

    // --- Light-dependent effects ---
    vec3 lightDir = normalize(vec3(cos(uLightAngle), sin(uLightAngle), -0.7));
    vec3 oppositeLightDir = normalize(vec3(-lightDir.xy, lightDir.z));

    // Common vectors needed for both light sources
    vec3 halfwayDir1 = normalize(lightDir + viewDir);
    float specDot1 = max(0.0, dot(normal, halfwayDir1));
    vec3 halfwayDir2 = normalize(oppositeLightDir + viewDir);
    float specDot2 = max(0.0, dot(normal, halfwayDir2));

    // --- Environment Reflection Sampling ---
    // This is used for both the glint and the base reflection for efficiency.
    vec3 reflectedColor = vec3(1.0); // Default to white
    const float reflectionSampleDistance = 300.0;
    const float reflectionBlur = 10.0; // A large blur will wash out distinct colors.

    // Using the normal's XY components provides a more direct "outward" vector
    // than the physically correct reflect() function for this specific visual effect.
    if (length(normal.xy) > 0.001) {
        vec2 reflectionDir = normalize(normal.xy);
        vec2 baseSampleUV = uv + reflectionDir * reflectionSampleDistance / uSize;

        // Simple 4-tap blur for the reflection
        vec2 blurOffset = vec2(reflectionBlur) / uSize;
        vec3 sampledColor = vec3(0.0);
        sampledColor += texture(uBackgroundTexture, baseSampleUV + blurOffset * vec2( 1,  1)).rgb;
        sampledColor += texture(uBackgroundTexture, baseSampleUV + blurOffset * vec2(-1,  1)).rgb;
        sampledColor += texture(uBackgroundTexture, baseSampleUV + blurOffset * vec2( 1, -1)).rgb;
        sampledColor += texture(uBackgroundTexture, baseSampleUV + blurOffset * vec2(-1, -1)).rgb;
        reflectedColor = sampledColor / 4.0;
    }
    
    // 1. Sharp surface glint (tinted by the environment)
    float glintExponent = mix(350.0, 512.0, smoothstep(5.0, 25.0, uThickness));
    float sharpFactor = pow(specDot1, glintExponent) + pow(specDot2, glintExponent * 1.2);

    // First, calculate the pure white glint intensity.
    vec3 whiteGlint = vec3(sharpFactor) * uLightIntensity * 2.5;
    // Then, multiply by the reflected color to tint the glint. This is the key change.
    vec3 sharpGlint = whiteGlint * reflectedColor;

    // 2. Soft internal bleed, controlled by refraction amount
    float displacementMag = length(refractionDisplacement);
    float internalIntensity = smoothstep(5.0, 40.0, displacementMag);
    
    // A very low exponent creates a wide, soft glow.
    float softFactor = pow(specDot1, 32.0) + pow(specDot2, 32.0);
    vec3 softBleed = vec3(softFactor) * uLightIntensity * 0.8;

    // 3. Base Environment Reflection (subtle, always on)
    const float reflectionBase = .1;
    const float reflectionFresnelStrength = 0.5;
    float reflectionFresnel = pow(1.0 - max(0.0, dot(normal, viewDir)), 3.0);
    float reflectionIntensity = reflectionBase + reflectionFresnel * reflectionFresnelStrength;
    vec3 environmentReflection = reflectedColor * reflectionIntensity;

    // Combine lighting components
    vec3 lighting = rimLight + sharpGlint + (softBleed * internalIntensity) + environmentReflection;

    // Final combination
    return lighting * shape;
}

void main() {
    vec2 screenUV = FlutterFragCoord().xy / uSize;
    vec2 p = FlutterFragCoord().xy;
    
    // Generate shape and calculate normal/height directly
    float sd = sceneSDF(p);
    float alpha = smoothstep(-4.0, 0.0, sd);
    
    // If we're completely outside the glass area (with smooth transition)
    if (alpha > 0.999) {
        fragColor = texture(uBackgroundTexture, screenUV);
        return;
    }
    
    // If thickness is effectively zero, behave like a simple blur
    if (uThickness < 0.01) {
        fragColor = texture(uBackgroundTexture, screenUV);
        return;
    }
    
    // Calculate normal and height directly - use normal as is
    vec3 normal = getNormal(sd, uThickness);
    float height = getHeight(sd, uThickness);
    
    // --- Refraction & Chromatic Aberration ---
    float baseHeight = uThickness * 8.0;
    vec3 incident = vec3(0.0, 0.0, -1.0);
    
    vec4 refractColor;
    vec2 refractionDisplacement;

    // To simulate a prism, we calculate refraction separately for each color channel
    // by slightly varying the refractive index.
    if (uChromaticAberration > 0.001) {
        float iorR = uRefractiveIndex - uChromaticAberration * 0.04; // Less deviation for red
        float iorG = uRefractiveIndex;
        float iorB = uRefractiveIndex + uChromaticAberration * 0.08; // More deviation for blue

        // Red channel
        vec3 refractVecR = refract(incident, normal, 1.0 / iorR);
        float refractLengthR = (height + baseHeight) / max(0.001, abs(refractVecR.z));
        vec2 refractedUVR = screenUV + (refractVecR.xy * refractLengthR) / uSize;
        float red = texture(uBackgroundTexture, refractedUVR).r;

        // Green channel (we'll use this for the main displacement and alpha)
        vec3 refractVecG = refract(incident, normal, 1.0 / iorG);
        float refractLengthG = (height + baseHeight) / max(0.001, abs(refractVecG.z));
        refractionDisplacement = refractVecG.xy * refractLengthG; 
        vec2 refractedUVG = screenUV + refractionDisplacement / uSize;
        vec4 greenSample = texture(uBackgroundTexture, refractedUVG);
        float green = greenSample.g;
        float bgAlpha = greenSample.a;

        // Blue channel
        vec3 refractVecB = refract(incident, normal, 1.0 / iorB);
        float refractLengthB = (height + baseHeight) / max(0.001, abs(refractVecB.z));
        vec2 refractedUVB = screenUV + (refractVecB.xy * refractLengthB) / uSize;
        float blue = texture(uBackgroundTexture, refractedUVB).b;
        
        refractColor = vec4(red, green, blue, bgAlpha);
    } else {
        // Default path for no chromatic aberration
        vec3 refractVec = refract(incident, normal, 1.0 / uRefractiveIndex);
        float refractLength = (height + baseHeight) / max(0.001, abs(refractVec.z));
        refractionDisplacement = refractVec.xy * refractLength;
        vec2 refractedUV = screenUV + refractionDisplacement / uSize;
        refractColor = texture(uBackgroundTexture, refractedUV);
    }
    
    // Calculate reflection effect
    vec4 reflectColor = vec4(0.0);
    float reflectionIntensity = clamp(abs(refractionDisplacement.x - refractionDisplacement.y) * 0.001, 0.0, 0.3);
    reflectColor = vec4(reflectionIntensity, reflectionIntensity, reflectionIntensity, 0.0);
    
    // Mix refraction and reflection based on normal.z
    vec4 liquidColor = mix(refractColor, reflectColor, (1.0 - normal.z) * 0.2);
    
    // Calculate lighting effects
    vec3 lighting = calculateLighting(screenUV, normal, height, refractionDisplacement, uThickness);
    
    // Apply realistic glass color influence
    vec4 finalColor = liquidColor;
    
    if (uGlassColor.a > 0.0) {
        float glassLuminance = dot(uGlassColor.rgb, vec3(0.299, 0.587, 0.114));
        
        if (glassLuminance < 0.5) {
            vec3 darkened = liquidColor.rgb * (uGlassColor.rgb * 2.0);
            finalColor.rgb = mix(liquidColor.rgb, darkened, uGlassColor.a);
        } else {
            vec3 invLiquid = vec3(1.0) - liquidColor.rgb;
            vec3 invGlass = vec3(1.0) - uGlassColor.rgb;
            vec3 screened = vec3(1.0) - (invLiquid * invGlass);
            finalColor.rgb = mix(liquidColor.rgb, screened, uGlassColor.a);
        }
        
        finalColor.a = liquidColor.a;
    }
    
    // Add lighting effects to final color
    finalColor.rgb += lighting;
    
    // Sample original background for falloff areas
    vec4 originalBgColor = texture(uBackgroundTexture, screenUV);
    
    // Create falloff effect for areas outside the main liquid glass
    float falloff = clamp(length(refractionDisplacement) / 100.0, 0.0, 1.0) * 0.1 + 0.9;
    vec4 falloffColor = mix(vec4(0.0), originalBgColor, falloff);
    
    // Final mix: blend between displaced liquid color and background based on edge alpha
    finalColor = clamp(finalColor, 0.0, 1.0);
    falloffColor = clamp(falloffColor, 0.0, 1.0);
    
    // Use alpha for smooth transition at boundaries
    vec4 backgroundColor = texture(uBackgroundTexture, screenUV);
    fragColor = mix(backgroundColor, finalColor, 1.0 - alpha);
}

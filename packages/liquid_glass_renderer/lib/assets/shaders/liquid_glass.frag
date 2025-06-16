// Copyright 2025, Tim Lehmann for whynotmake.it
//
// This shader is based on a bunch of sources:
// - https://www.shadertoy.com/view/wccSDf for the refraction
// - https://iquilezles.org/articles/distfunctions2d/ for SDFs
// - Gracious help from @dkwingsmt for the Squircle SDF
//
// Feel free to use this shader in your own projects, it'd be lovely if you could
// give some credit like I did here.

#version 320 es
precision mediump float;

#include <flutter/runtime_effect.glsl>


layout(location = 0) uniform float uSizeW;
layout(location = 1) uniform float uSizeH;

vec2 uSize = vec2(uSizeW, uSizeH);

layout(location = 2) uniform float uChromaticAberration = 0.0;

layout(location = 3) uniform float uGlassColorR;
layout(location = 4) uniform float uGlassColorG;
layout(location = 5) uniform float uGlassColorB;
layout(location = 6) uniform float uGlassColorA;

vec4 uGlassColor = vec4(uGlassColorR, uGlassColorG, uGlassColorB, uGlassColorA);

layout(location = 7) uniform float uLightAngle = 0.785398;
layout(location = 8) uniform float uLightIntensity = 1.0;
layout(location = 9) uniform float uAmbientStrength = 0.1;
layout(location = 10) uniform float uThickness;
layout(location = 11) uniform float uRefractiveIndex = 1.2;

// Shape uniforms
layout(location = 12) uniform float uShape1Type;
layout(location = 13) uniform float uShape1CenterX;
layout(location = 14) uniform float uShape1CenterY;
layout(location = 15) uniform float uShape1SizeW;
layout(location = 16) uniform float uShape1SizeH;
layout(location = 17) uniform float uShape1CornerRadius;

vec2 uShape1Center = vec2(uShape1CenterX, uShape1CenterY);
vec2 uShape1Size = vec2(uShape1SizeW, uShape1SizeH);

layout(location = 18) uniform float uShape2Type;
layout(location = 19) uniform float uShape2CenterX;
layout(location = 20) uniform float uShape2CenterY;
layout(location = 21) uniform float uShape2SizeW;
layout(location = 22) uniform float uShape2SizeH;
layout(location = 23) uniform float uShape2CornerRadius;

vec2 uShape2Center = vec2(uShape2CenterX, uShape2CenterY);
vec2 uShape2Size = vec2(uShape2SizeW, uShape2SizeH);

layout(location = 24) uniform float uShape3Type;
layout(location = 25) uniform float uShape3CenterX;
layout(location = 26) uniform float uShape3CenterY;
layout(location = 27) uniform float uShape3SizeW;
layout(location = 28) uniform float uShape3SizeH;
layout(location = 29) uniform float uShape3CornerRadius;

vec2 uShape3Center = vec2(uShape3CenterX, uShape3CenterY);
vec2 uShape3Size = vec2(uShape3SizeW, uShape3SizeH);

layout(location = 30) uniform float uBlend;

uniform sampler2D uBackgroundTexture;
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

float sdfSquircle(vec2 p, vec2 b, float r, float n) {
    float shortest = min(b.x, b.y);
    r = min(r, shortest);

    vec2 q = abs(p) - b + r;
    // The component-wise power function `pow(max(q, 0.0), n)` calculates the
    // superelliptical curve for the corner. The result is then raised to `1.0/n`
    // to get the final distance, which is equivalent to the Lp-norm. This
    // provides a distance field for a rectangle with superelliptical corners. A
    // value of n=2.0 results in standard circular corners. The
    // `min(max(q.x, q.y), 0.0)` part handles the distance inside the shape
    // correctly.
    return min(max(q.x, q.y), 0.0) + pow(
        pow(max(q.x, 0.0), n) + pow(max(q.y, 0.0), n),
        1.0 / n
    ) - r;
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
    float d3 = getShapeSDF(uShape3Type, p, uShape3Center, uShape3Size, uShape3CornerRadius);
    return smoothUnion(smoothUnion(d1, d2, uBlend), d3, uBlend);
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
    vec3 rimLight = vec3(fresnel * uAmbientStrength * 0.5);

    // --- Light-dependent effects ---
    vec3 lightDir = normalize(vec3(cos(uLightAngle), sin(uLightAngle), -0.7));
    vec3 oppositeLightDir = normalize(vec3(-lightDir.xy, lightDir.z));

    // Common vectors needed for both light sources
    vec3 halfwayDir1 = normalize(lightDir + viewDir);
    float specDot1 = max(0.0, dot(normal, halfwayDir1));
    vec3 halfwayDir2 = normalize(oppositeLightDir + viewDir);
    float specDot2 = max(0.0, dot(normal, halfwayDir2));

    // 1. Sharp surface glint (pure white)
    float glintExponent = mix(350.0, 512.0, smoothstep(5.0, 25.0, uThickness));
    float sharpFactor = pow(specDot1, glintExponent) + pow(specDot2, glintExponent * 1.2);

    // Pure white glint without environment tinting
    vec3 sharpGlint = vec3(sharpFactor) * uLightIntensity * 2.5;

    // 2. Soft internal bleed, controlled by refraction amount
    float displacementMag = length(refractionDisplacement);
    float internalIntensity = smoothstep(5.0, 40.0, displacementMag);
    
    // A very low exponent creates a wide, soft glow.
    float softFactor = pow(specDot1, 32.0) + pow(specDot2, 32.0);
    vec3 softBleed = vec3(softFactor) * uLightIntensity * 0.8;

    // Combine lighting components
    vec3 lighting = rimLight + sharpGlint + (softBleed * internalIntensity);

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
    
    // Mix refraction and reflection based on normal.z
    vec4 liquidColor = refractColor;
    
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
        
    // Use alpha for smooth transition at boundaries
    vec4 backgroundColor = texture(uBackgroundTexture, screenUV);
    fragColor = mix(backgroundColor, finalColor, 1.0 - alpha);
}

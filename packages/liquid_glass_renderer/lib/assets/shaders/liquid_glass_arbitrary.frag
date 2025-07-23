// Copyright 2025, Tim Lehmann for whynotmake.it
//
// Alternative liquid glass shader with different normal calculation approach
// This demonstrates how the shared rendering pipeline makes it easy to create variants

#version 320 es
precision mediump float;

#define DEBUG_NORMALS 0
#define DEBUG_BLUR_MATTE 0

#include <flutter/runtime_effect.glsl>
#include "shared.glsl"

layout(location = 0) uniform float uSizeW;
layout(location = 1) uniform float uSizeH;

vec2 uSize = vec2(uSizeW, uSizeH);

layout(location = 2) uniform float uForegroundSizeW;
layout(location = 3) uniform float uForegroundSizeH;
vec2 uForegroundSize = vec2(uForegroundSizeW, uForegroundSizeH);

layout(location = 4) uniform float uChromaticAberration = 0.0;

layout(location = 5) uniform float uGlassColorR;
layout(location = 6) uniform float uGlassColorG;
layout(location = 7) uniform float uGlassColorB;
layout(location = 8) uniform float uGlassColorA;

vec4 uGlassColor = vec4(uGlassColorR, uGlassColorG, uGlassColorB, uGlassColorA);

layout(location = 9) uniform float uLightAngle;
layout(location = 10) uniform float uLightIntensity;
layout(location = 11) uniform float uAmbientStrength;
layout(location = 12) uniform float uThickness;
layout(location = 13) uniform float uRefractiveIndex;

layout(location = 14) uniform float uOffsetX;
layout(location = 15) uniform float uOffsetY;
vec2 uOffset = vec2(uOffsetX, uOffsetY);

// Saturation and lightness uniforms
layout(location = 16) uniform float uSaturation = 1.0;
layout(location = 17) uniform float uLightness = 1.0;

// Gaussian blur uniform
layout(location = 18) uniform float uGaussianBlur;

uniform sampler2D uBackgroundTexture;
uniform sampler2D uForegroundTexture;

// A pre-blurred version of the foreground texture.
// This will be eroded, so that the alpha is always 0 at the edge.
// This is used to calculate the normal.
uniform sampler2D uForegroundBlurredTexture;
layout(location = 0) out vec4 fragColor;


// Convert blurred alpha to approximate SDF that matches real SDF behavior
float approximateSDF(float blurredAlpha, float thickness) {
    // Convert alpha (0=edge, 1=center) to SDF-like values (0=edge, -thickness=center)
    // This matches how real SDFs work: negative inside, zero at edge
    float normalizedDistance = smoothstep(0.0, 1.0, blurredAlpha);
    return -normalizedDistance * thickness;
}



// Find the center of mass of the shape
vec2 findShapeCenter(vec2 currentUV) {
    vec2 texelSize = 2.0 / uForegroundSize;
    vec2 centerSum = vec2(0.0);
    float totalAlpha = 0.0;
    
    // Sample in a reasonable radius around the current point
    int sampleRadius = 10;
    for (int y = -sampleRadius; y <= sampleRadius; y++) {
        for (int x = -sampleRadius; x <= sampleRadius; x++) {
            vec2 sampleUV = currentUV + vec2(float(x), float(y)) * texelSize;
            
            // Make sure we're within texture bounds
            if (sampleUV.x >= 0.0 && sampleUV.x <= 1.0 && sampleUV.y >= 0.0 && sampleUV.y <= 1.0) {
                float alpha = texture(uForegroundTexture, sampleUV).a;
                if (alpha > 0.1) {
                    centerSum += sampleUV * alpha;
                    totalAlpha += alpha;
                }
            }
        }
    }
    
    // Return center of mass, or current UV if no valid samples found
    return totalAlpha > 0.0 ? centerSum / totalAlpha : currentUV;
}





// Helper for robust, multi-scale gradient calculation using a Sobel operator.
// This is more noise-resistant than simple central differences.
vec2 calculateGradient(sampler2D tex, vec2 uv, vec2 texelSize) {
    vec2 gradient = vec2(0.0);
    float totalWeight = 0.0;

    // Sample at different scales (1x, 2x, 4x) to capture both fine and broad details.
    // This creates a smooth gradient, even from noisy or wide-blurred textures.
    for (float scale = 1.0; scale <= 4.0; scale *= 2.0) {
        float weight = 1.0 / scale;
        vec2 d = texelSize * scale;

        // Sample the 3x3 neighborhood at the current scale.
        float tl = texture(tex, uv - d).a;
        float tm = texture(tex, uv - vec2(0.0, d.y)).a;
        float tr = texture(tex, uv + vec2(d.x, -d.y)).a;
        float ml = texture(tex, uv - vec2(d.x, 0.0)).a;
        float mr = texture(tex, uv + vec2(d.x, 0.0)).a;
        float bl = texture(tex, uv + vec2(-d.x, d.y)).a;
        float bm = texture(tex, uv + vec2(0.0, d.y)).a;
        float br = texture(tex, uv + d).a;
        
        // Apply the Sobel operator to calculate the gradient for this scale.
        float sobelX = (tr + 2.0 * mr + br) - (tl + 2.0 * ml + bl);
        float sobelY = (bl + 2.0 * bm + br) - (tl + 2.0 * tm + tr);

        gradient += vec2(sobelX, sobelY) * weight;
        totalWeight += weight;
    }
    
    // Normalize the summed gradients.
    // The 0.125 factor is an approximation to normalize the Sobel kernel (1/8).
    return (gradient / totalWeight) * 0.125;
}

vec3 getReconstructedNormal(vec2 p, float thickness) {
    vec2 uv = p / uForegroundSize;
    
    if (texture(uForegroundTexture, uv).a < 0.01) {
        return vec3(0.0, 0.0, 1.0);
    }
    
    // Find the center of the shape
    vec2 shapeCenter = findShapeCenter(uv);
    
    // Calculate direction from center to current point
    vec2 centerToPoint = uv - shapeCenter;
    
    // If we're at the center, default to pointing up
    if (length(centerToPoint) < 0.001) {
        return vec3(0.0, 0.0, 1.0);
    }
    
    // Normalize the direction
    vec2 outwardDirection = normalize(centerToPoint);
    
    // Get blurred alpha to determine curvature strength
    float blurredAlpha = texture(uForegroundBlurredTexture, uv).a;
    float sharpAlpha = texture(uForegroundTexture, uv).a;
    
    // Calculate distance from edge (0 = at edge, 1 = at center)
    float edgeDistance = smoothstep(0.0, 1.0, blurredAlpha);
    
    // At edges, normals should be parallel to xy plane (z approaches 0)
    // At center, normals should point more upward (z approaches 1)
    // Adjust this exponent to decide how gradual this transition should be. Higher values are more abrupt
    float normalExponent = .2;
    float normalZ = pow(edgeDistance, normalExponent);
    
    // Scale xy components to maintain unit length
    float xyScale = sqrt(max(0.0, 1.0 - normalZ * normalZ));
    
    return normalize(vec3(outwardDirection * xyScale, normalZ));
}

vec3 getNormal(vec2 p, float thickness) {
    return getReconstructedNormal(p, thickness);
}

void main() {
    vec2 screenUV = FlutterFragCoord().xy / uSize;

    // Convert screen coordinates to layer-local coordinates
    // Subtract the layer's position on screen to get coordinates relative to the layer
    vec2 layerLocalCoord = FlutterFragCoord().xy - uOffset;
    vec2 layerUV = layerLocalCoord / uForegroundSize;

    // If we are sampling outside of the foreground matte we should just treat the
    // pixel as skipped
    if (layerUV.x < 0.0 || layerUV.x > 1.0 || layerUV.y < 0.0 || layerUV.y > 1.0) {
        fragColor = texture(uBackgroundTexture, screenUV);
        return;
    }

    vec4 foregroundColor = texture(uForegroundTexture, layerUV);
    
    // If the fragment is transparent (based on the sharp alpha), we can skip all calculations.
    if (foregroundColor.a < 0.001) {
        fragColor = texture(uBackgroundTexture, screenUV);
        return;
    }
    
    // Use the same SDF calculation as the normal function for consistency
    vec4 blurred = texture(uForegroundBlurredTexture, layerUV);
    float sd = approximateSDF(blurred.a, uThickness);
    vec3 normal = getNormal(layerLocalCoord, uThickness);
    
    // Use shared rendering pipeline to get the glass color
    fragColor = renderLiquidGlass(
        screenUV, 
        FlutterFragCoord().xy,
        uSize, 
        sd, 
        uThickness, 
        uRefractiveIndex, 
        uChromaticAberration, 
        uGlassColor, 
        uLightAngle, 
        uLightIntensity, 
        uAmbientStrength, 
        uBackgroundTexture, 
        normal,
        foregroundColor.a,
        uGaussianBlur,
        uSaturation,
        uLightness
    );
    
    // Apply debug normals visualization using shared function
    #if DEBUG_NORMALS
        fragColor = debugNormals(fragColor, normal, true);
    #endif

    #if DEBUG_BLUR_MATTE
        fragColor = mix(fragColor, blurred, 0.99);
    #endif
}


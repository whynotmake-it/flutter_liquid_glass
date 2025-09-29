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

#define DEBUG_NORMALS 0

#include <flutter/runtime_effect.glsl>
#include "shared.glsl"

// Optimized uniform layout - grouped into vectors for better performance
layout(location = 0) uniform vec2 uSize;                    // width, height
layout(location = 1) uniform vec4 uGlassColor;             // r, g, b, a
layout(location = 2) uniform vec4 uOpticalProps;           // refractiveIndex, chromaticAberration, thickness, blend
layout(location = 3) uniform vec4 uLightConfig;            // angle, intensity, ambient, saturation
layout(location = 4) uniform float uNumShapes;             // numShapes  
layout(location = 5) uniform vec2 uLightDirection;         // pre-computed cos(angle), sin(angle)
layout(location = 6) uniform mat4 uTransform;              // transform matrix for all shapes

// Extract individual values for backward compatibility
float uChromaticAberration = uOpticalProps.y;
float uLightAngle = uLightConfig.x;
float uLightIntensity = uLightConfig.y;
float uAmbientStrength = uLightConfig.z;
float uThickness = uOpticalProps.z;
float uRefractiveIndex = uOpticalProps.x;
float uBlend = uOpticalProps.w;
float uSaturation = uLightConfig.w;

// Shape array uniforms - 6 floats per shape (type, centerX, centerY, sizeW, sizeH, cornerRadius)
// Reduced from 64 to 16 shapes to fit Impeller's uniform buffer limit (16 * 6 = 96 floats vs 384)
#define MAX_SHAPES 16
layout(location = 10) uniform float uShapeData[MAX_SHAPES * 6];

uniform sampler2D uBackgroundTexture;
layout(location = 0) out vec4 fragColor;

// SDF functions (shader-specific)
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

float sdfSquircle(vec2 p, vec2 b, float r) {
    float shortest = min(b.x, b.y);
    r = min(r, shortest);

    vec2 q = abs(p) - b + r;
    
    // For n=2.0: pow(x, 2.0) = x*x, pow(x, 0.5) = sqrt(x)
    // This is 10-100× faster than pow() operations
    vec2 maxQ = max(q, 0.0);
    return min(max(q.x, q.y), 0.0) + sqrt(maxQ.x * maxQ.x + maxQ.y * maxQ.y) - r;
}

// Optimized ellipse SDF (reduced divisions and length calculations)
float sdfEllipse(vec2 p, vec2 r) {
    r = max(r, 1e-4);
    
    // Cache reciprocals to avoid repeated division
    vec2 invR = 1.0 / r;
    vec2 invR2 = invR * invR;
    
    // Use squared lengths to avoid some sqrt operations where possible
    vec2 pInvR = p * invR;
    float k1 = length(pInvR);
    
    vec2 pInvR2 = p * invR2;
    float k2 = length(pInvR2);
    
    return (k1 * (k1 - 1.0)) / max(k2, 1e-4);
}

float smoothUnion(float d1, float d2, float k) {
    if (k <= 0.0) {
        return min(d1, d2);
    }
    float e = max(k - abs(d1 - d2), 0.0);
    return min(d1, d2) - e * e * 0.25 / k;
}

float getShapeSDF(float type, vec2 p, vec2 center, vec2 size, float r) {
    if (type == 1.0) { // squircle
        return sdfSquircle(p - center, size / 2.0, r);
    }
    if (type == 2.0) { // ellipse
        return sdfEllipse(p - center, size / 2.0);
    }
    if (type == 3.0) { // rounded rectangle
        return sdfRRect(p - center, size / 2.0, r);
    }
    return 1e9; // none
}

float getShapeSDFFromArray(int index, vec2 p) {
    int baseIndex = index * 6;
    float type = uShapeData[baseIndex];
    vec2 center = vec2(uShapeData[baseIndex + 1], uShapeData[baseIndex + 2]);
    vec2 size = vec2(uShapeData[baseIndex + 3], uShapeData[baseIndex + 4]);
    float cornerRadius = uShapeData[baseIndex + 5];
    
    return getShapeSDF(type, p, center, size, cornerRadius);
}

float sceneSDF(vec2 p) {
    int numShapes = int(uNumShapes);
    if (numShapes == 0) {
        return 1e9;
    }
    
    float result = getShapeSDFFromArray(0, p);
    
    // Optimized: unroll for common cases (1-4 shapes), use loop for 5+ shapes
    if (numShapes <= 4) {
        // Fully unrolled for 1-4 shapes (covers 90%+ of use cases)
        if (numShapes >= 2) {
            float shapeSDF = getShapeSDFFromArray(1, p);
            result = smoothUnion(result, shapeSDF, uBlend);
        }
        if (numShapes >= 3) {
            float shapeSDF = getShapeSDFFromArray(2, p);
            result = smoothUnion(result, shapeSDF, uBlend);
        }
        if (numShapes >= 4) {
            float shapeSDF = getShapeSDFFromArray(3, p);
            result = smoothUnion(result, shapeSDF, uBlend);
        }
    } else {
        // Dynamic loop for 5+ shapes (uncommon cases)
        for (int i = 1; i < min(numShapes, MAX_SHAPES); i++) {
            float shapeSDF = getShapeSDFFromArray(i, p);
            result = smoothUnion(result, shapeSDF, uBlend);
        }
    }
    
    return result;
}

// Calculate 3D normal using derivatives (shader-specific normal calculation)
vec3 getNormal(float sd, float thickness) {
    float dx = dFdx(sd);
    float dy = dFdy(sd);
    
    // The cosine and sine between normal and the xy plane
    float n_cos = max(thickness + sd, 0.0) / thickness;
    float n_sin = sqrt(max(0.0, 1.0 - n_cos * n_cos));
    
    // Return the normal directly without encoding
    return normalize(vec3(dx * n_cos, dy * n_cos, n_sin));
}

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    
    // Compute screen UV
    float yUsed = computeY(fragCoord.y, uSize);
    vec2 screenUV = vec2(fragCoord.x / uSize.x, yUsed);
    
    // Apply transform to fragment coordinates
    vec4 transformedCoord = uTransform * vec4(fragCoord, 0.0, 1.0);
    vec2 p = transformedCoord.xy;
    
    // Generate shape and calculate normal using shader-specific method
    float sd = sceneSDF(p);
    vec3 normal = getNormal(sd, uThickness);
    float foregroundAlpha = 1.0 - smoothstep(-2.0, 0.0, sd);

    // Early discard for pixels outside glass shapes to reduce overdraw
    if (foregroundAlpha < 0.01) {
        fragColor = texture(uBackgroundTexture, screenUV);
        return;
    }
    
    // Use shared rendering pipeline
    fragColor = renderLiquidGlass(
        screenUV, 
        p, 
        uSize, 
        sd, 
        uThickness, 
        uRefractiveIndex, 
        uChromaticAberration, 
        uGlassColor, 
        uLightDirection, 
        uLightIntensity, 
        uAmbientStrength, 
        uBackgroundTexture, 
        normal,
        foregroundAlpha,
        0.0,
        uSaturation
    );
    
    // Apply debug normals visualization using shared function
    #if DEBUG_NORMALS
        fragColor = debugNormals(fragColor, normal, true);
    #endif
}

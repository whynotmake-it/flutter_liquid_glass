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
    vec2 screenUV = FlutterFragCoord().xy / uSize;
    vec2 p = FlutterFragCoord().xy;
    
    // Generate shape and calculate normal using shader-specific method
    float sd = sceneSDF(p);
    vec3 normal = getNormal(sd, uThickness);
    float foregroundAlpha = 1.0 - smoothstep(-2.0, 0.0, sd);

    if (foregroundAlpha < 0.01) {
        discard;
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
        uLightAngle, 
        uLightIntensity, 
        uAmbientStrength, 
        uBackgroundTexture, 
        normal,
        foregroundAlpha,
        0.0
    );
    
    // Apply debug normals visualization using shared function
    #if DEBUG_NORMALS
        fragColor = debugNormals(fragColor, normal, true);
    #endif
}

#version 320 es
precision highp float;

#include <flutter/runtime_effect.glsl>

layout(location = 0) uniform vec2 uSize;

layout(location = 1) uniform vec2 squircle1Center;
layout(location = 2) uniform vec2 squircle1Size;
layout(location = 3) uniform float squircle1CornerRadius;

layout(location = 4) uniform vec2 squircle2Center;
layout(location = 5) uniform vec2 squircle2Size;
layout(location = 6) uniform float squircle2CornerRadius;

layout(location = 7) uniform float uBlend;
layout(location = 8) uniform float uThickness;

layout(location = 0) out vec4 fragColor;

#define ENCODING_SCALE 0.01

mat2 rotate2d(float angle) {
    return mat2(cos(angle), -sin(angle), sin(angle), cos(angle));
}

float sdfRRect( in vec2 p, in vec2 b, in float r ) {
    vec2 q = abs(p)-b+r;
    return min(max(q.x,q.y),0.0) + length(max(q,0.0)) - r;
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

float sceneSDF(vec2 p) {
    float d1 = sdfRRect(p - squircle1Center, squircle1Size, squircle1CornerRadius);
    float d2 = sdfRRect(p - squircle2Center, squircle2Size, squircle2CornerRadius);
    return smoothUnion(d1, d2, uBlend);
}

// Calculate 3D normal using derivatives like the reference shader
vec3 getNormal(float sd, float thickness) {
    float dx = dFdx(sd);
    float dy = dFdy(sd);
    
    // The cosine and sine between normal and the xy plane
    float n_cos = max(thickness + sd, 0.0) / thickness;
    float n_sin = sqrt(max(0.0, 1.0 - n_cos * n_cos));
    
    return normalize(vec3(dx * n_cos, dy * n_cos, n_sin));
}

// Calculate height/depth of the liquid surface - same as reference
float getHeight(float sd, float thickness) {
    if (sd >= 0.0) {
        return 0.0;
    }
    if (sd < -thickness) {
        return thickness;
    }
    
    float x = thickness + sd;
    return sqrt(max(0.0, thickness * thickness - x * x));
}

void main() {
    vec2 p = FlutterFragCoord().xy;
    float sd = sceneSDF(p);

    // Background pass-through with anti-aliasing like reference
    float alpha = smoothstep(-4.0, 0.0, sd);
    
    if (alpha < 1.0) {
        float refractiveIndex = 1.5;
        float baseHeight = uThickness * 8.0;
        
        vec3 normal = getNormal(sd, uThickness);
        
        // Calculate refraction using same method as reference
        vec3 incident = vec3(0.0, 0.0, -1.0);
        vec3 refractVec = refract(incident, normal, 1.0 / refractiveIndex);
        
        float h = getHeight(sd, uThickness);
        float refractLength = (h + baseHeight) / max(0.001, dot(vec3(0.0, 0.0, -1.0), refractVec));
        
        // Calculate the 2D refraction displacement
        vec2 refractionDisplacement = refractVec.xy * refractLength;
        
        vec2 scaledDisplacement = refractionDisplacement * ENCODING_SCALE;
        
        // Encode displacement values to 0-1 range (from approximately -1 to 1)
        vec2 encodedDisplacement = scaledDisplacement * 0.5 + 0.5;
        
        // Encode displacement in red and green channels, normal.z in blue for reflection
        fragColor = vec4(encodedDisplacement.x, encodedDisplacement.y, normal.z, 1.0 - alpha);
    } else {
        discard;
    }
}

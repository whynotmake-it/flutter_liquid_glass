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

layout(location = 0) out vec4 fragColor;

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

// Calculate 3D normal with thickness consideration
vec3 get3DNormal(float sd, vec2 p, float thickness) {
    vec2 eps = vec2(1.0, 0.0);
    float dx = sceneSDF(p + eps.xy) - sceneSDF(p - eps.xy);
    float dy = sceneSDF(p + eps.yx) - sceneSDF(p - eps.yx);
    
    // The cosine and sine between normal and the xy plane
    float n_cos = max(thickness + sd, 0.0) / thickness;
    float n_sin = sqrt(max(0.0, 1.0 - n_cos * n_cos));
    
    return normalize(vec3(dx * n_cos, dy * n_cos, n_sin));
}

// Calculate height/depth of the liquid surface
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
    float d = sceneSDF(p);

    float alpha = 1.0 - smoothstep(0.0, 1.0, d);

    if (alpha > 0.0) {
        float thickness = 40.0;
        float refractiveIndex = 1.4;
        float baseHeight = thickness * 4.0;
        
        vec3 normal = get3DNormal(d, p, thickness);
        
        // Calculate refraction using proper 3D ray tracing
        vec3 incident = vec3(0.0, 0.0, -1.0);
        vec3 refractVec = refract(incident, normal, 1.0 / refractiveIndex);
        
        float h = getHeight(d, thickness);
        float refractLength = (h + baseHeight) / max(0.001, dot(vec3(0.0, 0.0, -1.0), refractVec));
        
        // Calculate the 2D refraction displacement
        vec2 refractionDisplacement = refractVec.xy * refractLength * 0.02; // Scale factor for displacement strength
        
        vec2 encodedRefraction = refractionDisplacement * 0.5 + 0.5;

        fragColor = vec4(encodedRefraction.x, 0, encodedRefraction.y, alpha);
    } else {
        discard;
    }
}

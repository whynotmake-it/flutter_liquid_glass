// Copyright 2025, Tim Lehmann for whynotmake.it
//
// Alternative liquid glass shader with different normal calculation approach
// This demonstrates how the shared rendering pipeline makes it easy to create variants

#version 320 es
precision mediump float;

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


uniform sampler2D uBackgroundTexture;
uniform sampler2D uForegroundTexture;
uniform sampler2D uForegroundBlurredTexture;
layout(location = 0) out vec4 fragColor;

// Convert blurred alpha to approximate SDF that matches real SDF behavior
float approximateSDF(float blurredAlpha, float thickness) {
    // Convert alpha (0=edge, 1=center) to SDF-like values (0=edge, -thickness=center)
    // This matches how real SDFs work: negative inside, zero at edge
    float normalizedDistance = smoothstep(0.0, 1.0, blurredAlpha);
    return -normalizedDistance * thickness;
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

// Sharp-edge normal calculation with subsampling for improved quality.
vec3 getNormal(vec2 p, float thickness) {
    vec2 uv = p / uForegroundSize;
    vec2 texelSize = 1.0 / uForegroundSize;

    // Early exit for fragments outside the shape.
    if (texture(uForegroundTexture, uv).a < 0.01) {
        return vec3(0.0, 0.0, 1.0);
    }

    // Get distance from edge using blurred texture.
    float blurredAlpha = texture(uForegroundBlurredTexture, uv).a;
    float sdf = approximateSDF(blurredAlpha, thickness); // 0 at edge, -thickness in center

    // Calculate gradients from both sharp and blurred textures using the robust Sobel operator.
    // The sharp gradient gives accurate edge direction, while the blurred one provides smooth inner normals.
    vec2 grad_sharp = calculateGradient(uForegroundTexture, uv, texelSize);
    vec2 grad_blur = calculateGradient(uForegroundBlurredTexture, uv, texelSize);

    // Blend between the two gradients. At the very edge (sdf near 0), we rely on the sharp gradient.
    // As we move inwards (sdf becomes negative), we transition to the smoother, blurred gradient.
    // The smoothstep range (-thickness * 0.2) is a tweakable parameter for controlling the blend.
    float edgeProximity = smoothstep(0.0, -thickness * 0.2, sdf);
    vec2 blended_grad = mix(grad_sharp, grad_blur, edgeProximity);

    // If gradient is zero, normal is straight up.
    if (length(blended_grad) < 0.0001) {
        return vec3(0.0, 0.0, 1.0);
    }

    // The gradient points inward (towards higher alpha). We need it to point outward.
    vec2 outward_dir = -normalize(blended_grad);

    // Model the surface profile. We want the surface to be steep at the edges
    // and flat in the center, like a liquid drop, to produce strong edge highlights.
    // We can model the angle of the normal with the Z-axis (theta).
    float t = -sdf / max(thickness, 0.001); // t is 0 at edge, 1 in center

    // A cosine-based profile gives this effect.
    // cos(t * PI/2) is 1 at t=0 (edge) and 0 at t=1 (center).
    // This makes the surface steepest at the edge.
    float slope = cos(t * 1.57079632679); // PI/2

    // The maximum slope angle at the edge of the shape (the "contact angle").
    // Controls how "bubbly" the glass is. A larger angle makes the sides steeper.
    // Let's use 60 degrees.
    float max_angle = 3.14159265359 / 3.0;
    float theta = slope * max_angle;

    // Construct the normal from the angle and the outward direction.
    float n_z = cos(theta);
    float n_xy_magnitude = sin(theta);

    return vec3(outward_dir.x * n_xy_magnitude, outward_dir.y * n_xy_magnitude, n_z);
}

void main() {
    vec2 screenUV = FlutterFragCoord().xy / uSize;

    // Convert screen coordinates to layer-local coordinates
    // Subtract the layer's position on screen to get coordinates relative to the layer
    vec2 layerLocalCoord = FlutterFragCoord().xy - uOffset;
    vec2 layerUV = layerLocalCoord / uForegroundSize;

    vec4 foregroundColor = texture(uForegroundTexture, layerUV);
    
    // If the fragment is transparent (based on the sharp alpha), we can skip all calculations.
    if (foregroundColor.a == 0.0) {
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
        normal
    );

    // fragColor = mix(texture(uBackgroundTexture, screenUV), blurred, 0.5);
}


// Copyright 2025, Tim Lehmann for whynotmake.it
//
// Final rendering pass for liquid glass with iridescence (soap bubble effect)
// This shader reads displacement data from a pre-computed texture and applies
// the liquid glass effect with thin-film interference for iridescent colors

#version 460 core
precision mediump float;

#define DEBUG_GEOMETRY 0

#include <flutter/runtime_effect.glsl>
#include "displacement_encoding.glsl"
#include "render.glsl"

uniform vec2 uSize;
uniform vec2 uGeometryOffset;
uniform vec2 uGeometrySize;

uniform vec4 uGlassColor;
uniform vec3 uOpticalProps;
uniform vec3 uLightConfig;
uniform vec2 uLightDirection;
uniform float uTime;

// Iridescence controls
uniform float uIridescence; // x: intensity (0-1), y: film thickness multiplier

float uRefractiveIndex = uOpticalProps.x;
float uChromaticAberration = uOpticalProps.y;
float uThickness = uOpticalProps.z;
float uLightIntensity = uLightConfig.x;
float uAmbientStrength = uLightConfig.y;
float uSaturation = uLightConfig.z;

uniform sampler2D uBackgroundTexture;
uniform sampler2D uGeometryTexture;

layout(location = 0) out vec4 fragColor;

// 3D Random
float random (in vec3 st) {
    return fract(sin(dot(st.xyz,
                         vec3(12.9898,78.233,45.543)))
                 * 43758.5453123);
}

// 3D Noise based on Morgan McGuire @morgan3d
// https://www.shadertoy.com/view/4dS3Wd
float noise (in vec3 st) {
    vec3 i = floor(st);
    vec3 f = fract(st);

    // Eight corners of a cube
    float a = random(i);
    float b = random(i + vec3(1.0, 0.0, 0.0));
    float c = random(i + vec3(0.0, 1.0, 0.0));
    float d = random(i + vec3(1.0, 1.0, 0.0));
    float e = random(i + vec3(0.0, 0.0, 1.0));
    float f_ = random(i + vec3(1.0, 0.0, 1.0));
    float g = random(i + vec3(0.0, 1.0, 1.0));
    float h = random(i + vec3(1.0, 1.0, 1.0));

    // Smooth Interpolation
    vec3 u = f*f*(3.0-2.0*f);

    // Mix 8 corners percentages
    return mix(mix(mix( a, b, u.x),
                   mix( c, d, u.x), u.y),
               mix(mix( e, f_, u.x),
                   mix( g, h, u.x), u.y), u.z);
}

// Simulate thin-film interference for iridescence
// Uses a more advanced noise function to create large, swirling patterns.
vec3 calculateIridescence(vec2 screenUV, float height, float intensity) {
    if (intensity < 0.01) {
        return vec3(1.0);
    }

    // Use a much larger scale for the noise to create broad swirls
    vec3 p = vec3(screenUV * 0.2, uTime * 0.1);

    // Use noise to distort the UV coordinates, creating a swirling effect
    float n = noise(p * 10);
    vec3 q = vec3(n, n, n);
    vec3 r = vec3(noise(p + q * 0.5), noise(p - q * 0.5), noise(p));

    // Combine multiple layers of noise (FBM) for more detail
    float f = noise(p + r * 2.0);

    // Modulate the hue based on the final noise value and height
    float hue = fract(f * 2.0 + height * 1.5);

    // Use a color palette that feels more like a soap bubble (cyan, magenta, yellow shifts)
    vec3 color = vec3(
        sin(hue * 6.28318 + 0.0) * 0.5 + 0.5,
        sin(hue * 6.28318 + 2.09439) * 0.5 + 0.5, // 2*PI/3
        sin(hue * 6.28318 + 4.18879) * 0.5 + 0.5  // 4*PI/3
    );

    // Soften the colors for a more pastel, pearlescent look
    color = normalize(color) * 0.8 + 0.2;
    
    // Mix with white for a pastel, pearlescent look
    vec3 iridescentColor = mix(vec3(1.0), color, 0.9);

    // Blend with white based on intensity
    return mix(vec3(1.0), iridescentColor, intensity);
}

void main() {
    // FlutterFragCoord() returns logical pixels, but our geometry texture is in physical pixels
    // So we need to scale by devicePixelRatio to work in physical pixel space
    vec2 fragCoord = FlutterFragCoord().xy;

    vec2 screenUV = vec2(fragCoord.x / uSize.x, fragCoord.y / uSize.y);

    #ifdef IMPELLER_TARGET_OPENGLES
        screenUV.y = 1.0 - screenUV.y;
    #endif

    vec2 geometryUV = (fragCoord - uGeometryOffset) / uGeometrySize;
    #ifdef IMPELLER_TARGET_OPENGLES
        geometryUV.y = 1.0 - geometryUV.y;
    #endif

    vec4 geometryData = texture(uGeometryTexture, geometryUV);

    #if DEBUG_GEOMETRY
        fragColor = geometryData;
        return;
    #endif

    if (geometryData.a < 0.01) {
        fragColor = vec4(0);
        return;
    }

    float maxDisplacement = uThickness * 10.0;
    vec2 displacement = decodeDisplacement(geometryData, maxDisplacement);

    vec2 invUSize = 1.0 / uSize;

    vec4 refractColor;
    if (uChromaticAberration < 0.01) {
        vec2 refractedUV = screenUV + displacement * invUSize;
        refractColor = texture(uBackgroundTexture, refractedUV);
    } else {
        float dispersionStrength = uChromaticAberration * 0.5;
        vec2 redOffset = displacement * (1.0 + dispersionStrength);
        vec2 blueOffset = displacement * (1.0 - dispersionStrength);

        vec2 redUV = screenUV + redOffset * invUSize;
        vec2 greenUV = screenUV + displacement * invUSize;
        vec2 blueUV = screenUV + blueOffset * invUSize;

        float red = texture(uBackgroundTexture, redUV).r;
        vec4 greenSample = texture(uBackgroundTexture, greenUV);
        float blue = texture(uBackgroundTexture, blueUV).b;

        refractColor = vec4(red, greenSample.g, blue, greenSample.a);
    }

    vec4 finalColor = applyGlassColor(refractColor, uGlassColor);
    finalColor.rgb = applySaturation(finalColor.rgb, uSaturation);

    // Compute edge lighting
    float normalizedHeight = geometryData.b;

    float thicknessScale = clamp(40.0 / max(uThickness, 1.0), 1.0, 4.0);
    float edgeThreshold = mix(0.8, 0.5, 1.0 / thicknessScale);
    float edgeFactor = 1.0 - smoothstep(0.0, edgeThreshold, normalizedHeight);

    vec2 normalXY = vec2(0.0);
    if (length(displacement) > 0.01) {
        normalXY = normalize(displacement);
    }

    // Calculate iridescence based on surface properties
    vec3 iridescentTint = calculateIridescence(screenUV, normalizedHeight, uIridescence);

    // Apply iridescence to the entire surface
    // More visible on edges where the angle changes more
    float iridescenceFactor = mix(0.3, 1.0, edgeFactor);
    finalColor.rgb *= mix(vec3(1.0), iridescentTint, iridescenceFactor * uIridescence);

    if (edgeFactor > 0.01) {
        float mainLight = max(0.0, dot(normalXY, uLightDirection));
        float oppositeLight = max(0.0, dot(normalXY, -uLightDirection));

        float totalInfluence = mainLight + oppositeLight * 0.8;

        float directional = pow(totalInfluence, 1.5) * uLightIntensity * 3.0;
        float ambient = uAmbientStrength * 0.5;

        float brightness = (directional + ambient) * edgeFactor * thicknessScale * 0.8;

        vec3 bgColor = refractColor.rgb;
        float bgLuminance = dot(bgColor, LUMA_WEIGHTS);
        vec3 highlightColor;

        vec3 saturatedBg = bgColor / max(bgLuminance, 0.001);
        saturatedBg = mix(bgColor, saturatedBg, 0.8);
        float colorfulness = length(bgColor - vec3(bgLuminance));
        float colorMix = clamp(colorfulness * 1.0 + 0.5, 0.5, 1.0);
        highlightColor = mix(vec3(1.0), saturatedBg, colorMix);

        // Tint highlights with iridescence
        highlightColor *= iridescentTint;

        finalColor.rgb = mix(finalColor.rgb, highlightColor, brightness);
    }

    float alpha = geometryData.a;
    fragColor = vec4(finalColor.rgb * alpha, alpha);
}

// Copyright 2025, Tim Lehmann for whynotmake.it
//
// This shader is based on a bunch of sources:
// - https://www.shadertoy.com/view/wccSDf for the refraction
// - https://iquilezles.org/articles/distfunctions2d/ for SDFs
// - Gracious help from @dkwingsmt for the Squircle SDF
//
// Feel free to use this shader in your own projects, it'd be lovely if you could
// give some credit like I did here.

#version 460 core
precision mediump float;

#define DEBUG_NORMALS 0

#include <flutter/runtime_effect.glsl>
#include "shared.glsl"
#include "sdf.glsl"

// Optimized uniform layout - grouped into vectors for better performance
layout(location = 0) uniform vec2 uSize;                    // width, height
layout(location = 1) uniform vec4 uGlassColor;             // r, g, b, a
layout(location = 2) uniform vec4 uOpticalProps;           // refractiveIndex, chromaticAberration, thickness, blend
layout(location = 3) uniform vec4 uLightConfig;            // angle, intensity, ambient, saturation
layout(location = 4) uniform vec2 uLightDirection;         // pre-computed cos(angle), sin(angle)

// Extract individual values for backward compatibility
float uChromaticAberration = uOpticalProps.y;
float uLightAngle = uLightConfig.x;
float uLightIntensity = uLightConfig.y;
float uAmbientStrength = uLightConfig.z;
float uThickness = uOpticalProps.z;
float uRefractiveIndex = uOpticalProps.x;
float uBlend = uOpticalProps.w;
float uSaturation = uLightConfig.w;

layout(location = 5) uniform float uNumShapes;             // numShapes  
layout(location = 6) uniform float uShapeData[MAX_SHAPES * 6];

uniform sampler2D uBlurredTexture;
layout(location = 0) out vec4 fragColor;

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
     
    // We invert screenUV Y on OpenGL to sample the textures correctly
    // fragCoord stays the same so shape positions are correct.
    #ifdef IMPELLER_TARGET_OPENGLES
        vec2 screenUV = vec2(fragCoord.x / uSize.x, 1.0 - (fragCoord.y / uSize.y));
    #else
        vec2 screenUV = vec2(fragCoord.x / uSize.x, fragCoord.y / uSize.y);
    #endif
    
    // Generate shape and calculate normal using shader-specific method
    float sd = sceneSDF(fragCoord, int(uNumShapes), uShapeData, uBlend);
    float foregroundAlpha = 1.0 - smoothstep(-2.0, 0.0, sd);

    // Early discard for pixels outside glass shapes to reduce overdraw
    if (foregroundAlpha < 0.01) {
        // Outside we sample the background texture
        fragColor = vec4(0, 0, 0, 0);
        return;
    }

    vec3 normal = getNormal(sd, uThickness);
    
    // Use shared rendering pipeline
    fragColor = renderLiquidGlass(
        screenUV, 
        fragCoord, 
        uSize, 
        sd, 
        uThickness, 
        uRefractiveIndex, 
        uChromaticAberration, 
        uGlassColor, 
        uLightDirection, 
        uLightIntensity, 
        uAmbientStrength, 
        uBlurredTexture, 
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

#version 320 es
precision highp float;

#include <flutter/runtime_effect.glsl>

layout(location = 0) uniform sampler2D uBackgroundTexture;
layout(location = 1) uniform sampler2D uDisplacementTexture;
layout(location = 2) uniform vec2 uSize;

layout(location = 0) out vec4 fragColor;

// The threshold for the alpha channel to create the "merged" effect
const float threshold = 0.7;


void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;


    vec2 displacementMap = texture(uDisplacementTexture, uv).rb;

    if (displacementMap == vec2(0.0, 0.0)) {
        discard;
    }

    vec2 displacementOffset = displacementMap - 0.5;

    vec2 translatedUv = uv + displacementOffset;

    vec4 originalColor = texture(uBackgroundTexture, translatedUv);

    // Use smoothstep to create a sharp falloff on the blurred alpha.
    // This is what creates the "merged" effect.
    float newAlpha = smoothstep(threshold, threshold + 0.01, originalColor.a);

    // The final color is the original color with the new alpha.
    fragColor = vec4(originalColor.rgb, newAlpha);
}

#version 300 es
precision mediump float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform sampler2D uBackgroundTexture;

// The threshold for the alpha channel to create the "merged" effect
const float threshold = 0.7;

out vec4 fragColor;

void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;

    // Get the original color from the pre-blurred texture.
    vec4 originalColor = texture(uBackgroundTexture, uv);

    // Use smoothstep to create a sharp falloff on the blurred alpha.
    // This is what creates the "merged" effect.
    float newAlpha = smoothstep(threshold, threshold + 0.01, originalColor.a);

    // The final color is the original color with the new alpha.
    fragColor = originalColor;
}

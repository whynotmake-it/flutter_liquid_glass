#version 460 core
precision mediump float;

#include <flutter/runtime_effect.glsl>

// The input image to blur.
uniform sampler2D uTexture;

// Resolution of the texture (width, height).
uniform vec2 uResolution;

// Maximum blur radius in pixels.
uniform float uMaxBlurRadius;

// Blur direction flag: 1.0 for horizontal pass, 0.0 for vertical pass.
// This shader is designed for two-pass separated Gaussian blur.
uniform float uHorizontal;

// The widget's bounding box in physical screen pixels:
//   uRect.xy = top-left origin (x, y)
//   uRect.zw = size (width, height)
// Used to convert screen-space fragment coordinates to local 0..1 UVs
// for the progressive gradient.
uniform vec4 uRect;

// Progressive blur parameters (in local widget space, 0..1):
//   uProgressive.xy = gradient start position
//   uProgressive.zw = gradient end position
uniform vec4 uProgressive;

// Intensity at start and end of the gradient (0..1).
//   uIntensity.x = startIntensity
//   uIntensity.y = endIntensity
uniform vec2 uIntensity;

out vec4 fragColor;

// Maximum kernel radius we support (must be a compile-time constant for the loop).
const float kMaxRadius = 128.0;

// Compute the blur intensity at this fragment based on the progressive gradient.
// localUV is in widget-local space (0..1).
// Returns a value in [0, 1] that scales the blur radius.
float progressiveIntensity(vec2 localUV) {
    vec2 gradStart = uProgressive.xy;
    vec2 gradEnd = uProgressive.zw;

    vec2 gradDir = gradEnd - gradStart;
    float gradLength = length(gradDir);

    // If start == end, return uniform intensity (the average).
    if (gradLength < 0.001) {
        return mix(uIntensity.x, uIntensity.y, 0.5);
    }

    // Project the current UV onto the gradient line to get a 0..1 parameter.
    float t = dot(localUV - gradStart, gradDir) / (gradLength * gradLength);
    t = clamp(t, 0.0, 1.0);

    // Apply an ease-in curve (quadratic) matching Haze's default EaseIn easing.
    t = t * t;

    return mix(uIntensity.x, uIntensity.y, t);
}

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;

    // Screen-space UV for texture sampling.
    vec2 uv = fragCoord / uResolution;

    // Widget-local UV for progressive gradient evaluation.
    vec2 localUV = (fragCoord - uRect.xy) / uRect.zw;

    // Determine the local blur intensity from the progressive gradient.
    float intensity = progressiveIntensity(localUV);

    // Scale the blur radius by the intensity.
    float blurRadius = uMaxBlurRadius * intensity;

    // Clamp to our max supported radius.
    blurRadius = min(blurRadius, kMaxRadius);

    // For very small radii, just return the original texel.
    if (blurRadius < 0.5) {
        fragColor = texture(uTexture, uv);
        return;
    }

    // Sigma for the Gaussian kernel: radius / 2 is a good balance (matches Haze).
    float sigma = max(blurRadius / 2.0, 1.0);

    // The step size in UV space for one pixel in the blur direction.
    vec2 texelStep = vec2(uHorizontal, 1.0 - uHorizontal) / uResolution;

    // Truncate to integer radius for the loop bound.
    float r = floor(blurRadius);

    // --- Iterative Gaussian weights ---
    // G(n) = exp(-n^2 / (2*sigma^2)). Instead of calling exp() per iteration,
    // we use the recurrence: G(n) = G(n-1) * stepFactor, where
    // stepFactor advances by a^2 each step (a = exp(-1/(2*sigma^2))).
    // This reduces 128 exp() calls to exactly 1.
    float a = exp(-0.5 / (sigma * sigma));  // base decay: exp(-1/(2*sigma^2))
    float a2 = a * a;                        // a^2, constant multiplier for stepFactor

    // Accumulate center pixel (G(0) = 1.0).
    float weightSum = 1.0;
    vec4 result = texture(uTexture, uv);

    // Iterative weight state:
    //   wPrev tracks G(i) at the start of each paired iteration (i = 1, 3, 5, ...).
    //   stepFactor tracks a^(2n-1), the ratio G(n)/G(n-1).
    //
    // Initialization for i=1:
    //   G(1) = a^1 = a
    //   stepFactor starts as a^3 (the ratio G(2)/G(1) = a^(2*2-1) = a^3)
    float wL = a;                   // G(1)
    float stepFactor = a2 * a;      // a^3, to compute G(2) from G(1)

    // Optimized sampling: sample pairs of pixels at once using linear filtering.
    // For each pair at offsets [i] and [i+1], we sample once at the weighted
    // midpoint. This halves the number of texture fetches.
    for (float i = 1.0; i < kMaxRadius; i += 2.0) {
        if (i >= r) { break; }

        // wL = G(i), computed iteratively from previous iteration.
        float wH = wL * stepFactor;   // G(i+1) = G(i) * a^(2(i+1)-1)
        float w = wL + wH;

        // Offset biased toward the heavier weight.
        float offset = i + wH / w;
        vec2 uvOffset = offset * texelStep;

        // Sample in both directions. Use branchless step() masks to exclude
        // out-of-bounds samples without divergent branching. The clamp ensures
        // we always sample a valid texel (the mask zeros out its contribution).
        vec2 uvMinus = uv - uvOffset;
        vec2 uvPlus  = uv + uvOffset;

        float maskMinus = step(0.0, uvMinus.x) * step(uvMinus.x, 1.0)
                        * step(0.0, uvMinus.y) * step(uvMinus.y, 1.0);
        float maskPlus  = step(0.0, uvPlus.x)  * step(uvPlus.x, 1.0)
                        * step(0.0, uvPlus.y)  * step(uvPlus.y, 1.0);

        // Clamp UVs so the texture fetch is always valid (mask zeros the result
        // when out of bounds, so the clamped value doesn't matter).
        result += w * maskMinus * texture(uTexture, clamp(uvMinus, 0.0, 1.0));
        result += w * maskPlus  * texture(uTexture, clamp(uvPlus,  0.0, 1.0));
        weightSum += w * (maskMinus + maskPlus);

        // Advance iterative weights for next pair (i+2, i+3):
        //   G(i+2) = G(i+1) * a^(2(i+2)-1)
        //   But stepFactor currently = a^(2(i+1)-1), so we need a^(2(i+2)-1) = stepFactor * a^2
        stepFactor *= a2;
        wL = wH * stepFactor;  // G(i+2)
        //   Advance stepFactor again for the next wH: a^(2(i+3)-1) = stepFactor * a^2
        stepFactor *= a2;
    }

    // Handle the last odd-radius sample if needed.
    // Use float bit trick: if r is odd, fract(r * 0.5) = 0.5.
    if (r < kMaxRadius && fract(r * 0.5) > 0.25) {
        // wL already holds G(r) from the iterative computation (since the loop
        // exited with wL ready for the next odd index, which is r).
        float w = wL;
        vec2 uvOffset = r * texelStep;

        vec2 uvMinus = uv - uvOffset;
        vec2 uvPlus  = uv + uvOffset;

        float maskMinus = step(0.0, uvMinus.x) * step(uvMinus.x, 1.0)
                        * step(0.0, uvMinus.y) * step(uvMinus.y, 1.0);
        float maskPlus  = step(0.0, uvPlus.x)  * step(uvPlus.x, 1.0)
                        * step(0.0, uvPlus.y)  * step(uvPlus.y, 1.0);

        result += w * maskMinus * texture(uTexture, clamp(uvMinus, 0.0, 1.0));
        result += w * maskPlus  * texture(uTexture, clamp(uvPlus,  0.0, 1.0));
        weightSum += w * (maskMinus + maskPlus);
    }

    fragColor = result / weightSum;
}

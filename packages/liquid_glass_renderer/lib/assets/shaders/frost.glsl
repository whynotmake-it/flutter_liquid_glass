#include "shader_constants.glsl"

// Which way the fragment at [fragment] mirrors its taps along each axis.
vec2 frostMirror(vec2 fragment) {
    return step(0.5, fract(fragment * 0.5)) * 2.0 - 1.0;
}

// A Gaussian frost of [copy] around [uv] by [sigma] texels: 12 bilinear taps
// importance-sampled from the Gaussian on a golden-angle spiral, equal
// weights, each clamped to [lo, hi] in uv. It stands in for a copy's blur
// passes, over a copy taken unblurred. [invSize] is one texel in uv.
//
// Each pixel of a 2 x 2 cell at [fragment] starts the spiral a quarter turn on
// from the last, so a hard edge shows as a faint dither in place of faint
// copies; a constant [fragment] gives up the dither for the registers it holds.
//
// [sigma] must be positive. The loop runs to a bound read from it, 12 for
// any positive [sigma]: unrolled, the reads are all kept in flight and double
// a shader's registers on the Mali-G78, halving its occupancy. In the loop
// each read waits for the last, so the count is what it costs: 12 against 24
// takes 0.34 to 0.47 ms of GPU time per frame from a Pixel 6a's chrome.
vec4 frostTaps(
    sampler2D copy,
    highp vec2 uv,
    float sigma,
    highp vec2 invSize,
    highp vec2 lo,
    highp vec2 hi,
    vec2 fragment
) {
    vec4 frost = vec4(0.0);
    vec2 cell = frostMirror(fragment);
    vec2 direction = 0.5 * cell.x * vec2(1.0 + cell.y, 1.0 - cell.y);
    int taps = FROST_SPIRAL_TAPS - int(min(sigma, 0.0));
    for (int i = 0; i < taps; i++) {
        float u = (float(i) + 0.5) / float(FROST_SPIRAL_TAPS);
        float r = sigma * sqrt(-2.0 * log(1.0 - u));
        frost += texture(copy, clamp(uv + direction * r * invSize, lo, hi));
        // Turns by the golden angle, 2.39996323 rad.
        direction = vec2(
            -0.73736888 * direction.x - 0.67549029 * direction.y,
            0.67549029 * direction.x - 0.73736888 * direction.y
        );
    }
    return frost / float(FROST_SPIRAL_TAPS);
}

#define FROST_TAP(x, y) \
    frost += texture(copy, clamp(uv + vec2(x, y) * reach, lo, hi));

// [invSize] carries [frostMirror]'s sign per axis. Each pixel of a 2 x 2 cell
// reads the taps mirrored its own way, four times as many positions over the
// cell, so a hard edge shows as a faint dither in place of faint copies.
vec4 frostEight(
    sampler2D copy,
    highp vec2 uv,
    float sigma,
    highp vec2 invSize,
    highp vec2 lo,
    highp vec2 hi
) {
    highp vec2 reach = sigma * invSize;
    vec4 frost = vec4(0.0);
    FROST_EIGHT_TAPS(FROST_TAP)
    return frost * 0.125;
}

vec4 frostSixteen(
    sampler2D copy,
    highp vec2 uv,
    float sigma,
    highp vec2 invSize,
    highp vec2 lo,
    highp vec2 hi
) {
    highp vec2 reach = sigma * invSize;
    vec4 frost = vec4(0.0);
    FROST_SIXTEEN_TAPS(FROST_TAP)
    return frost * 0.0625;
}

// How much of a frost shows a share [t] of the way from where it is gone
// (0) to where it is whole (1): a smootherstep, so neither end shows as a
// line.
float frostEase(float t) {
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

// How much of a frost shows at [row], between the row where it is whole
// and the row where it is gone: every way a soft scroll edge is drawn
// dissolves its frost by this.
float frostDissolve(highp float row, highp float whole, highp float gone) {
    return frostEase(clamp((row - gone) / (whole - gone), 0.0, 1.0));
}

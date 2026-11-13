#version 460 core

// One axis of the frost drawn into a copy at the copy's own pixels: the
// image filter of a layer that holds the copy from its top-left corner, so
// every fragment lies on the center of a pixel of the copy. Two of these in
// a row, along x and then along y, draw what backdrop_frost.frag draws there
// in one pass: its weights are a product of the axes', so 2 N reads stand
// for N * N. On a pixel's center the weights are the same for every
// fragment, so they come worked out (latticeTaps in backdrop_rig.dart) and
// the program is its reads.

#include <flutter/runtime_effect.glsl>

// The copy's texture size in pixels; an image filter's engine sets it.
uniform vec2 uSize;
// The rect of the copy in the image, in its pixels, inset by half a pixel.
uniform vec4 uBounds;
// The axis frosted: (1, 0) or (0, 1).
uniform vec2 uAxis;
// Where the reads lie along the axis, in pixels from the fragment, and
// their weights, which add up to one; a read not taken weighs nothing.
uniform vec4 uOffsets[2];
uniform vec4 uWeights[2];

uniform sampler2D uCopy;

out vec4 fragColor;

void main() {
    highp vec2 invSize = 1.0 / uSize;
    highp vec2 uv = FlutterFragCoord().xy * invSize;
    highp vec2 lo = uBounds.xy * invSize;
    highp vec2 hi = uBounds.zw * invSize;
    highp vec2 step = uAxis * invSize;
    vec4 frost = vec4(0.0);
    for (int i = 0; i < 2; i++) {
        for (int j = 0; j < 4; j++) {
            frost += uWeights[i][j]
                * texture(uCopy, clamp(uv + step * uOffsets[i][j], lo, hi));
        }
    }
    fragColor = frost;
}

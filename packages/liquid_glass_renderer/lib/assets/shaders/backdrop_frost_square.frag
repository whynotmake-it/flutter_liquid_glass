#version 460 core

// The frost drawn into a copy at the copy's own pixels in one pass, where
// it is narrow: three reads an axis, nine in all, each standing for two
// pixels of the copy. The image filter of a layer that holds the copy from
// its top-left corner, so every fragment lies on the center of a pixel of
// the copy and takes the same weights, which come worked out (latticeTaps
// in backdrop_rig.dart). A wider frost is two passes of
// backdrop_frost_axis.frag.

#include <flutter/runtime_effect.glsl>

// The copy's texture size in pixels; an image filter's engine sets it.
uniform vec2 uSize;
// The rect of the copy in the image, in its pixels, inset by half a pixel.
uniform vec4 uBounds;
// Where the three reads of an axis lie, in pixels from the fragment, and
// their weights, which add up to one.
uniform vec3 uOffsets;
uniform vec3 uWeights;

uniform sampler2D uCopy;

out vec4 fragColor;

void main() {
    highp vec2 invSize = 1.0 / uSize;
    highp vec2 uv = FlutterFragCoord().xy * invSize;
    highp vec2 lo = uBounds.xy * invSize;
    highp vec2 hi = uBounds.zw * invSize;
    highp vec3 xs = clamp(uv.x + uOffsets * invSize.x, lo.x, hi.x);
    highp vec3 ys = clamp(uv.y + uOffsets * invSize.y, lo.y, hi.y);
    vec4 frost = vec4(0.0);
    for (int j = 0; j < 3; j++) {
        vec4 row = vec4(0.0);
        for (int i = 0; i < 3; i++) {
            row += uWeights[i] * texture(uCopy, vec2(xs[i], ys[j]));
        }
        frost += uWeights[j] * row;
    }
    fragColor = frost;
}

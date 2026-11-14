#version 460 core

// The first half of a copy's haze: the copy averaged into a strip of pixels
// under it, one for every square cell of the copy. The image filter of a
// layer that holds the copy from its top-left corner and has rows to spare
// below it; backdrop_haze_mix.frag then reads the wide blur out of the
// strip.
//
// Every pixel of a cell is weighed, so what lies under the glass moves
// through the cells without a flicker: a page drawn again at the strip's
// scale would hit a thin line with some of its samples and miss it with
// others. A strip pixel takes many reads, and there are few of them: all of
// the strip's reads come to a quarter of the copy's pixels.

precision mediump float;

#include <flutter/runtime_effect.glsl>

// The layer's texture size in pixels; an image filter's engine sets it.
uniform highp vec2 uSize;
// The rect of the copy in the layer, in its pixels, inset by half a pixel.
uniform highp vec4 uBounds;
// The row the strip begins at, the side of a cell in the copy's pixels, the
// reads along a side of a cell (each stands for two pixels) and the weight
// of one read.
uniform highp vec4 uStrip;

uniform sampler2D uCopy;

out vec4 fragColor;

void main() {
    highp vec2 invSize = 1.0 / uSize;
    highp vec2 at = FlutterFragCoord().xy;
    if (at.y < uStrip.x) {
        fragColor = texture(uCopy, at * invSize);
        return;
    }
    highp vec2 low = uBounds.xy * invSize;
    highp vec2 high = uBounds.zw * invSize;
    highp vec2 pace = 2.0 * invSize;
    // The corner between the first four pixels of the fragment's cell.
    highp vec2 start =
        (floor(vec2(at.x, at.y - uStrip.x)) * uStrip.y + 1.0) * invSize;
    highp vec2 read = start;
    // Sixteen bits of a float lose the small terms of a long sum.
    highp vec4 sum = vec4(0.0);
    float column = 0.0;
    float row = 0.0;
    // One loop over the cell's reads, row after row: a loop inside a loop
    // takes 63 work registers on a Mali-G78 and spills, and the fragments
    // that only pass the copy on would pay for it too.
    for (int n = 0; n < 1024; n++) {
        sum += texture(uCopy, clamp(read, low, high));
        column += 1.0;
        read.x += pace.x;
        if (column >= uStrip.z) {
            row += 1.0;
            if (row >= uStrip.z) break;
            column = 0.0;
            read = vec2(start.x, read.y + pace.y);
        }
    }
    fragColor = sum * uStrip.w;
}

#version 460 core

// The second half of a copy's haze: the wide blur of the copy, read out of
// the strip backdrop_haze_strip.frag left under it, mixed into the copy. The
// image filter of a layer that holds that filter's output from its top-left
// corner.
//
// The wide blur is a bell over the strip's pixels, six of them along each
// axis, on top of the cell each already averages. Its weights are worked
// out for the place of every fragment between the strip's pixels: weights
// fixed for a pixel's center let a striped page through as ripples. Two
// pixels share a read, so it is nine reads. The mix is iOS 27's: every
// channel moves to the wide blur by one amount where the blur is lighter
// and by another where it is darker, and the wide blur then covers the
// result by a third.

precision mediump float;

#include <flutter/runtime_effect.glsl>

// The layer's texture size in pixels; an image filter's engine sets it.
uniform highp vec2 uSize;
// The rect of the copy in the layer, in its pixels. Nothing is drawn
// outside it: the strip is not part of the copy.
uniform highp vec4 uRect;
// The row the strip begins at, the strip's pixels to one pixel of the copy
// and the strip's size in pixels.
uniform highp vec4 uStrip;
// One over the square of how many strip pixels the bell reaches: a strip
// pixel a distance d away weighs (1 - d * d * uReach) squared, and nothing
// past the reach, so a pixel entering the six weighs nothing.
uniform float uReach;
// How far a channel moves to the wide blur where the blur is lighter, where
// it is darker, and how much of the result the blur covers.
uniform vec3 uMix;

uniform sampler2D uCopy;

out vec4 fragColor;

const vec3 kPairs = vec3(-2.0, 0.0, 2.0);

void main() {
    highp vec2 invSize = 1.0 / uSize;
    highp vec2 at = FlutterFragCoord().xy;
    highp vec2 cell = at * uStrip.y;
    // The center of the strip pixel at or before the fragment, and how far
    // past it the fragment lies.
    highp vec2 first = floor(cell - 0.5) + 0.5;
    vec2 part = cell - first;
    // Along each axis three reads, each of two strip pixels: the pixels'
    // distances from the fragment and their weights.
    vec3 nearX = kPairs - part.x;
    vec3 nearY = kPairs - part.y;
    vec3 ax = max(1.0 - nearX * nearX * uReach, 0.0);
    vec3 bx = max(1.0 - (nearX + 1.0) * (nearX + 1.0) * uReach, 0.0);
    vec3 ay = max(1.0 - nearY * nearY * uReach, 0.0);
    vec3 by = max(1.0 - (nearY + 1.0) * (nearY + 1.0) * uReach, 0.0);
    ax *= ax;
    bx *= bx;
    ay *= ay;
    by *= by;
    vec3 wx = ax + bx;
    vec3 wy = ay + by;
    // A read lies between its two pixels by their weights.
    highp vec3 xs =
        clamp(first.x + kPairs + bx / max(wx, 1e-4), 0.5, uStrip.z - 0.5)
        * invSize.x;
    highp vec3 ys =
        (clamp(first.y + kPairs + by / max(wy, 1e-4), 0.5, uStrip.w - 0.5)
            + uStrip.x)
        * invSize.y;
    wx /= wx.x + wx.y + wx.z;
    wy /= wy.x + wy.y + wy.z;
    vec4 wide = vec4(0.0);
    for (int j = 0; j < 3; j++) {
        vec4 row = vec4(0.0);
        for (int i = 0; i < 3; i++) {
            row += wx[i] * texture(uCopy, vec2(xs[i], ys[j]));
        }
        wide += wy[j] * row;
    }
    vec4 sharp = texture(uCopy, at * invSize);
    // A layer cut short of the strip has no wide blur to mix.
    wide = mix(sharp, wide, step(uStrip.x + uStrip.w - 0.5, uSize.y));
    // One amount picked by the sign, not a lighter and a darker of the two
    // each scaled: that form takes 61 work registers on a Mali-G78, where
    // past 32 a shader runs half as many fragments at once.
    vec4 toWide = wide - sharp;
    vec4 mixed =
        sharp + toWide * mix(vec4(uMix.y), vec4(uMix.x), step(0.0, toWide));
    highp vec2 inside = step(uRect.xy, at) * step(at, uRect.zw);
    fragColor = mix(mixed, wide, uMix.z) * (inside.x * inside.y);
}

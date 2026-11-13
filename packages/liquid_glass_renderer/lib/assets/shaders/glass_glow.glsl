// The touch glow of one lit shape (see LiquidGlassGlow), applied to the
// glass color under the content painted after the layer: the wash adds to
// every channel, the spot multiplies them by 1 + gain exp(-r^2 / (2 sigma^2))
// and clamps at white. iOS composes the two as a plus blend, then a color
// dodge; the plus blend's own clamp is left out because the multiplier is at
// least 1, so it changes nothing. Both stay inside the lit surface's
// circular rounded box, antialiased over one pixel.
//
// LiquidGlassGlow.shade (lib/src/liquid_glass_glow.dart) is the CPU
// reference of this function; change both or neither.
//
// spot: center (matte device px), the falloff log2(e) / (2 sigma^2) per
// squared device px, gain.
// box: the lit surface's center and half extents (matte device px).
// shape: x the corner radius (device px), y the wash.
//
// Device pixels stay highp even though the rest of the shader is mediump. On a
// 16-bit mediump, as on a Mali-G615, dot(r, r) overflows 256 px from the finger:
// the spot stops there with a hard edge, and once it has faded and the falloff
// is 0, 0 * infinity makes the whole lit surface past that line white.
vec3 applyGlassGlow(
    vec3 color,
    highp vec2 p,
    highp vec4 spot,
    highp vec4 box,
    highp vec4 shape
) {
    highp vec2 q = abs(p - box.xy) - box.zw + shape.x;
    highp float d =
        length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - shape.x;
    float cover = clamp(0.5 - d, 0.0, 1.0);
    highp vec2 r = p - spot.xy;
    highp float factor = 1.0 + spot.w * exp2(-spot.z * dot(r, r));
    vec3 lit = min((color + vec3(shape.y)) * factor, vec3(1.0));
    return mix(color, lit, cover);
}

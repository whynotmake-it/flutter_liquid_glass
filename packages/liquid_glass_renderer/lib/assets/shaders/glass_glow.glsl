// The touch glow of one lit shape (see LiquidGlassGlow), applied to the
// glass color under the content painted after the layer: the wash adds to
// every channel, the spot multiplies them by 1 + gain exp(-r^2 / (2 sigma^2))
// and clamps at white. iOS composes the two as a plus blend, then a color
// dodge; the plus blend's own clamp is left out because the multiplier is at
// least 1, so it changes nothing.
//
// spot: center (matte device px), the falloff log2(e) / (2 sigma^2) per
// squared device px, gain.
//
// Device pixels stay highp even though the rest of the shader is mediump. On a
// 16-bit mediump, as on a Mali-G615, dot(r, r) overflows 256 px from the finger:
// the spot stops there with a hard edge, and once it has faded and the falloff
// is 0, 0 * infinity makes the whole lit surface past that line white.
vec3 applyGlassGlow(
    vec3 color,
    highp vec2 p,
    highp vec4 spot,
    highp vec4 neighborFence,
    float wash
) {
    highp vec2 q = abs(p - neighborFence.xy) - neighborFence.zw;
    float cover = clamp(0.5 - max(q.x, q.y), 0.0, 1.0);
    highp vec2 r = p - spot.xy;
    highp float factor = 1.0 + spot.w * exp2(-spot.z * dot(r, r));
    vec3 lit = min((color + vec3(wash)) * factor, vec3(1.0));
    return mix(color, lit, cover);
}

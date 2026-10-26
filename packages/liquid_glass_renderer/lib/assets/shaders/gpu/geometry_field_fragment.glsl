// Geometry pass for a body whose outline its owner has already fused
// (LiquidGlassLayer.field): the same matte as geometry_fragment.glsl, but
// the signed distance, its gradient and the local half thickness come from
// a sampled field instead of the analytic shapes. The field is a
// float texture of nodes on a square grid, one RGBA texel per node:
// R = signed distance (negative inside), G and B = its gradient, A = the
// half minor extent of the part the node belongs to; R and A are in logical
// pixels. RGBA32F is not filterable on every GPU, so the texture is sampled
// nearest and the shader interpolates the four nodes around a pixel
// bilinearly, which keeps the distance and the normal continuous.

precision highp float;

layout(std140) uniform FieldUniforms {
    vec2 uOffset;
    // xy: node (0, 0), z: the node step, both in matte pixels; w: matte
    // pixels per logical pixel, the unit of the field's values.
    vec4 uFieldFrame;
    // xy: the nodes along x and y; zw: one texel of the texture, whose
    // top-left the field fills.
    vec4 uFieldSize;
    vec4 uLowRes;
} fieldUniforms;

uniform sampler2D uField;

#define uOffset fieldUniforms.uOffset
#define uFieldFrame fieldUniforms.uFieldFrame
#define uFieldSize fieldUniforms.uFieldSize

out vec4 fragColor;

#include "matte_encoding.glsl"

// The field interpolated at p (matte pixels).
vec4 fieldAt(vec2 p) {
    vec2 grid = clamp(
        (p - uFieldFrame.xy) / uFieldFrame.z,
        vec2(0.0),
        uFieldSize.xy - 1.0
    );
    vec2 cell = min(floor(grid), uFieldSize.xy - 2.0);
    vec2 f = grid - cell;
    vec2 texel = uFieldSize.zw;
    vec4 a = texture(uField, (cell + vec2(0.5, 0.5)) * texel);
    vec4 b = texture(uField, (cell + vec2(1.5, 0.5)) * texel);
    vec4 c = texture(uField, (cell + vec2(0.5, 1.5)) * texel);
    vec4 d = texture(uField, (cell + vec2(1.5, 1.5)) * texel);
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void main() {
    float scale = fieldUniforms.uLowRes.x;
    vec2 position = (gl_FragCoord.xy - 0.5) * scale + uOffset + kPixelCenter;
    vec4 field = fieldAt(position);
    fragColor = encodeMatte(
        field.r * uFieldFrame.w,
        field.gb,
        field.a * uFieldFrame.w
    );
}

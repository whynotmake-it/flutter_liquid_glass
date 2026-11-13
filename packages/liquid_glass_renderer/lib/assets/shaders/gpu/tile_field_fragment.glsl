// Draws a geometry atlas of a fused body (LiquidGlassLayer.field): its
// constant tiles and its table (tile_fill.glsl), and its ring strips, whose
// texels evaluate the field as tile_geometry_fragment.glsl evaluates shapes.
// The field is a float texture of nodes on a grid, one RGBA texel per node:
// R = signed distance (negative inside), G and B = its gradient, A = the half
// minor extent of the part the node belongs to; R and A are in logical
// pixels. RGBA32F is not filterable on every GPU, so the texture is sampled
// nearest and the shader interpolates the four nodes around a pixel
// bilinearly, which keeps the distance and the normal continuous. With
// LOOKS the shapes the body grew from give each texel its look: a strip's
// ramp names their rows, x - 64 the first and y how many.

precision highp float;

#ifndef LOOKS
#define LOOKS 0
#endif
#define SCENE_LOOKS LOOKS

layout(std140) uniform TileFieldUniforms {
    // Buffer pixels to grid coordinates: grid = mat2(xx, yx, xy, yy) * p +
    // uGridShift.xy, node (i, j) at (i, j).
    vec4 uBufferToGrid;
    // xy: the grid shift; z: buffer pixels per logical pixel of the field's
    // values.
    vec4 uGridShift;
    // xy: the nodes along x and y; zw: one texel of the texture, whose
    // top-left the field fills.
    vec4 uFieldSize;
} fieldUniforms;

uniform sampler2D uField;

#define uBufferToGrid fieldUniforms.uBufferToGrid
#define uGridShift fieldUniforms.uGridShift
#define uFieldSize fieldUniforms.uFieldSize

#if LOOKS
#include "sdf.glsl"
#endif
#include "matte_encoding.glsl"

flat in vec4 vValue;
flat in vec4 vRamp;

layout(location = 0) out vec4 fragColor;
#if LOOKS
#include "look_targets.glsl"
#endif
#include "tile_fill.glsl"

vec4 fieldAt(vec2 p) {
    vec2 grid = clamp(
        vec2(
            dot(uBufferToGrid.xy, p),
            dot(uBufferToGrid.zw, p)
        ) + uGridShift.xy,
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
    if (isFill()) {
        writeFill();
        return;
    }
    vec2 position = gl_FragCoord.xy * vValue.z + vValue.xy;
    vec4 field = fieldAt(position);
    fragColor = encodeMatte(
        field.r * uGridShift.z,
        field.gb,
        field.a * uGridShift.z
    );
#if LOOKS
    writeLook(
        sceneSample(position, int(vRamp.x) & 15, int(vRamp.y)).look
    );
#endif
}

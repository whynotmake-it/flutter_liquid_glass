// One quad of a geometry atlas (geometry_tiling.dart), drawn once per
// instance: the vertices carry a corner of the unit square, and an instance
// its rectangle in clip space (left, top, right, bottom) with the value and
// the ramp every fragment of the quad gets: what a fill quad writes
// (tile_fill.glsl), or where a strip finds the buffer pixel under a texel
// and the shapes it evaluates there.

in vec2 corner;
in vec4 rect;
in vec4 value;
in vec4 ramp;

flat out vec4 vValue;
flat out vec4 vRamp;

void main() {
  gl_Position = vec4(mix(rect.xy, rect.zw, corner), 0.0, 1.0);
  vValue = value;
  vRamp = ramp;
}

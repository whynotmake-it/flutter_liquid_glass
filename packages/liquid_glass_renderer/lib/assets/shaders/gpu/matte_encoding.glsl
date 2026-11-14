// A geometry texel, written the same way by the shape strips
// (tile_geometry_fragment.glsl) and the field strips
// (tile_field_fragment.glsl).

// Distances are capped here, well within 16-bit float range. A hidden shape
// reports a distance of 1e9, which would otherwise become infinity and break
// the blending between texels.
const float kInwardLimit = 16000.0;
// The value of texels far outside every shape: far outside, and still within
// a 16-bit float. Keep in sync with kFarInward in the renderer.
const float kFarInward = -4096.0;

// R: the distance to the edge, positive inside. GB: the direction the surface
// faces, scaled by the square root of the gradient's length, so it refracts
// less where a smooth union shortens the gradient. A: half the thickness.
vec4 encodeMatte(float distance, vec2 gradient, float halfMinor) {
    float gradientLength = length(gradient);
    vec2 normal = gradientLength > 0.0001
        ? gradient / gradientLength
        : vec2(0.0);
    return vec4(
        clamp(-distance, -kInwardLimit, kInwardLimit),
        normal * sqrt(clamp(gradientLength, 0.0, 1.0)),
        halfMinor
    );
}

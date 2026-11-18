// The quads of a geometry atlas that hold no geometry: its constant tiles and
// its table. With LOOKS a deep block writes the look of row ramp.z
// (looks.glsl) beside it, and a quad with a negative ramp.z none.
//
// Included after the including shader has declared vValue, vRamp, fragColor
// and, with LOOKS, the look targets.

#include "shader_constants.glsl"

bool isFill() {
    return vRamp.x >= RAMP_FILL;
}

void writeFill() {
    vec2 tile = floor(gl_FragCoord.xy - vRamp.yw);
    float entryStride = ATLAS_TILE_SIZE * vValue.z;
    fragColor = vValue + vec4(entryStride * tile, 0.0, 0.0);
#if LOOKS
    writeLook(
        vRamp.z < 0.0
            ? Look(vec4(0.0), vec4(0.0), vec4(0.0))
            : lookAt(int(vRamp.z) & SHAPE_INDEX_MASK)
    );
#endif
}

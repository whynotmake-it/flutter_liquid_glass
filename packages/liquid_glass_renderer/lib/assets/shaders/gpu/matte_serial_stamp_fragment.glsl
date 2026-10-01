// Copyright 2025, Tim Lehmann for whynotmake.it
//
// Validation only, off by default: the render-order check behind
// LIQUID_GLASS_VALIDATE_MATTE_ORDER. Writes the render serial into one texel
// below the matte, which the final shader compares with the serial of the
// frame that samples it.
layout(std140) uniform StampUniforms {
    vec4 uStamp;
} stampUniforms;

out vec4 fragColor;

void main() {
    fragColor = stampUniforms.uStamp;
}

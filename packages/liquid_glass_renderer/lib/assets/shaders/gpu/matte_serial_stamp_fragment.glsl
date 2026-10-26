// Harness-only render-order check (LIQUID_GLASS_VALIDATE_MATTE_ORDER): writes
// the render serial into one texel below the matte, which the final shader
// compares with the serial of the frame that samples it.
//
// This shader is compiled into its own validation bundle
// (liquid_glass_renderer_validate.shaderbundle); the production geometry
// bundle never contains it.
layout(std140) uniform StampUniforms {
    vec4 uStamp;
} stampUniforms;

out vec4 fragColor;

void main() {
    fragColor = stampUniforms.uStamp;
}

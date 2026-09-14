#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform sampler2D uTexture;

out vec4 fragColor;

void main() {
  fragColor = texture(uTexture, FlutterFragCoord().xy / uSize);
}

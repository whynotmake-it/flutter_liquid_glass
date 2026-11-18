#version 460 core
// Positions are the layer's, up to thousands of logical pixels: at 16 bits a
// node would land a pixel off.
precision highp float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uNodes;
#include "fake_glass_lanes.glsl"
#include "shader_constants.glsl"
uniform vec4 uGrid;
uniform sampler2D uField;

layout(location = 0) out vec4 fragColor;

#include "fake_glass_lighting.glsl"

void main() {
  vec2 node = (FlutterFragCoord().xy - uGrid.xy) / uGrid.z;
  vec4 texel = texture(uField, (node + 0.5) / uNodes);
  float distance = mix(-kFakeFieldInside, kFakeFieldOutside, texel.r);
  vec2 normal = normalize(texel.gb * 2.0 - 1.0 + vec2(0.00001));
  float coveredByLayerClip = 1.0;
  fragColor = fakeGlassLit(distance, normal, coveredByLayerClip);
}

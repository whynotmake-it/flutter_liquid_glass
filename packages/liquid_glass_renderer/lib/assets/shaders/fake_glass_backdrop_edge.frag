// Copyright 2025, Tim Lehmann for whynotmake.it

// Anti-aliases FakeGlass's filtered backdrop on Impeller, which clips
// backdrop filters with the stencil. The filtered pass is clipped a little
// outside the shapes; this pass reads the same unfiltered backdrop snapshot
// (a shared BackdropKey) in a thin band around the silhouette and puts it
// back over the filtered pass with weight 1 - coverage. Coverage is the same
// one-pixel box coverage as the analytic surface drawn on top, so both
// clips' hard edges land where the result equals the backdrop or the
// filtered face exactly.

#version 460 core
precision highp float;

#include <flutter/runtime_effect.glsl>

#define MAX_SHAPES 16

uniform vec2 uSize;
// Maps filter fragment coordinates (physical pixels of the enclosing pass,
// which the unfiltered snapshot spans) to the layer's logical coordinates.
uniform vec4 uPassToLayerBasis;
uniform vec2 uPassToLayerOffset;
uniform float uShapeCount;
// Per shape: layer-to-shape affine basis; its offset and half size; corner
// radius, shape type (0 oval, 1 rounded rectangle, 2 rounded superellipse)
// and the shape-space length of one physical pixel; then the three rounded
// superellipse parameter vectors.
uniform vec4 uShapes[MAX_SHAPES * 6];
uniform sampler2D uTexture;

out vec4 fragColor;

#include "fake_glass_shape.glsl"

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 layerPoint = vec2(
        dot(uPassToLayerBasis.xy, fragCoord),
        dot(uPassToLayerBasis.zw, fragCoord)
    ) + uPassToLayerOffset;
    float coverage = 0.0;
    for (int i = 0; i < MAX_SHAPES; i++) {
        if (float(i) >= uShapeCount) break;
        vec4 basis = uShapes[i * 6];
        vec4 placement = uShapes[i * 6 + 1];
        vec4 profile = uShapes[i * 6 + 2];
        vec2 local = vec2(
            dot(basis.xy, layerPoint),
            dot(basis.zw, layerPoint)
        ) + placement.xy;
        float distance = sdFakeGlassShape(
            profile.y,
            local,
            placement.zw,
            profile.x,
            uShapes[i * 6 + 3],
            uShapes[i * 6 + 4],
            uShapes[i * 6 + 5]
        );
        coverage = max(
            coverage,
            clamp(0.5 - distance / profile.z, 0.0, 1.0)
        );
        if (coverage >= 1.0) break;
    }
    fragColor = texture(uTexture, fragCoord / uSize) * (1.0 - coverage);
}

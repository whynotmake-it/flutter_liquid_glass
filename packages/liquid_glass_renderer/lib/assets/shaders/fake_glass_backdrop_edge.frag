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
// radius, shape type (0 oval, 1 rounded box) and the shape-space length of
// one physical pixel.
uniform vec4 uShapes[MAX_SHAPES * 3];
uniform sampler2D uTexture;

out vec4 fragColor;

float sdRoundedBox(vec2 p, vec2 halfSize, float radius) {
    radius = clamp(radius, 0.0, min(halfSize.x, halfSize.y));
    vec2 q = abs(p) - halfSize + vec2(radius);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

float sdEllipse(vec2 p, vec2 radius) {
    radius = max(radius, vec2(0.001));
    float k0 = length(p / radius);
    float k1 = length(p / (radius * radius));
    return k0 * (k0 - 1.0) / max(k1, 0.001);
}

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 layerPoint = vec2(
        dot(uPassToLayerBasis.xy, fragCoord),
        dot(uPassToLayerBasis.zw, fragCoord)
    ) + uPassToLayerOffset;
    float coverage = 0.0;
    for (int i = 0; i < MAX_SHAPES; i++) {
        if (float(i) >= uShapeCount) break;
        vec4 basis = uShapes[i * 3];
        vec4 placement = uShapes[i * 3 + 1];
        vec4 profile = uShapes[i * 3 + 2];
        vec2 local = vec2(
            dot(basis.xy, layerPoint),
            dot(basis.zw, layerPoint)
        ) + placement.xy;
        float distance = profile.y < 0.5
            ? sdEllipse(local, placement.zw)
            : sdRoundedBox(local, placement.zw, profile.x);
        coverage = max(
            coverage,
            clamp(0.5 - distance / profile.z, 0.0, 1.0)
        );
        if (coverage >= 1.0) break;
    }
    fragColor = texture(uTexture, fragCoord / uSize) * (1.0 - coverage);
}

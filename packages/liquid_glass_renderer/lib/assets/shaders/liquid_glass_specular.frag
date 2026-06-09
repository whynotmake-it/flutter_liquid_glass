// Copyright 2025, Tim Lehmann for whynotmake.it
//
// Specular highlights pass for the separate specular layer.
//
// This shader is applied as an ImageFilter over the geometry texture, so its
// input (sampler 0) IS the geometry texture and FlutterFragCoord maps 1:1 to
// its texels. That means it needs no matte transform uniform: the placement is
// handled by the Flutter canvas when the filtered image is drawn, which keeps
// the shader/pipeline cacheable.
//
// Along the rim it blends between a configurable edge color and a configurable
// highlight color based on how strongly the light hits the edge. The result is
// premultiplied and meant to be composited on top of the refracted glass.

#version 460 core
precision mediump float;

#include <flutter/runtime_effect.glsl>
#include "displacement_encoding.glsl"

// uSize (0-1) is filled by the engine with the input (geometry) image size.
// Sampler 0 is the input image (the geometry texture).
uniform vec2 uSize;
// Combined light intensity: the highlight color's alpha (base intensity) times
// the lightIntensity overdrive multiplier. Can exceed 1 to overdrive.
uniform float uLightIntensity;
uniform float uAmbientStrength;
uniform float uThickness;
// How visible the inward light bleed is (0 = off, 1 = full).
uniform float uBleedStrength;
// How far the specular wraps around the rim before fading to edgeColor.
uniform float uSpecularWrap;
uniform vec2 uLightDirection;
// Straight (non-premultiplied) colors. Only the highlight RGB is used for the
// rim/bleed tint; its intensity is carried by uLightIntensity above.
uniform vec4 uHighlightColor;
uniform vec4 uEdgeColor;

uniform sampler2D uGeometryTexture;

layout(location = 0) out vec4 fragColor;

void main() {
    vec2 uv = FlutterFragCoord().xy / uSize;

    #ifdef IMPELLER_TARGET_OPENGLES
        uv.y = 1.0 - uv.y;
    #endif

    vec4 geometryData = texture(uGeometryTexture, uv);

    float alpha = geometryData.a;
    if (alpha < 0.01) {
        fragColor = vec4(0.0);
        return;
    }

    // Height-based edge profile: the rim sits where height ~ 0 (the edge) and
    // fades towards the interior.
    float normalizedHeight = geometryData.b;

    float thicknessScale = clamp(40.0 / max(uThickness, 1.0), 1.0, 4.0);
    float edgeThreshold = mix(0.8, 0.5, 1.0 / thicknessScale);
    float edgeFactor = 1.0 - smoothstep(0.0, edgeThreshold, normalizedHeight);

    // A much wider, softer band than the crisp rim. The light bleed uses this
    // to reach further into the interior of the shape.
    float bleedThreshold = clamp(edgeThreshold * 2.2, 0.0, 1.0);
    float bleedBand = 1.0 - smoothstep(0.0, bleedThreshold, normalizedHeight);

    if (edgeFactor < 0.01 && bleedBand < 0.01) {
        fragColor = vec4(0.0);
        return;
    }

    // Use the displacement direction as a surface-normal proxy.
    float maxDisplacement = uThickness * 10.0;
    vec2 displacement = decodeDisplacement(geometryData, maxDisplacement);
    float dispLength = length(displacement);
    vec2 normalXY = dispLength > 0.001 ? displacement / dispLength : vec2(0.0);

    float mainLight = max(0.0, dot(normalXY, uLightDirection));
    float oppositeLight = max(0.0, dot(normalXY, -uLightDirection));

    float lightIntensity = uLightIntensity;

    float wrap = clamp(uSpecularWrap, 0.0, 1.0);

    // Angular envelope for where the specular rim exists at all:
    // - wrap = 0: only normals almost directly facing toward/away from light.
    // - wrap = 1: the envelope reaches all the way around the rim.
    float directness = max(mainLight, oppositeLight);
    float wrapCenter = mix(0.96, -0.3, wrap);
    float wrapSoftness = mix(0.04, 0.3, wrap);
    float specularEnvelope = smoothstep(
        wrapCenter - wrapSoftness,
        wrapCenter + wrapSoftness,
        directness
    );
    float highlightMix = smoothstep(wrapCenter, 1.0, directness);

    float directional = pow(specularEnvelope, 1.5) * lightIntensity * 3.0;
    float directionalLit = clamp(directional * thicknessScale * 0.8, 0.0, 1.0);

    // How strongly the highlight paints this part of the rim (0 = unlit,
    // 1 = fully lit).
    float lit = clamp(
        directionalLit + uAmbientStrength * thicknessScale * 0.4,
        0.0,
        1.0
    );

    vec4 edgePremult = vec4(uEdgeColor.rgb * uEdgeColor.a, uEdgeColor.a);
    vec4 highlightPremult = vec4(uHighlightColor.rgb, 1.0);
    vec4 rim = mix(edgePremult, highlightPremult, specularEnvelope * highlightMix);

    // Coverage follows the whole rim band and the anti-aliased shape alpha.
    // edgeColor is the fallback for the rim; the angular terms only decide how
    // much highlight replaces it.
    float coverage = edgeFactor * alpha;

    // --- Subtle inward light bleed ---
    // A soft glow of the highlight color that bleeds from the lit edges towards
    // the interior. It is weaker than the crisp rim highlight and applies
    // equally to both highlight directions. uBleedStrength controls how visible
    // it is.
    float bleed =
        bleedBand * specularEnvelope * lightIntensity * uBleedStrength * alpha;

    fragColor = rim * coverage + highlightPremult * bleed;
}

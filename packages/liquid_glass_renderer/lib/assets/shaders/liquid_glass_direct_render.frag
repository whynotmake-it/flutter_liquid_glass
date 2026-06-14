// Copyright 2025, Tim Lehmann for whynotmake.it
//
// Direct rendering pass for liquid glass *without* a pre-computed geometry
// texture. This computes the SDF, normal and refraction displacement inline
// from shape uniforms, then applies the exact same glass effect as
// `liquid_glass_final_render.frag`.
//
// It is used while shape geometry is actively animating, so that no
// intermediate displacement texture has to be allocated per frame. Once the
// geometry settles, the renderer bakes a texture again and switches back to
// the cheaper `liquid_glass_final_render.frag` path.
//
// Constraint: shapes must be uploaded in screen-physical pixel space and may
// only be translated/scaled (no rotation), because the SDF is evaluated
// directly in screen space.

#version 460 core
precision mediump float;

#include <flutter/runtime_effect.glsl>
#include "render.glsl"

#define MAX_SHAPES 16

uniform vec2 uSize;             // auto-populated by ImageFilter.shader
uniform vec4 uGlassColor;
uniform vec3 uOpticalProps;     // refractiveIndex, chromaticAberration, thickness
uniform vec3 uLightConfig;      // lightIntensity, ambientStrength, saturation
uniform vec2 uLightDirection;
uniform vec4 uHighlightColor;
uniform vec4 uEdgeColor;
uniform vec4 uSpecularConfig;   // edgeWidth, edgeInset, bleedStrength, specularWrap
uniform vec2 uShapeConfig;      // numShapes, blend
uniform float uShapeData[MAX_SHAPES * 6];

// Included after uShapeData so the SDF helpers can read the uniform directly.
#include "sdf.glsl"

float uRefractiveIndex = uOpticalProps.x;
float uChromaticAberration = uOpticalProps.y;
float uThickness = uOpticalProps.z;
float uLightIntensity = uLightConfig.x;
float uAmbientStrength = uLightConfig.y;
float uSaturation = uLightConfig.z;
float uEdgeWidth = uSpecularConfig.x;
float uEdgeInset = uSpecularConfig.y;
float uBleedStrength = uSpecularConfig.z;
float uSpecularWrap = uSpecularConfig.w;
float uNumShapes = uShapeConfig.x;
float uBlend = uShapeConfig.y;

uniform sampler2D uBackgroundTexture;

layout(location = 0) out vec4 fragColor;

// Identical to `applySpecularHighlights` in liquid_glass_final_render.frag so
// that the lit result matches the two-pass path exactly.
vec3 applySpecularHighlights(
    vec3 baseColor,
    vec4 geometryData,
    vec2 displacement,
    float alpha
) {
    if (
        uLightIntensity < 0.01 &&
        uAmbientStrength < 0.01 &&
        uEdgeColor.a < 0.01
    ) {
        return baseColor;
    }

    float opticalThickness = max(uThickness, 1.0);
    float inwardDistance = geometryData.b * opticalThickness;
    float edgeWidth = min(max(uEdgeWidth, 0.0), opticalThickness * 0.5);
    float highlightInset = edgeWidth * clamp(uEdgeInset, 0.0, 1.0);
    float edgeFeather = max(fwidth(inwardDistance), 0.5);

    float innerRimMask = edgeWidth > 0.0
        ? smoothstep(
            highlightInset - edgeFeather,
            highlightInset + edgeFeather,
            inwardDistance
        )
        : 1.0;
    float outlineInnerMask = edgeWidth > 0.0
        ? smoothstep(
            edgeWidth - edgeFeather,
            edgeWidth + edgeFeather,
            inwardDistance
        )
        : 1.0;
    float outlineCoverage = edgeWidth > 0.0
        ? (1.0 - outlineInnerMask) * alpha
        : 0.0;

    float thicknessScale = clamp(40.0 / max(uThickness, 1.0), 1.0, 4.0);
    float edgeThreshold = mix(0.8, 0.5, 1.0 / thicknessScale);

    float shiftedDistance = max(inwardDistance - highlightInset, 0.0);
    float shiftedDistanceRatio = clamp(
        shiftedDistance / opticalThickness,
        0.0,
        1.0
    );
    float shiftedHeight = sqrt(
        max(0.0, shiftedDistanceRatio * (2.0 - shiftedDistanceRatio))
    );
    float edgeFactor =
        (1.0 - smoothstep(0.0, edgeThreshold, shiftedHeight)) *
        innerRimMask;

    float bleedThreshold = clamp(edgeThreshold * 2.2, 0.0, 1.0);
    float bleedBand =
        (1.0 - smoothstep(0.0, bleedThreshold, shiftedHeight)) *
        innerRimMask;

    if (outlineCoverage < 0.01 && edgeFactor < 0.01 && bleedBand < 0.01) {
        return baseColor;
    }

    float dispLength = length(displacement);
    vec2 normalXY = dispLength > 0.001 ? displacement / dispLength : vec2(0.0);

    float mainLight = max(0.0, dot(normalXY, uLightDirection));
    float oppositeLight = max(0.0, dot(normalXY, -uLightDirection));
    float directness = max(mainLight, oppositeLight);

    float wrap = clamp(uSpecularWrap, 0.0, 1.0);
    float wrapCenter = mix(0.96, -0.3, wrap);
    float wrapSoftness = mix(0.04, 0.3, wrap);
    float specularEnvelope = smoothstep(
        wrapCenter - wrapSoftness,
        wrapCenter + wrapSoftness,
        directness
    );
    float highlightMix = smoothstep(wrapCenter, 1.0, directness);
    float lightIntensity = max(uLightIntensity, 0.0);
    float highlightMask = specularEnvelope * highlightMix;
    float visibleHighlightMask = highlightMask * min(lightIntensity * 0.5, 1.0);

    float highlightCoverage =
        edgeFactor * alpha * highlightMask * lightIntensity * 0.8;
    float ambientCoverage =
        edgeFactor * alpha * clamp(uAmbientStrength, 0.0, 1.0) * 0.35;
    float bleed =
        bleedBand *
        specularEnvelope *
        lightIntensity *
        uBleedStrength *
        alpha *
        0.5;
    float highlightAmount = clamp(
        highlightCoverage + ambientCoverage + bleed,
        0.0,
        1.0
    );

    vec3 highlightColor = getHighlightColor(baseColor, 1.0) * uHighlightColor.rgb;
    vec3 result = baseColor + highlightColor * highlightAmount;

    float edgeDuck =
        smoothstep(0.05, 0.35, visibleHighlightMask) * innerRimMask;
    float edgeVisibility = 1.0 - edgeDuck;
    float edgeAmount = clamp(outlineCoverage * edgeVisibility * uEdgeColor.a, 0.0, 1.0);
    result = mix(result, uEdgeColor.rgb, edgeAmount);

    return result;
}

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;

    vec2 screenUV = vec2(fragCoord.x / uSize.x, fragCoord.y / uSize.y);
    #ifdef IMPELLER_TARGET_OPENGLES
        screenUV.y = 1.0 - screenUV.y;
    #endif

    // --- Inline geometry (mirrors liquid_glass_geometry_blended.frag) ---
    float sd = sceneSDF(fragCoord, int(uNumShapes), uBlend);

    float foregroundAlpha = 1.0 - smoothstep(-2.0, 0.0, sd);
    if (foregroundAlpha < 0.01) {
        fragColor = vec4(0.0);
        return;
    }

    if (sd >= 0.0 || uThickness <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }

    float dx = dFdx(sd);
    float dy = dFdy(sd);

    float n_cos = max(uThickness + sd, 0.0) / uThickness;
    float n_sin = sqrt(max(0.0, 1.0 - n_cos * n_cos));
    vec3 normal = normalize(vec3(dx * n_cos, dy * n_cos, n_sin));

    float x = uThickness + sd;
    float sqrtTerm = sqrt(max(0.0, uThickness * uThickness - x * x));
    float height = mix(sqrtTerm, uThickness, float(sd < -uThickness));

    float baseHeight = uThickness * 8.0;
    vec3 incident = vec3(0.0, 0.0, -1.0);
    float invRefractiveIndex = 1.0 / uRefractiveIndex;
    vec3 baseRefract = refract(incident, normal, invRefractiveIndex);
    float baseRefractLength =
        (height + baseHeight) / max(0.001, abs(baseRefract.z));
    vec2 displacement = baseRefract.xy * baseRefractLength;

    float edgeDistance = -sd;
    float normalizedEdgeDistance =
        clamp(edgeDistance / max(uThickness, 1e-4), 0.0, 1.0);
    vec4 geometryData = vec4(0.0, 0.0, normalizedEdgeDistance, foregroundAlpha);

    // --- Refraction + glass color (mirrors liquid_glass_final_render.frag) ---
    vec2 invUSize = 1.0 / uSize;

    vec4 refractColor;
    if (uChromaticAberration < 0.01) {
        vec2 refractedUV = screenUV + displacement * invUSize;
        refractColor = texture(uBackgroundTexture, refractedUV);
    } else {
        float dispersionStrength = uChromaticAberration * 0.5;
        vec2 redOffset = displacement * (1.0 + dispersionStrength);
        vec2 blueOffset = displacement * (1.0 - dispersionStrength);

        vec2 redUV = screenUV + redOffset * invUSize;
        vec2 greenUV = screenUV + displacement * invUSize;
        vec2 blueUV = screenUV + blueOffset * invUSize;

        float red = texture(uBackgroundTexture, redUV).r;
        vec4 greenSample = texture(uBackgroundTexture, greenUV);
        float blue = texture(uBackgroundTexture, blueUV).b;

        refractColor = vec4(red, greenSample.g, blue, greenSample.a);
    }

    vec4 finalColor;
    finalColor.rgb =
        uGlassColor.rgb * uGlassColor.a + refractColor.rgb * (1.0 - uGlassColor.a);
    finalColor.a = refractColor.a;
    finalColor.rgb = applySaturation(finalColor.rgb, uSaturation);

    float alpha = geometryData.a;
    finalColor.rgb = applySpecularHighlights(
        finalColor.rgb,
        geometryData,
        displacement,
        alpha
    );

    fragColor = vec4(finalColor.rgb * alpha, alpha);
}

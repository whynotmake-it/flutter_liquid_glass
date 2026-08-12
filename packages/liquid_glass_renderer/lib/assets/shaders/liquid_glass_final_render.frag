// Copyright 2025, Tim Lehmann for whynotmake.it
//
// Final rendering pass for liquid glass with pre-computed geometry
// This shader reads displacement data from a pre-computed texture and applies
// the liquid glass effect efficiently

#version 460 core
precision mediump float;

#define DEBUG_GEOMETRY 0

#include <flutter/runtime_effect.glsl>
#include "displacement_encoding.glsl"
#include "render.glsl"

uniform vec2 uSize;
uniform vec2 uGeometryOffset;
uniform vec2 uGeometrySize;

uniform vec4 uGlassColor;
uniform vec3 uOpticalProps;
uniform vec3 uLightConfig;
uniform vec2 uLightDirection;
uniform vec4 uHighlightColor;
uniform vec4 uEdgeColor;
uniform vec4 uSpecularConfig;

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

uniform sampler2D uBackgroundTexture;
uniform sampler2D uGeometryTexture;

layout(location = 0) out vec4 fragColor;

vec2 mirrorBackgroundUV(vec2 uv, vec2 inverseTextureSize) {
    // Image-filter sampler edge behavior differs between Impeller backends.
    // Preserve every coordinate inside the input texture exactly, and mirror
    // only displaced samples that genuinely leave it. This avoids GLES decal
    // black without clamping Metal samples into stretched edge pixels.
    vec2 mirrored = vec2(1.0) - abs(mod(uv, vec2(2.0)) - vec2(1.0));
    vec2 halfTexel = inverseTextureSize * 0.5;
    return clamp(mirrored, halfTexel, vec2(1.0) - halfTexel);
}

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
    // Flutter runtime-effect shaders do not expose fragment derivatives, even
    // when Impeller is the active renderer. Use a fixed half-pixel feather;
    // this is cheaper than fwidth(), but does not adapt to local scaling.
    float edgeFeather = 0.5;

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
    // FlutterFragCoord is the BackdropFilter's clip-local space. Geometry is
    // encoded in the same layer-local space, so ancestor transforms are
    // compositor-only and this pass only subtracts the matte origin.
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 screenUV = fragCoord / uSize;
    #ifdef IMPELLER_TARGET_OPENGLES
        screenUV.y = 1.0 - screenUV.y;
    #endif

    vec2 geometryUV = (fragCoord - uGeometryOffset) / uGeometrySize;
    #ifdef IMPELLER_TARGET_OPENGLES
        // Runtime-effect image samplers use bottom-up UVs on OpenGLES even
        // after the geometry pass has canonicalized its fragment coordinates.
        geometryUV.y = 1.0 - geometryUV.y;
    #endif

    if (
        any(lessThan(geometryUV, vec2(0.0))) ||
        any(greaterThan(geometryUV, vec2(1.0)))
    ) {
        fragColor = vec4(0.0);
        return;
    }

    vec4 geometryData = texture(uGeometryTexture, geometryUV);

    #if DEBUG_GEOMETRY
        fragColor = geometryData;
        return;
    #endif
    
    if (geometryData.a < 0.01) {
        fragColor = vec4(0);
        return;
    }

    float maxDisplacement = uThickness * 10.0;
    vec2 displacement = decodeDisplacement(geometryData, maxDisplacement);

    #ifdef IMPELLER_TARGET_OPENGLES
        displacement.y = -displacement.y;
    #endif

    vec2 invUSize = 1.0 / uSize;
    
    vec4 refractColor;
    if (uChromaticAberration < 0.01) {
        vec2 refractedUV = mirrorBackgroundUV(
            screenUV + displacement * invUSize,
            invUSize
        );
        refractColor = texture(uBackgroundTexture, refractedUV);
    } else {
        float dispersionStrength = uChromaticAberration * 0.5;
        vec2 redOffset = displacement * (1.0 + dispersionStrength);
        vec2 blueOffset = displacement * (1.0 - dispersionStrength);
        
        vec2 redUV = mirrorBackgroundUV(
            screenUV + redOffset * invUSize,
            invUSize
        );
        vec2 greenUV = mirrorBackgroundUV(
            screenUV + displacement * invUSize,
            invUSize
        );
        vec2 blueUV = mirrorBackgroundUV(
            screenUV + blueOffset * invUSize,
            invUSize
        );
        
        float red = texture(uBackgroundTexture, redUV).r;
        vec4 greenSample = texture(uBackgroundTexture, greenUV);
        float blue = texture(uBackgroundTexture, blueUV).b;
        
        refractColor = vec4(red, greenSample.g, blue, greenSample.a);
    }
    
    // Apply glass color using alpha blending
    vec4 finalColor;
    finalColor.rgb = uGlassColor.rgb * uGlassColor.a + refractColor.rgb * (1.0 - uGlassColor.a);
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

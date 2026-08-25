// Copyright 2025, Tim Lehmann for whynotmake.it
//
// Final rendering pass for liquid glass with pre-computed geometry
// This shader reads displacement data from a pre-computed texture and applies
// the liquid glass effect efficiently

#version 460 core
// Refraction is evaluated in global filter coordinates. Keep the affine
// mapping and sub-pixel displacement in high precision on GLES; mediump turns
// the coordinate subtraction into visible shimmer on large layers.
precision highp float;

#define DEBUG_GEOMETRY 0

#include <flutter/runtime_effect.glsl>
#include "displacement_encoding.glsl"
#include "render.glsl"

uniform vec2 uSize;
uniform vec2 uGeometryOffset;
uniform vec2 uGeometrySize;

uniform vec4 uTint;
uniform vec3 uOpticalProps;
uniform vec3 uLightConfig;
uniform vec2 uLightDirection;
uniform vec4 uHighlightColor;
uniform vec4 uContourColor;
uniform vec4 uReservedContourColor;
uniform vec2 uContourConfig;
uniform vec4 uProfileConfig;
uniform vec2 uMaterialConfig;
uniform vec2 uReservedFaceConfig;
uniform vec3 uReservedShadowConfig;

// The second reserved face slot is a stable normalized row in the shared
// coordinate atlas. Keeping this in an existing unused slot avoids changing
// the public material vector or adding a per-frame filter input.
float uCoordinateRow = uReservedFaceConfig.y;

float uDisplacementScale = uOpticalProps.x;
float uChromaticAberration = uOpticalProps.y;
float uThickness = uOpticalProps.z;
float uLightIntensity = uLightConfig.x;
float uAmbientStrength = 0.0;
float uSaturation = uLightConfig.z;
float uEdgeWidth = uContourConfig.x;
float uEdgeInset = 0.25;
float uBleedStrength = 0.375;
float uSpecularWrap = 0.25;
float uTransmissionGamma = uMaterialConfig.x;
float uVibrancy = uMaterialConfig.y;
float uFaceShadingStrength = uLightConfig.x * 0.03;
float uFaceShadingDepth = max(uThickness * 3.0, 1.0);
float uInnerShadowStrength = uContourColor.a * 0.25;
float uInnerShadowDepth = max(uThickness, 1.0);
float uInnerShadowDirectionality = 0.0;

uniform sampler2D uBackgroundTexture;
uniform sampler2D uGeometryTexture;
uniform sampler2D uCoordinateTexture;

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
    vec2 surfaceUV
) {
    if (
        uLightIntensity < 0.01 &&
        uAmbientStrength < 0.01 &&
        uContourColor.a < 0.01
    ) {
        return baseColor;
    }

    float opticalThickness = max(uThickness, 1.0);
    float inwardDistance = decodeEdgeDistance(geometryData, opticalThickness);
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
    float insideOutlineCoverage = edgeWidth > 0.0
        // Keep material masks unpremultiplied. Coverage is applied exactly
        // once at the end of main(); multiplying by alpha here attenuates the
        // thin contour/highlight a second time.
        ? (1.0 - outlineInnerMask)
        : 0.0;
    float outlineCoverage = insideOutlineCoverage;

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

    if (
        outlineCoverage < 0.01 &&
        edgeFactor < 0.01 &&
        bleedBand < 0.01 &&
        uFaceShadingStrength < 0.001 &&
        uContourColor.a < 0.001
    ) {
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
    float highlightFactor = edgeFactor;
    float highlightCoverage =
        highlightFactor * highlightMask * lightIntensity * 0.8;
    float ambientCoverage =
        edgeFactor * clamp(uAmbientStrength, 0.0, 1.0) * 0.35;
    float bleed =
        bleedBand *
        specularEnvelope *
        lightIntensity *
        uBleedStrength *
        0.5;
    float highlightAmount = max(
        highlightCoverage + ambientCoverage + bleed,
        0.0
    );
    // Specular light is an incident-light color, not a tint of the transmitted
    // backdrop. Deriving it from baseColor creates colored perimeter residuals
    // on checkerboard/reference probes and makes highlights depend on blur.
    vec3 highlightColor = uHighlightColor.rgb;
    vec2 facePosition = (surfaceUV - vec2(0.5)) * uGeometrySize;
    vec2 halfSize = uGeometrySize * 0.5;
    float lightSupport =
        abs(uLightDirection.x) * halfSize.x +
        abs(uLightDirection.y) * halfSize.y;
    // The contour also supplies a derived, symmetric bevel occlusion. This is
    // not an independent shadow control: it is the same SDF profile viewed as
    // absorption beneath a dielectric coating.
    float bevelOcclusion = clamp(
        (1.0 - smoothstep(0.0, max(uThickness, 1.0), inwardDistance)) *
        uContourColor.a * 0.25,
        0.0,
        1.0
    );
    float edgeAbsorption = clamp(
        outlineCoverage * uContourColor.a,
        0.0,
        1.0
    );
    float edgeTransmittance = 1.0 - edgeAbsorption;
    vec3 result = baseColor * edgeTransmittance +
        uContourColor.rgb * edgeAbsorption;
    result *= 1.0 - bevelOcclusion;
    result += highlightColor * highlightAmount;

    return result;
}

void main() {
    // Map image-filter fragment coordinates back into the layer-local geometry
    // matte. Apple Metal surfaces expose global filter coordinates, while
    // other backends may expose clip-local coordinates; this live affine
    // mapping handles both without rebuilding the native image filter.
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 screenUV = fragCoord / uSize;

    vec4 filterToMatteBasis = texture(
        uCoordinateTexture,
        vec2(0.25, uCoordinateRow)
    );
    vec2 filterToMatteOffset = texture(
        uCoordinateTexture,
        vec2(0.75, uCoordinateRow)
    ).xy;
    vec2 matteCoord = vec2(
        dot(filterToMatteBasis.xy, fragCoord),
        dot(filterToMatteBasis.zw, fragCoord)
    ) + filterToMatteOffset;
    vec2 geometryUV = (matteCoord - uGeometryOffset) / uGeometrySize;

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

    float maxDisplacement = max(uDisplacementScale, 0.001);
    vec2 displacement = decodeDisplacement(geometryData, maxDisplacement);

    vec2 invUSize = 1.0 / uSize;
    
    vec4 refractColor;
    // The public/default value is intentionally small (~0.005), but it still
    // represents a real channel separation. The old 0.01 cutoff silently
    // disabled that range and made CA appear broken. Only exact-zero values
    // take the single-sample fast path.
    if (uChromaticAberration < 0.0001) {
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
    
    vec3 transmittedColor = pow(
        max(refractColor.rgb, vec3(0.0)),
        vec3(max(uTransmissionGamma, 0.01))
    );
    vec3 materialColor = uTint.rgb * uTint.a;
    transmittedColor *= 1.0 - uTint.a;
    vec3 baseColor = materialColor + transmittedColor;
    baseColor = applySaturation(baseColor, uSaturation);
    float chroma = max(max(baseColor.r, baseColor.g), baseColor.b) -
        min(min(baseColor.r, baseColor.g), baseColor.b);
    baseColor = clamp(
        baseColor + vec3(chroma * max(uVibrancy, 0.0)),
        0.0,
        1.0
    );

    float alpha = geometryData.a;
    vec3 finalColor = applySpecularHighlights(
        baseColor,
        geometryData,
        displacement,
        geometryUV
    );

    fragColor = vec4(finalColor * alpha, alpha);
}

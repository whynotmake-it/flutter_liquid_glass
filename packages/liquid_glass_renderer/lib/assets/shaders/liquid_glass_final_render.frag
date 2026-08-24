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
uniform vec4 uOuterContourColor;
uniform vec2 uOuterContourConfig;
uniform vec4 uSpecularConfig;
uniform vec2 uMaterialConfig;
uniform vec2 uFaceShadingConfig;
uniform vec3 uInnerShadowConfig;

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
float uTransmissionGamma = uMaterialConfig.x;
float uVibrancy = uMaterialConfig.y;
float uFaceShadingStrength = uFaceShadingConfig.x;
float uFaceShadingDepth = uFaceShadingConfig.y;
float uInnerShadowStrength = uInnerShadowConfig.x;
float uInnerShadowDepth = uInnerShadowConfig.y;
float uInnerShadowDirectionality = uInnerShadowConfig.z;
float uOuterContourWidth = uOuterContourConfig.x;

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
        uEdgeColor.a < 0.01 &&
        uFaceShadingStrength < 0.001 &&
        uInnerShadowStrength < 0.001
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
        uInnerShadowStrength < 0.001
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
    float faceDepth = max(uFaceShadingDepth, 0.001);
    float faceRise = smoothstep(0.0, faceDepth * 0.35, inwardDistance);
    float faceFall = 1.0 - smoothstep(
        faceDepth * 0.35,
        faceDepth,
        inwardDistance
    );
    // The coordinate-map transform supplies screen-oriented geometry UVs on
    // Metal. Negative projection selects the screen-top, light-facing half for
    // the default upward light.
    float lightSide = smoothstep(
        -lightSupport * 0.08,
        lightSupport * 0.08,
        -dot(facePosition, uLightDirection)
    );
    float faceShading = clamp(
        faceRise * faceFall * lightSide *
        max(uFaceShadingStrength, 0.0),
        0.0,
        1.0
    );
    float innerShadowDepth = max(uInnerShadowDepth, 0.001);
    float innerShadow = clamp(
        (1.0 - smoothstep(0.0, innerShadowDepth, inwardDistance)) *
        max(uInnerShadowStrength, 0.0),
        0.0,
        1.0
    );
    // Preserve the symmetric ambient occlusion at directionality 0, while
    // allowing a configurable fraction to deepen on the light-opposed side.
    // The centered factor keeps the mean shadow strength unchanged instead of
    // turning directionality into an undocumented global intensity control.
    if (uInnerShadowDirectionality > 0.001) {
        float edgeFacingLight = dot(normalXY, uLightDirection);
        float directionalShadowFactor = 1.0 + clamp(
            uInnerShadowDirectionality,
            0.0,
            1.0
        ) * (-edgeFacingLight * 0.5);
        innerShadow = clamp(
            innerShadow * directionalShadowFactor,
            0.0,
            1.0
        );
    }

    // A material contour is evaluated in this pass rather than painted as a
    // separate canvas stroke. That keeps its coverage in the same compositing
    // domain as the specular layer: a highlight can eclipse the dark edge
    // locally, while the contour remains visible on the unlit silhouette.
    float outerContourCoverage = uOuterContourWidth > 0.0
        ? 1.0 - smoothstep(
            0.0,
            max(uOuterContourWidth, 0.001),
            inwardDistance
        )
        : 0.0;
    float outerContourAlpha = clamp(
        outerContourCoverage * uOuterContourColor.a,
        0.0,
        1.0
    );
    // The dark material contour exists around the complete silhouette. The
    // specular reflection is a separate layer above it, so highlights can
    // locally eclipse the contour without punching discontinuities into it.
    // This is both simpler and closer to a coated dielectric than weakening
    // the outline with a hand-authored directional mask.
    float edgeAbsorption = clamp(
        outlineCoverage * uEdgeColor.a,
        0.0,
        1.0
    );
    float edgeTransmittance = 1.0 - edgeAbsorption;
    vec3 result = baseColor * edgeTransmittance +
        uEdgeColor.rgb * edgeAbsorption;
    result *= (1.0 - faceShading) * (1.0 - innerShadow);
    result = mix(result, uOuterContourColor.rgb, outerContourAlpha);
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

    vec4 filterToMatteBasis = texture(uCoordinateTexture, vec2(0.25, 0.5));
    vec2 filterToMatteOffset = texture(uCoordinateTexture, vec2(0.75, 0.5)).xy;
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

    float maxDisplacement = uThickness * 10.0;
    vec2 displacement = decodeDisplacement(geometryData, maxDisplacement);

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
    
    vec3 transmittedColor = pow(
        max(refractColor.rgb, vec3(0.0)),
        vec3(max(uTransmissionGamma, 0.01))
    );
    vec3 materialColor = uGlassColor.rgb * uGlassColor.a;
    transmittedColor *= 1.0 - uGlassColor.a;
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

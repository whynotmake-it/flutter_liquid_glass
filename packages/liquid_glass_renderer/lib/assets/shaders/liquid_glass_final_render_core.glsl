// Copyright 2025, Tim Lehmann for whynotmake.it
//
// Final rendering pass for liquid glass with pre-computed geometry
// This shader reads displacement data from a pre-computed texture and applies
// the liquid glass effect efficiently

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
uniform vec4 uLightingShapeConfig;
uniform vec2 uContourConfig;
uniform vec4 uProfileConfig;
uniform vec2 uMaterialConfig;
uniform vec3 uBevelShadowConfig;
uniform vec2 uAppearanceConfig;
#if SHAPE_APPEARANCE
uniform vec4 uShapeTints[16];
uniform vec4 uShapeAppearances[16];
uniform float uShapeColorModels[16];
#endif

float uDisplacementScale = uOpticalProps.x;
float uChromaticAberration = uOpticalProps.y;
float uThickness = uOpticalProps.z;
float uLightIntensity = uLightConfig.x;
float uBackdropScale = uLightConfig.y;
float uAmbientStrength = 0.0;
float uSaturation = uLightConfig.z;
float uEdgeWidth = uContourConfig.x;
float uContourTransmittance = uContourConfig.y;
float uContourOffset = uProfileConfig.x;
vec2 uMaterialCenter = uProfileConfig.yz;
float uEdgeInset = 0.25;
float uBleedStrength = 0.375;
float uSpecularWrap = uProfileConfig.w;
float uTransmissionGamma = uMaterialConfig.x;
float uVibrancy = uMaterialConfig.y;
float uBevelShadowStrength = uBevelShadowConfig.x;
float uBevelShadowDepth = uBevelShadowConfig.y;
float uBevelShadowOffset = uBevelShadowConfig.z;
float uBevelShadowDirectionality = uLightingShapeConfig.x;
float uBevelShadowSizeResponse = uLightingShapeConfig.y;
float uHighlightWidth = uLightingShapeConfig.z;
float uHighlightOppositeStrength = uLightingShapeConfig.w;

// The fitted/default CA range is below the pixel response of the backdrop
// sampler: the pinned three-scene scan found no score or decoded-image gain
// through |CA| = .01. Bound the fast path by the maximum encoded displacement,
// rather than by CA alone, so a large-refraction surface does not silently lose
// visible dispersion. The threshold is a conservative quarter-pixel total
// red-to-blue spread (an eighth pixel on either side of green).
const float kChromaticAberrationSubpixelThreshold = 0.25;
const float kEdgeFeather = 0.75;
// The contour is reconstructed from a sampled SDF. Test a wider coverage
// transition independently from the encoded exterior range so distance
// decoding and geometry placement remain bit-for-bit unchanged.
const float kContourCoverageFeather = 1.0;

uniform sampler2D uBackgroundTexture;
uniform sampler2D uGeometryTexture;
uniform sampler2D uCoordinateTexture;
#if SHAPE_APPEARANCE
uniform sampler2D uMaterialTexture;
#endif

layout(location = 0) out vec4 fragColor;

#if SHAPE_APPEARANCE
vec4 shapeTint(int index) {
    if (index == 0) return uShapeTints[0];
    if (index == 1) return uShapeTints[1];
    if (index == 2) return uShapeTints[2];
    if (index == 3) return uShapeTints[3];
    if (index == 4) return uShapeTints[4];
    if (index == 5) return uShapeTints[5];
    if (index == 6) return uShapeTints[6];
    if (index == 7) return uShapeTints[7];
    if (index == 8) return uShapeTints[8];
    if (index == 9) return uShapeTints[9];
    if (index == 10) return uShapeTints[10];
    if (index == 11) return uShapeTints[11];
    if (index == 12) return uShapeTints[12];
    if (index == 13) return uShapeTints[13];
    if (index == 14) return uShapeTints[14];
    return uShapeTints[15];
}

vec4 shapeAppearance(int index) {
    if (index == 0) return uShapeAppearances[0];
    if (index == 1) return uShapeAppearances[1];
    if (index == 2) return uShapeAppearances[2];
    if (index == 3) return uShapeAppearances[3];
    if (index == 4) return uShapeAppearances[4];
    if (index == 5) return uShapeAppearances[5];
    if (index == 6) return uShapeAppearances[6];
    if (index == 7) return uShapeAppearances[7];
    if (index == 8) return uShapeAppearances[8];
    if (index == 9) return uShapeAppearances[9];
    if (index == 10) return uShapeAppearances[10];
    if (index == 11) return uShapeAppearances[11];
    if (index == 12) return uShapeAppearances[12];
    if (index == 13) return uShapeAppearances[13];
    if (index == 14) return uShapeAppearances[14];
    return uShapeAppearances[15];
}

float shapeColorModel(int index) {
    if (index == 0) return uShapeColorModels[0];
    if (index == 1) return uShapeColorModels[1];
    if (index == 2) return uShapeColorModels[2];
    if (index == 3) return uShapeColorModels[3];
    if (index == 4) return uShapeColorModels[4];
    if (index == 5) return uShapeColorModels[5];
    if (index == 6) return uShapeColorModels[6];
    if (index == 7) return uShapeColorModels[7];
    if (index == 8) return uShapeColorModels[8];
    if (index == 9) return uShapeColorModels[9];
    if (index == 10) return uShapeColorModels[10];
    if (index == 11) return uShapeColorModels[11];
    if (index == 12) return uShapeColorModels[12];
    if (index == 13) return uShapeColorModels[13];
    if (index == 14) return uShapeColorModels[14];
    return uShapeColorModels[15];
}
#endif

vec4 ios27NeutralTint(float darkWeight) {
    return mix(
        vec4(vec3(253.0, 252.0, 253.0) / 255.0, 0.407),
        vec4(vec3(57.142857 / 255.0), 0.56),
        darkWeight
    );
}

vec3 ios27TintTone(vec3 tint, float backdropLuminance, float darkWeight) {
    float luminance = clamp(backdropLuminance, 0.0, 1.0);
    if (darkWeight < 0.5) {
        float lightScale = 0.76059211 +
            (1.0 - 0.76059211) * pow(luminance, 0.90667748);
        return clamp(
            lightScale * pow(
                max(tint, vec3(0.0)),
                vec3(1.0 + 0.07044432 * (1.0 - luminance))
            ),
            0.0,
            1.0
        );
    }
    float darkFloor = 0.08611765 * pow(
        min(1.0, luminance / 0.62019473),
        1.01150514
    );
    float darkCeiling = 1.0 - 0.01560784 * pow(
        min(1.0, luminance / 0.46837318),
        1.85642966
    );
    return clamp(
        mix(vec3(darkFloor), vec3(darkCeiling), tint),
        0.0,
        1.0
    );
}

float contourExtent() {
    return max(
        kContourCoverageFeather,
        uContourOffset + uEdgeWidth * 0.5 + kContourCoverageFeather
    );
}

float contourCoverage(float signedEdgeDistance) {
    if (uEdgeWidth <= 0.0) {
        return 0.0;
    }
    // Positive contour offsets move the band center outside the mathematical
    // edge, where signedEdgeDistance is negative. This remains attached to
    // the same SDF as refraction and highlights instead of approximating the
    // boundary with a broad canvas shadow.
    float distanceFromContourCenter = abs(
        signedEdgeDistance + uContourOffset
    );
    float halfWidth = uEdgeWidth * 0.5;
    return 1.0 - smoothstep(
        max(halfWidth - kContourCoverageFeather, 0.0),
        halfWidth + kContourCoverageFeather,
        distanceFromContourCenter
    );
}

vec2 mirrorBackgroundUV(vec2 uv, vec2 inverseTextureSize) {
    // Image-filter sampler edge behavior differs between Impeller backends.
    // Preserve every coordinate inside the input texture exactly, and mirror
    // only displaced samples that genuinely leave it. This avoids GLES decal
    // black without clamping Metal samples into stretched edge pixels.
    vec2 mirrored = vec2(1.0) - abs(mod(uv, vec2(2.0)) - vec2(1.0));
    vec2 halfTexel = inverseTextureSize * 0.5;
    return clamp(mirrored, halfTexel, vec2(1.0) - halfTexel);
}

vec2 filterDeltaFromMatteDelta(vec2 matteDelta, vec4 basis) {
    // Invert the live filter->matte affine basis so material-centered source
    // mapping remains stable under ancestor transforms.
    float determinant = basis.x * basis.w - basis.y * basis.z;
    if (abs(determinant) < 1e-6) {
        return vec2(0.0);
    }
    return vec2(
        basis.w * matteDelta.x - basis.y * matteDelta.y,
        -basis.z * matteDelta.x + basis.x * matteDelta.y
    ) / determinant;
}

vec3 applySpecularHighlights(
    vec3 baseColor,
    vec3 transmittedColor,
    float signedEdgeDistance,
    vec2 surfaceNormal
) {
    if (
        uLightIntensity < 0.01 &&
        uAmbientStrength < 0.01 &&
        uContourColor.a < 0.01 &&
        uBevelShadowStrength < 0.001
    ) {
        return baseColor;
    }

    float opticalThickness = max(uThickness, 1.0);
    float inwardDistance = max(signedEdgeDistance, 0.0);
    float configuredHighlightWidth = uHighlightWidth > 0.0
        ? uHighlightWidth
        : uEdgeWidth;
    float edgeWidth = min(
        max(configuredHighlightWidth, 0.0),
        opticalThickness * 0.5
    );
    float highlightInset = edgeWidth * clamp(uEdgeInset, 0.0, 1.0);
    // Flutter runtime-effect shaders do not expose fragment derivatives, even
    // when Impeller is the active renderer. Use a fixed half-pixel feather;
    // this is cheaper than fwidth(), but does not adapt to local scaling.
    float edgeFeather = kEdgeFeather;

    float innerRimMask = edgeWidth > 0.0
        ? smoothstep(
            highlightInset - edgeFeather,
            highlightInset + edgeFeather,
            inwardDistance
        )
        : 1.0;
    float outlineCoverage = contourCoverage(signedEdgeDistance);

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
        uContourColor.a < 0.001 &&
        uBevelShadowStrength < 0.001
    ) {
        return baseColor;
    }

    vec2 normalXY = surfaceNormal;

    // A dielectric rim catches light at both silhouette-facing walls. Use the
    // absolute SDF-normal projection to produce the paired source and return
    // highlights without a second pass. Keeping one smooth envelope avoids
    // the old multiplied-threshold ridge at straight-to-corner transitions.
    float signedLightFacing = dot(normalXY, -uLightDirection);
    float primaryLightFacing = max(signedLightFacing, 0.0);
    float oppositeLightFacing = max(-signedLightFacing, 0.0);

    float wrap = clamp(uSpecularWrap, 0.0, 1.0);
    float wrapCenter = mix(0.96, -0.3, wrap);
    float wrapSoftness = mix(0.04, 0.3, wrap);
    // highlightWrap has one predictable job: choosing how far both highlights
    // travel around the SDF contour.
    float primaryEnvelope = smoothstep(
        wrapCenter - wrapSoftness,
        1.0,
        primaryLightFacing
    );
    float oppositeEnvelope = smoothstep(
        wrapCenter - wrapSoftness,
        1.0,
        oppositeLightFacing
    );
    float specularEnvelope = primaryEnvelope +
        oppositeEnvelope * clamp(uHighlightOppositeStrength, 0.0, 1.0);
    float lightIntensity = max(uLightIntensity, 0.0);
    float highlightMask = specularEnvelope;
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
    // Both branches are uniform across the draw. Disabled lighting layers skip
    // their ALU without introducing fragment divergence, texture samples, or
    // another compositor pass.
    float bevelShadow = 0.0;
    if (uBevelShadowStrength >= 0.001) {
        float configuredBevelDepth = max(uBevelShadowDepth, 0.001);
        float sizeAwareBevelDepth = configuredBevelDepth;
        float surfaceHalfMinor = min(uGeometrySize.x, uGeometrySize.y) * 0.5;
        float sizeProgress = smoothstep(
            configuredBevelDepth * 3.5,
            configuredBevelDepth * 5.0,
            surfaceHalfMinor
        );
        float sizeEnergy = mix(
            1.0,
            1.875,
            sizeProgress * clamp(uBevelShadowSizeResponse, 0.0, 1.0)
        );
        // A bevel occupies proportionally less of a large surface, so its wall
        // contributes more integrated shadow without extending farther into
        // the face. Small controls retain the configured strength; larger
        // surfaces grow smoothly up to 2x. This avoids the broad matte wash
        // produced by globally increasing strength or band depth.
        float shadowOffset = max(uBevelShadowOffset, 0.0);
        shadowOffset = min(
            shadowOffset,
            max(sizeAwareBevelDepth - 0.001, 0.0)
        );
        float bevelLeadingEdge = shadowOffset > 0.001
            ? smoothstep(0.0, shadowOffset, inwardDistance)
            : 1.0;
        float bevelFalloff = 1.0 - smoothstep(
            shadowOffset,
            max(sizeAwareBevelDepth, shadowOffset + 0.001),
            inwardDistance
        );
        float bevelBand = bevelLeadingEdge * bevelFalloff;
        // Remap the signed SDF-normal response across the full contour before
        // applying directionality. Clamping dot() at zero creates a visible
        // half-plane seam whose endpoints project as wedges into circles and
        // blended shapes. The cubic ramp remains strongest on the source-facing
        // wall, reaches zero only opposite the source, and has zero slope at
        // both ends. The highlight is added after this shadow, allowing the
        // bright rim to eclipse the dark wall where they overlap.
        float wrappedLightFacing = smoothstep(
            0.0,
            1.0,
            dot(normalXY, -uLightDirection) * 0.5 + 0.5
        );
        float bevelDirection = mix(
            1.0,
            wrappedLightFacing,
            clamp(uBevelShadowDirectionality, 0.0, 1.0)
        );
        float baseLuminance = dot(
            baseColor,
            vec3(0.2126, 0.7152, 0.0722)
        );
        // Incident shadow remains visible over dark transmitted content, but
        // does not apply a constant wash to it. A fourth-root response matches
        // the black/white wall-energy ratio while remaining exactly zero for
        // a truly black surface and one for white.
        float luminanceResponse = pow(
            clamp(baseLuminance, 0.0, 1.0),
            0.25
        );
        bevelShadow = clamp(
            bevelBand *
                bevelDirection *
                uBevelShadowStrength *
                sizeEnergy *
                luminanceResponse,
            0.0,
            1.0
        );
    }
    // Contour transmittance is evaluated in the material pass, below the
    // specular addition. Highlights therefore eclipse the dark contour
    // naturally without an independent canvas stroke.
    float edgeAbsorption = clamp(
        outlineCoverage * uContourColor.a,
        0.0,
        1.0
    );
    float edgeTransmittance = 1.0 - edgeAbsorption;
    vec3 result = baseColor * edgeTransmittance +
        uContourColor.rgb * edgeAbsorption;
    // Preserve only the configured fraction of the backdrop component. The
    // material/tint emission remains fully affected by contour absorption,
    // which keeps black-probe response independent from transmittance.
    result += transmittedColor *
        edgeAbsorption *
        clamp(uContourTransmittance, 0.0, 1.0);
    result *= 1.0 - bevelShadow;
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
    
    vec4 materialTint = uTint;
    float appearanceVisibility = clamp(uAppearanceConfig.y, 0.0, 1.0);
    float colorModel = uAppearanceConfig.x;
    #if SHAPE_APPEARANCE
    {
        vec2 materialUV =
            (floor(geometryUV * uGeometrySize) + vec2(0.5)) /
            uGeometrySize;
        vec4 contributors = texture(uMaterialTexture, materialUV);
        int primary = int(clamp(
            floor(contributors.r * 16.0),
            0.0,
            15.0
        ));
        int secondary = int(clamp(
            floor(contributors.g * 16.0),
            0.0,
            15.0
        ));
        float primaryWeight = clamp(contributors.b, 0.0, 1.0);
        vec4 secondaryTint = shapeTint(secondary);
        vec4 primaryTint = shapeTint(primary);
        float secondaryWeight = 1.0 - primaryWeight;
        float blendedTintAlpha =
            secondaryTint.a * secondaryWeight +
            primaryTint.a * primaryWeight;
        // Interpolate tint in premultiplied form. Transparent preset tints
        // retain a useful hue for later opacity changes, but that invisible
        // RGB must not leak into an adjacent visible tint during a union.
        vec3 blendedTintPremultiplied =
            secondaryTint.rgb * secondaryTint.a * secondaryWeight +
            primaryTint.rgb * primaryTint.a * primaryWeight;
        vec3 blendedTintColor = blendedTintAlpha > 0.0001
            ? blendedTintPremultiplied / blendedTintAlpha
            : mix(secondaryTint.rgb, primaryTint.rgb, primaryWeight);
        materialTint = vec4(blendedTintColor, blendedTintAlpha);
        vec4 appearance = mix(
            shapeAppearance(secondary),
            shapeAppearance(primary),
            primaryWeight
        );
        appearanceVisibility = clamp(appearance.w, 0.0, 1.0);
        colorModel = mix(
            shapeColorModel(secondary),
            shapeColorModel(primary),
            primaryWeight
        );
        materialTint.a *= appearanceVisibility;
        uSaturation = mix(1.0, appearance.x, appearanceVisibility);
        uTransmissionGamma = mix(
            1.0,
            appearance.y,
            appearanceVisibility
        );
        uVibrancy = appearance.z * appearanceVisibility;
    }
    #endif

    float maxDisplacement = max(uDisplacementScale, 0.001);
    float signedEdgeDistance = decodeSignedEdgeDistance(
        geometryData,
        max(uThickness, 1.0),
        contourExtent()
    );
    float materialAlpha = smoothstep(
        -kEdgeFeather,
        kEdgeFeather,
        signedEdgeDistance
    );
    if (
        materialAlpha < 0.01 &&
        contourCoverage(signedEdgeDistance) * uContourColor.a < 0.01
    ) {
        fragColor = vec4(0.0);
        return;
    }
    vec2 displacement =
        decodeDisplacement(geometryData, maxDisplacement) *
        appearanceVisibility;
    vec2 surfaceNormal = decodeSurfaceNormal(geometryData);

    vec2 invUSize = 1.0 / uSize;
    vec2 backdropScaleOffset = vec2(0.0);
    if (abs(uBackdropScale - 1.0) > 0.0001) {
        // Treat face scaling and edge refraction as one source-coordinate
        // mapping. The scale is exactly identity at the mathematical contour,
        // then approaches the requested face scale continuously without a
        // clipped cutoff. Complementing the actual displacement field lets
        // edge refraction own the optical wall for every SDF/blended shape.
        float inwardDistance = max(signedEdgeDistance, 0.0);
        float transitionDepth = max(uThickness * 0.25, 1.0);
        float inwardDistanceSquared = inwardDistance * inwardDistance;
        float transitionDepthSquared = transitionDepth * transitionDepth;
        float distanceWeight =
            inwardDistanceSquared /
            (inwardDistanceSquared + transitionDepthSquared);
        float displacementRatio = clamp(
            length(displacement) / maxDisplacement,
            0.0,
            1.0
        );
        float refractionComplement =
            1.0 - smoothstep(0.0, 1.0, displacementRatio);
        float scaleWeight = distanceWeight * refractionComplement;
        vec2 filterDeltaFromCenter = filterDeltaFromMatteDelta(
            matteCoord - uMaterialCenter,
            filterToMatteBasis
        );
        float backdropScale = clamp(uBackdropScale, 0.25, 4.0);
        backdropScaleOffset =
            filterDeltaFromCenter *
            (1.0 / backdropScale - 1.0) *
            scaleWeight;
    }
    vec4 refractColor;
    // Skip two texture reads only when the maximum channel separation is
    // subpixel. The uniform predicate stays coherent across the layer and the
    // displacement bound keeps this optimization valid for either CA sign.
    if (
        abs(uChromaticAberration) * maxDisplacement <=
        kChromaticAberrationSubpixelThreshold
    ) {
        vec2 refractedUV = mirrorBackgroundUV(
            screenUV + (backdropScaleOffset + displacement) * invUSize,
            invUSize
        );
        refractColor = texture(uBackgroundTexture, refractedUV);
    } else {
        float dispersionStrength = uChromaticAberration * 0.5;
        vec2 redOffset = displacement * (1.0 + dispersionStrength);
        vec2 blueOffset = displacement * (1.0 - dispersionStrength);
        
        vec2 redUV = mirrorBackgroundUV(
            screenUV + (backdropScaleOffset + redOffset) * invUSize,
            invUSize
        );
        vec2 greenUV = mirrorBackgroundUV(
            screenUV + (backdropScaleOffset + displacement) * invUSize,
            invUSize
        );
        vec2 blueUV = mirrorBackgroundUV(
            screenUV + (backdropScaleOffset + blueOffset) * invUSize,
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
    vec3 baseColor;
    if (colorModel < 0.5) {
        vec3 materialColor = materialTint.rgb * materialTint.a;
        transmittedColor *= 1.0 - materialTint.a;
        baseColor = materialColor + transmittedColor;
        baseColor = applySaturation(baseColor, uSaturation);
        float chroma = max(max(baseColor.r, baseColor.g), baseColor.b) -
            min(min(baseColor.r, baseColor.g), baseColor.b);
        baseColor = clamp(
            baseColor + vec3(chroma * max(uVibrancy, 0.0)),
            0.0,
            1.0
        );
    } else {
        // Apple's public tint is not a flat source-over wash. Its documented
        // "range of tones" is selected from backdrop brightness, while tint
        // opacity linearly mixes that opaque tonal result with the untinted
        // material. The six native solid-palette captures in the harness
        // validate both properties. This adds no backdrop read or extra pass.
        float darkWeight = clamp(colorModel - 1.0, 0.0, 1.0);
        vec4 neutralTint = ios27NeutralTint(darkWeight);
        vec3 neutralTransmission = transmittedColor * (1.0 - neutralTint.a);
        vec3 neutralBase = neutralTint.rgb * neutralTint.a +
            neutralTransmission;
        neutralBase = applySaturation(neutralBase, uSaturation);
        float neutralChroma =
            max(max(neutralBase.r, neutralBase.g), neutralBase.b) -
            min(min(neutralBase.r, neutralBase.g), neutralBase.b);
        neutralBase = clamp(
            neutralBase + vec3(neutralChroma * max(uVibrancy, 0.0)),
            0.0,
            1.0
        );
        baseColor = neutralBase;
        if (materialTint.a >= 0.001) {
            vec3 tintTone = ios27TintTone(
                materialTint.rgb,
                dot(refractColor.rgb, LUMA_WEIGHTS),
                darkWeight
            );
            baseColor = mix(neutralBase, tintTone, materialTint.a);
        }
        transmittedColor = neutralTransmission * (1.0 - materialTint.a);
    }

    // Reconstruct the original material silhouette from the signed SDF. The
    // geometry alpha is only an expanded support mask, allowing the attached
    // contour to sit outside without turning those pixels into glass.
    vec3 finalColor = applySpecularHighlights(
        baseColor,
        transmittedColor,
        signedEdgeDistance,
        surfaceNormal
    );
    // Inside the material, contour absorption is handled before highlights so
    // specular light can eclipse it. Only the part outside the material is
    // composited as a translucent attached boundary.
    float visibleMaterialAlpha = materialAlpha * appearanceVisibility;
    float externalContourAlpha =
        contourCoverage(signedEdgeDistance) *
        uContourColor.a *
        (1.0 - materialAlpha) *
        appearanceVisibility;
    float alpha = visibleMaterialAlpha + externalContourAlpha;
    vec3 premultipliedColor = finalColor * visibleMaterialAlpha +
        uContourColor.rgb * externalContourAlpha;

    fragColor = vec4(premultipliedColor, alpha);
}

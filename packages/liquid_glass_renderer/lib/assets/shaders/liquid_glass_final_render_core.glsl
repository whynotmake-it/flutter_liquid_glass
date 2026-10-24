// Copyright 2025, Tim Lehmann for whynotmake.it
//
// Final rendering pass for liquid glass with pre-computed geometry
// This shader reads the smooth low-resolution geometry field (edge distance,
// normal, half short side) and applies the liquid glass effect efficiently

// Refraction is evaluated in global filter coordinates. Keep the affine
// mapping and sub-pixel displacement in high precision on GLES; mediump turns
// the coordinate subtraction into visible shimmer on large layers.
precision highp float;

#include <flutter/runtime_effect.glsl>
#include "render.glsl"

// The geometry texture is a smooth RGBA16F field on a lattice of one texel per
// uLowResMatte.x matte pixels (see gpu/geometry_fragment.glsl), read through one
// hardware-filtered fetch (the renderer binds the geometry sampler with linear
// filtering). The edge, normal and displacement are rebuilt from it per pixel.

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
uniform vec3 uContourConfig;
uniform vec4 uProfileConfig;
uniform vec3 uMaterialConfig;
uniform vec3 uBevelShadowConfig;
uniform vec3 uAppearanceConfig;
uniform vec4 uFilterToMatteBasis;
uniform vec2 uFilterToMatteOffset;
// 1.0 lets material alpha cross-fade the frost away, and the rest of the
// material with it; 0.0 keeps unfrosted glass opaque and cross-fades the
// material to the refracted backdrop instead, so visibility 0 is an exact
// identity of the backdrop.
uniform float uBlurFade;
// Matte-space rect (LTRB, device px) the filter captured backdrop for.
// Outside it the filter input is transparent or clamped, so displaced samples
// are mirrored back in at its edge.
uniform vec4 uBackdropBounds;
// Unused by the field; kept so the float layout of the uniforms below does not
// move. uGeometrySize is the matte's size in device px.
uniform vec2 uGeometryUVScale;
// Texel size of the material map's texture; the map fills its top-left.
uniform vec2 uMaterialTextureSize;

// Per-model parameter blocks for the three adaptive color-model slots the
// layer assigned this frame: slot code 1..3 selects
// uColorModelParams[(code - 1) * 6 .. code * 6 - 1]. Packing, mirrored from
// GlassColorParameters.toShaderParameters:
//   +0: emissionColor.rgb,           emissionAlpha.clear
//   +1: emissionAlpha.tinted,        transmittance.clear,
//       transmittance.tinted,        contourResponse
//   +2: luminanceLift c/t,           chromaGain c/t
//   +3: toneLow   (base, amplitude, pivot, exponent)
//   +4: toneHigh  (base, amplitude, pivot, exponent)
//   +5: toneGammaLuminance, glintLuminance, glintFaceGain, glintVibrancy
uniform vec4 uColorModelParams[18];

// Declared last (float index 133).
//   uLowResMatte:  matte pixels per lattice texel, then the lattice texture's
//                  size in texels.
//   uLowResOptics: refraction height in px and whether refraction fits the
//                  shape (the geometry pass's two bevel inputs).
uniform vec4 uLowResMatte;
uniform vec2 uLowResOptics;

vec4 colorModelSlot(int slot, int field) {
    return uColorModelParams[slot * 6 + field];
}

float uDisplacementScale = uOpticalProps.x;
float uDispersion = uOpticalProps.y;
// Rim lighting depth.
float uThickness = uOpticalProps.z;
float uLightIntensity = uLightConfig.x;
float uBackdropScale = uLightConfig.y;
float uSaturation = uLightConfig.z;
float uEdgeWidth = uContourConfig.x;
float uContourTransmittance = uContourConfig.y;
float uContourDirectionality = uContourConfig.z;
float uContourOffset = uProfileConfig.x;
vec2 uMaterialCenter = uProfileConfig.yz;
float uSpecularWrap = uProfileConfig.w;
float uTransmissionGamma = uMaterialConfig.x;
float uVibrancy = uMaterialConfig.y;
// iOS 27 Liquid Glass slider: 0 = Clear, 1 = Tinted.
float uTintAmount = clamp(uMaterialConfig.z, 0.0, 1.0);
float uBevelShadowStrength = uBevelShadowConfig.x;
float uBevelShadowDepth = uBevelShadowConfig.y;
float uBevelShadowOffset = uBevelShadowConfig.z;
float uBevelShadowDirectionality = uLightingShapeConfig.x;
float uBevelShadowSizeResponse = uLightingShapeConfig.y;
float uHighlightWidth = uLightingShapeConfig.z;
float uHighlightOppositeStrength = uLightingShapeConfig.w;

// The fitted/default CA range is below the pixel response of the backdrop
// sampler: the pinned three-scene scan found no score or decoded-image gain
// through |CA| = .01. Bound the fast path by the maximum displacement,
// rather than by CA alone, so a large-refraction surface does not silently lose
// visible dispersion. The threshold is a conservative quarter-pixel total
// red-to-blue spread (an eighth pixel on either side of green).
const float kDispersionSubpixelThreshold = 0.25;
// Border strength; the dark iOS 27 face raises it with the slider.
float gContourAlpha = uContourColor.a;
// iOS 27 glint recolor, measured on the pinned solid-palette probes in both
// appearances: the glint mixes the lit face toward a bright target whose
// luminance sits above SDR white and whose chroma is the face chroma
// amplified. The simulator captures give a mix weight of 0.14; an iPhone
// renders the same glass 1.8x stronger, so highlight = 1 matches the device.
const float kGlintLuminance = 1.6;
const float kGlintVibrancy = 2.85;
const float kGlintPeak = 0.252;
// A faint inward bleed four glint widths deep carries a fifth of the line's
// weight.
const float kGlintBleed = 0.21;
const float kGlintBleedReach = 4.0;
// The glint target is Lh + faceGain * face + vibrancy * face chroma. Regular
// glass pulls toward a fixed bright target; clear glass instead brightens
// its own face. Set per color model in main().
float gGlintLuminance = kGlintLuminance;
float gGlintFaceGain = 0.0;
float gGlintVibrancy = kGlintVibrancy;
// The contour is reconstructed from a sampled SDF. Test a wider coverage
// transition independently from the encoded exterior range so distance
// decoding and geometry placement remain bit-for-bit unchanged.
const float kContourCoverageFeather = 1.0;

uniform sampler2D uBackgroundTexture;
uniform sampler2D uGeometryTexture;
#if SHAPE_APPEARANCE || SHAPE_TINT
uniform sampler2D uMaterialTexture;
#endif
#if SHAPE_APPEARANCE
uniform sampler2D uMaterialLinearTexture;
#endif

layout(location = 0) out vec4 fragColor;

#if SHAPE_APPEARANCE
vec4 shapeLookup(
    int index,
    vec2 materialTextureSize,
    float rowCenter
) {
    return texture(
        uMaterialTexture,
        vec2(
            (float(index) + 0.5) / materialTextureSize.x,
            rowCenter / materialTextureSize.y
        )
    );
}
#endif

// Transmittance of one model's face, blended linearly between the Clear and
// Tinted slider endpoints. The dark model's transmittance is size-independent.
float parametricTransmittance(int slot, float tintAmount) {
    vec4 transmittance = colorModelSlot(slot, 1);
    return mix(transmittance.y, transmittance.z, tintAmount);
}

// Neutral wash of one model's untinted face: premultiplied emission over
// the wash's opacity, the complement of its transmittance.
vec4 parametricNeutralTint(int slot, float tintAmount) {
    float transmittance = parametricTransmittance(slot, tintAmount);
    vec4 emission = colorModelSlot(slot, 0);
    vec4 response = colorModelSlot(slot, 1);
    float alpha = 1.0 - transmittance;
    float emissionAlpha = mix(emission.w, response.x, tintAmount);
    return vec4(
        emission.rgb * emissionAlpha / max(alpha, 1e-4),
        alpha
    );
}

// Luminance lift and chroma gain of one model's untinted face.
vec2 parametricFaceTransfer(int slot, float tintAmount) {
    vec4 liftChroma = colorModelSlot(slot, 2);
    return vec2(
        mix(liftChroma.x, liftChroma.y, tintAmount),
        mix(liftChroma.z, liftChroma.w, tintAmount)
    );
}

// The brightness-mapped range of tint tones of one model, evaluated per
// channel as clamp(lo + (hi - lo) * tint^gamma) where lo and hi are
// luminance ramps base + amplitude * (min(1, Y / pivot))^exponent and the
// gamma is 1 + toneGammaLuminance * (1 - Y).
vec3 parametricTintTone(int slot, vec3 tint, float backdropLuminance) {
    float luminance = clamp(backdropLuminance, 0.0, 1.0);
    vec4 low = colorModelSlot(slot, 3);
    vec4 high = colorModelSlot(slot, 4);
    vec4 misc = colorModelSlot(slot, 5);
    float floor_ = low.x + low.y * pow(
        min(1.0, luminance / max(low.z, 1e-6)),
        low.w
    );
    float ceiling = high.x + high.y * pow(
        min(1.0, luminance / max(high.z, 1e-6)),
        high.w
    );
    return clamp(
        vec3(floor_) + (vec3(ceiling) - floor_) * pow(
            max(tint, vec3(0.0)),
            vec3(1.0 + misc.x * (1.0 - luminance))
        ),
        0.0,
        1.0
    );
}

// Glint target parameters of one model: luminance, face gain, vibrancy.
vec3 parametricGlint(int slot) {
    return colorModelSlot(slot, 5).yzw;
}

// How strongly a model's border follows the opacity the slider adds.
float parametricContourResponse(int slot) {
    return colorModelSlot(slot, 1).w;
}

// Shares of a color model code: direct (0) plus the layer's three model
// slots (1..3). Merged shapes blend these shares rather than the codes, so
// a merge between two adaptive models does not pass through direct.
vec4 colorModelSharesOf(float code) {
    return vec4(
        code < 0.5 ? 1.0 : 0.0,
        abs(code - 1.0) < 0.5 ? 1.0 : 0.0,
        abs(code - 2.0) < 0.5 ? 1.0 : 0.0,
        code > 2.5 ? 1.0 : 0.0
    );
}

// The dark border starts at the silhouette (shifted outward by
// contourOffset) and fades linearly outward over contourWidth. It is often
// narrower than a pixel, so it is box-filtered over the same one-pixel
// footprint as the silhouette instead of being point-sampled, which would
// alias into a dotted line along curves. This is the ramp's integral from
// the silhouette to outward distance t.
float contourIntegral(float t) {
    float u = clamp(t - uContourOffset, 0.0, uEdgeWidth);
    return u - u * u / (2.0 * uEdgeWidth);
}

// Border coverage of the pixel, split at the silhouette: x lies outside the
// material and is composited over the backdrop, y lies inside it.
vec2 contourCoverage(float signedEdgeDistance) {
    if (uEdgeWidth <= 0.0) {
        return vec2(0.0);
    }
    float outward = -signedEdgeDistance;
    float lower = outward - 0.5;
    float upper = outward + 0.5;
    return vec2(
        contourIntegral(max(upper, 0.0)) - contourIntegral(max(lower, 0.0)),
        contourIntegral(min(upper, 0.0)) - contourIntegral(min(lower, 0.0))
    );
}

// The fraction of the normal perpendicular to the light axis. The glint
// lives where it is zero; the dark border concentrates where it is one.
float lightAxisTangency(vec2 surfaceNormal) {
    return abs(dot(surfaceNormal, vec2(-uLightDirection.y, uLightDirection.x)));
}

float contourDirection(vec2 surfaceNormal) {
    return mix(
        1.0,
        lightAxisTangency(surfaceNormal),
        clamp(uContourDirectionality, 0.0, 1.0)
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

vec2 mirrorIntoBackdrop(vec2 sourceOffset, vec2 matteCoord) {
    vec2 sampleMatte = matteCoord + vec2(
        dot(uFilterToMatteBasis.xy, sourceOffset),
        dot(uFilterToMatteBasis.zw, sourceOffset)
    );
    // Keep bilinear footprints off the uncaptured side of the edge.
    float margin = 0.5;
    vec2 lo = uBackdropBounds.xy + margin;
    vec2 hi = uBackdropBounds.zw - margin;
    if (all(greaterThanEqual(sampleMatte, lo)) &&
        all(lessThanEqual(sampleMatte, hi))) {
        return sourceOffset;
    }
    vec2 extent = max(hi - lo, vec2(0.0));
    vec2 mirrored = lo + extent - abs(extent - abs(sampleMatte - lo));
    mirrored = clamp(mirrored, lo, max(hi, lo));
    return sourceOffset + filterDeltaFromMatteDelta(
        mirrored - sampleMatte,
        uFilterToMatteBasis
    );
}

// Transmitted part of the untinted adaptive face for one backdrop color.
vec3 neutralTransmissionOf(
    vec3 backdrop,
    float backdropLuminance,
    vec2 faceTransfer,
    float neutralAlpha
) {
    float lifted = clamp(
        backdropLuminance *
            (1.0 + faceTransfer.x * (1.0 - backdropLuminance)),
        0.0,
        1.0
    );
    float transmittedLuminance = pow(lifted, max(uTransmissionGamma, 0.01));
    return vec3(transmittedLuminance * (1.0 - neutralAlpha)) +
        (backdrop - vec3(backdropLuminance)) *
            (faceTransfer.y * uSaturation);
}

// Distance inward from the silhouette, in device px, beyond which
// applySpecularHighlights and the contour contribute exactly nothing, so the
// lit color is the base color and the exterior border is absent. Every term
// is a uniform expression; a block whose strength is zero adds no reach.
// Conservative: it may only be larger than the true reach, never smaller.
float rimReach() {
    float reach = -1.0e9;
    if (uLightIntensity > 0.0) {
        // glintProfile reaches zero at glintWidth * kGlintBleedReach.
        float glintWidth = max(
            uHighlightWidth > 0.0 ? uHighlightWidth : uEdgeWidth,
            0.001
        );
        reach = max(reach, glintWidth * kGlintBleedReach);
    }
    if (gContourAlpha > 0.0 && uEdgeWidth > 0.0) {
        // contourCoverage is zero on both sides of the silhouette from here.
        reach = max(reach, 0.5 - uContourOffset);
    }
    if (uBevelShadowStrength >= 0.001) {
        // The band is gone once inward - shift >= depth; the shift is at most
        // the offset. A small margin keeps smoothstep exactly saturated.
        reach = max(
            reach,
            (max(uBevelShadowDepth, 0.001) + max(uBevelShadowOffset, 0.0)) *
                1.001 + 0.01
        );
    }
    return reach;
}

vec3 applySpecularHighlights(
    vec3 baseColor,
    vec3 transmittedColor,
    float signedEdgeDistance,
    vec2 surfaceNormal
) {
    if (
        uLightIntensity < 0.01 &&
        gContourAlpha < 0.01 &&
        uBevelShadowStrength < 0.001
    ) {
        return baseColor;
    }

    float inwardDistance = max(signedEdgeDistance, 0.0);
    float glintWidth = max(
        uHighlightWidth > 0.0 ? uHighlightWidth : uEdgeWidth,
        0.001
    );
    // In-material share of the border, relative to the material's coverage.
    float outlineCoverage = contourCoverage(signedEdgeDistance).y /
        max(clamp(signedEdgeDistance + 0.5, 0.0, 1.0), 0.001);
    // The glint is a thin line anchored at the silhouette with a faint
    // inward bleed. Both are linear ramps in logical distance, so the line
    // stays crisp at every size and scale factor.
    float glintProfile =
        clamp(1.0 - inwardDistance / glintWidth, 0.0, 1.0) +
        kGlintBleed * clamp(
            1.0 - inwardDistance / (glintWidth * kGlintBleedReach),
            0.0,
            1.0
        );

    if (
        outlineCoverage < 0.01 &&
        glintProfile < 0.001 &&
        uBevelShadowStrength < 0.001
    ) {
        return baseColor;
    }

    vec2 normalXY = surfaceNormal;

    // Both walls along the light axis catch the glint; it fades linearly
    // with the normal's tangential component. highlightWrap = 0.5 is the
    // linear falloff measured on iOS 27; lower values narrow the lobes and
    // higher values carry them further around corners.
    float wrapExponent = exp2(2.0 - 4.0 * clamp(uSpecularWrap, 0.0, 1.0));
    float axisAlignment = 1.0 - lightAxisTangency(normalXY);
    float lobe = pow(max(axisAlignment, 0.0), wrapExponent);
    float returnWeight = dot(normalXY, -uLightDirection) >= 0.0
        ? 1.0
        : clamp(uHighlightOppositeStrength, 0.0, 1.0);
    float glint = clamp(
        max(uLightIntensity, 0.0) * kGlintPeak * lobe * returnWeight *
            glintProfile,
        0.0,
        1.0
    );
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
        // The raised rim shades the face like a wall lit along the light
        // axis: its band is displaced by the offset along the light. Below
        // the lit wall it falls inside the face, along the sides it starts
        // at the rim, and below the far wall it is pushed out past the rim.
        // The penumbra is as wide as the displacement.
        float lightFacing = dot(normalXY, -uLightDirection);
        float shadowShift = max(uBevelShadowOffset, 0.0) * lightFacing;
        float penumbra = 2.0 * shadowShift;
        float bevelLeadingEdge = penumbra > 0.001
            ? smoothstep(0.0, penumbra, inwardDistance)
            : 1.0;
        float bevelFalloff = 1.0 - smoothstep(
            0.0,
            sizeAwareBevelDepth,
            inwardDistance - shadowShift
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
            lightFacing * 0.5 + 0.5
        );
        float bevelDirection = mix(
            1.0,
            wrappedLightFacing,
            clamp(uBevelShadowDirectionality, 0.0, 1.0)
        );
        bevelShadow = clamp(
            bevelBand *
                bevelDirection *
                uBevelShadowStrength *
                sizeEnergy,
            0.0,
            1.0
        );
    }
    // The border absorbs the transmitted backdrop only where the material
    // still overlaps it; its exterior part is composited in main().
    float edgeAbsorption = clamp(
        outlineCoverage * gContourAlpha * contourDirection(normalXY),
        0.0,
        1.0
    );
    vec3 result = baseColor * (1.0 - edgeAbsorption) +
        uContourColor.rgb * edgeAbsorption +
        transmittedColor * edgeAbsorption *
            clamp(uContourTransmittance, 0.0, 1.0);
    // The shadow absorbs only light that came through the glass: the wash
    // emits the same over any backdrop, so over black the face is unshaded.
    result = max(
        result - transmittedColor * (1.0 - edgeAbsorption) * bevelShadow,
        vec3(0.0)
    );
    // The glint recolors the lit face rather than adding white: it pulls
    // luminance toward a target above SDR white and amplifies the face's own
    // chroma, so glass over color glints in that color.
    float resultLuminance = dot(result, LUMA_WEIGHTS);
    vec3 glintTarget = uHighlightColor.rgb * gGlintLuminance +
        result * gGlintFaceGain +
        (result - vec3(resultLuminance)) * gGlintVibrancy;
    // Only the lower bound is clamped: amplified chroma must not produce
    // negative (out-of-gamut) channels, while the upper side keeps its
    // headroom above SDR white for extended-range surfaces.
    result = max(mix(result, glintTarget, glint), vec3(0.0));

    return result;
}


// Interpolated normal vectors shorter than this have been averaged across a
// crease (the field stores unit directions scaled by a factor that is 1 almost
// everywhere).
const float kLowResCreaseLength = 0.5;

// Surface normal (xy) and refraction shortening factor (z) from one filtered
// fetch. The field holds the unit optical normal scaled by the factor, so the
// interpolated vector's direction is the normal and its length the factor
// (slightly shortened where neighbouring directions disagree, as around a
// tight corner). Across a crease (the medial axis of a thin shape) the two
// sides cancel and the direction is arbitrary: where the vector is short, take
// the nearest texel instead, one extra fetch for the thin line of pixels
// where it happens.
vec3 lowResNormalFiltered(vec4 field, vec2 node) {
    vec2 sum = field.yz;
    float sumLength = length(sum);
    if (sumLength < kLowResCreaseLength) {
        vec2 nearestUV =
            (floor(node + 0.5) + 0.5) / uLowResMatte.yz;
        sum = texture(uGeometryTexture, nearestUV).yz;
        sumLength = length(sum);
    }
    return vec3(
        sumLength > 0.0001 ? sum / sumLength : vec2(0.0),
        sumLength
    );
}

// The geometry pass's refraction profile, evaluated at one pixel instead of
// read back from the matte: a flat face with a quarter-circle bevel whose
// size follows the shape's half short side. Returns the displacement along
// the inward normal, positive, in px.
float lowResDisplacementMagnitude(
    float inward,
    float halfMinor,
    float shortening
) {
    float refractionHeight = uLowResOptics.x;
    float refractionAmount = max(uDisplacementScale, 0.001);
    float bevel;
    float amount;
    if (uLowResOptics.y > 0.5) {
        // iOS 27 regular glass: the bevel spans at most half of the half
        // short side and the rim samples no deeper than the center line.
        bevel = min(refractionHeight, 0.5 * halfMinor);
        amount = min(refractionAmount, halfMinor);
    } else {
        // Clear glass keeps its lens until the bevel would pass the center
        // line, then scales the whole lens so displacement never flips there.
        float lensScale = min(1.0, halfMinor / max(refractionHeight, 0.001));
        bevel = refractionHeight * lensScale;
        amount = refractionAmount * lensScale;
    }
    float bevelX = 1.0 - clamp(max(inward, 0.0) / max(bevel, 0.001), 0.0, 1.0);
    float magnitude = bevel > 0.001
        ? amount * (1.0 - sqrt(1.0 - bevelX * bevelX)) * shortening
        : 0.0;
    return clamp(magnitude, 0.0, refractionAmount);
}

void main() {
    // Map image-filter fragment coordinates back into the layer-local geometry
    // matte. Apple Metal surfaces expose global filter coordinates, while
    // other backends may expose clip-local coordinates. These uniforms are
    // snapshotted with the frame, never overwritten through a shared texture.
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 screenUV = fragCoord / uSize;

    vec2 matteCoord = vec2(
        dot(uFilterToMatteBasis.xy, fragCoord),
        dot(uFilterToMatteBasis.zw, fragCoord)
    ) + uFilterToMatteOffset;
    vec2 geometryUV = (matteCoord - uGeometryOffset) / uGeometrySize;

    if (
        any(lessThan(geometryUV, vec2(0.0))) ||
        any(greaterThan(geometryUV, vec2(1.0)))
    ) {
        fragColor = vec4(0.0);
        return;
    }

    // Texel (i, j) is evaluated at the center of matte pixel (i, j) * scale
    // (kLatticePhase in geometry_fragment.glsl).
    vec2 lowResNode =
        (matteCoord - uGeometryOffset - 0.5) / uLowResMatte.x;
    // One filtered fetch: the sampler interpolates the four texels around
    // this fragment. Its edge clamp stands in for clamping the lattice, and
    // the texture holds the texel past the last matte pixel.
    vec4 lowResField = texture(
        uGeometryTexture,
        (lowResNode + 0.5) / uLowResMatte.yz
    );
    vec4 materialTint = uTint;
    float appearanceVisibility = clamp(uAppearanceConfig.y, 0.0, 1.0);
    // Weight of the material over the refracted backdrop. Frosted glass
    // renders the material in full and its alpha fades it with the frost;
    // opaque unfrosted glass fades it here. Either way it fades linearly,
    // never twice.
    float materialVisibility = mix(appearanceVisibility, 1.0, uBlurFade);
    vec4 colorModelShares = colorModelSharesOf(uAppearanceConfig.x);
    #if SHAPE_TINT
    {
        float materialRasterScale = max(uAppearanceConfig.z, 1.0);
        vec2 materialSize = max(
            ceil(uGeometrySize / materialRasterScale),
            vec2(1.0)
        );
        vec2 materialTextureSize = uMaterialTextureSize;
        vec2 materialLinearUV =
            (geometryUV * (materialSize - vec2(1.0)) + vec2(0.5)) /
            materialTextureSize;
        materialTint = texture(uMaterialTexture, materialLinearUV);
    }
    #elif SHAPE_APPEARANCE
    {
        float materialRasterScale = max(uAppearanceConfig.z, 1.0);
        vec2 materialSize = max(
            ceil(uGeometrySize / materialRasterScale),
            vec2(1.0)
        );
        vec2 materialTextureSize = uMaterialTextureSize;
        vec2 materialNearestUV =
            (floor(geometryUV * materialSize) + vec2(0.5)) /
            materialTextureSize;
        vec2 materialLinearUV =
            (geometryUV * (materialSize - vec2(1.0)) + vec2(0.5)) /
            materialTextureSize;
        // Keep contributor IDs discrete, while bilinearly upsampling only the
        // transition weight. Pair changes are allowed to be approximate: this
        // map is a transient tint gradient, never the geometry matte.
        vec4 contributors = texture(uMaterialTexture, materialNearestUV);
        vec4 filtered = texture(uMaterialLinearTexture, materialLinearUV);
        float primaryWeight = clamp(filtered.b, 0.0, 1.0);
        // Where the nearest shape swaps, the filtered footprint holds one
        // pair in both orders: the IDs differ but their sum does not. The
        // nearest-shape weight never reaches 0.5 there, so use the weight
        // stored for the pair's lower-indexed shape instead.
        const float kIdTolerance = 0.5 / 255.0;
        if (
            abs(filtered.r - contributors.r) > kIdTolerance &&
            abs(
                filtered.r + filtered.g - contributors.r - contributors.g
            ) < kIdTolerance
        ) {
            float lowerWeight = clamp(filtered.a, 0.0, 1.0);
            primaryWeight = contributors.r <= contributors.g
                ? lowerWeight
                : 1.0 - lowerWeight;
        }
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
        float secondaryWeight = 1.0 - primaryWeight;
        vec4 primaryTint = shapeLookup(
            primary,
            materialTextureSize,
            materialSize.y + 0.5
        );
        vec4 secondaryTint = shapeLookup(
            secondary,
            materialTextureSize,
            materialSize.y + 0.5
        );
        vec4 primaryResponse = shapeLookup(
            primary,
            materialTextureSize,
            materialSize.y + 1.5
        );
        vec4 secondaryResponse = shapeLookup(
            secondary,
            materialTextureSize,
            materialSize.y + 1.5
        );
        primaryResponse.xyz *= 4.0;
        secondaryResponse.xyz *= 4.0;
        float primaryPackedResponse = primaryResponse.w * 7.0;
        float secondaryPackedResponse = secondaryResponse.w * 7.0;
        float primaryColorModel = floor(primaryPackedResponse * 0.5);
        float secondaryColorModel = floor(secondaryPackedResponse * 0.5);
        primaryResponse.w = primaryPackedResponse - primaryColorModel * 2.0;
        secondaryResponse.w =
            secondaryPackedResponse - secondaryColorModel * 2.0;
        float blendedTintAlpha =
            secondaryTint.a * secondaryWeight +
            primaryTint.a * primaryWeight;
        vec3 blendedTintPremultiplied =
            secondaryTint.rgb * secondaryTint.a * secondaryWeight +
            primaryTint.rgb * primaryTint.a * primaryWeight;
        vec3 blendedTintColor = blendedTintAlpha > 0.0001
            ? blendedTintPremultiplied / blendedTintAlpha
            : mix(secondaryTint.rgb, primaryTint.rgb, primaryWeight);
        materialTint = vec4(blendedTintColor, blendedTintAlpha);
        vec4 appearance = mix(
            secondaryResponse,
            primaryResponse,
            primaryWeight
        );
        appearanceVisibility = clamp(appearance.w, 0.0, 1.0);
        colorModelShares = mix(
            colorModelSharesOf(secondaryColorModel),
            colorModelSharesOf(primaryColorModel),
            primaryWeight
        );
        materialVisibility = mix(appearanceVisibility, 1.0, uBlurFade);
        uSaturation = appearance.x;
        uTransmissionGamma = appearance.y;
        uVibrancy = appearance.z;
    }
    #endif

    float maxDisplacement = max(uDisplacementScale, 0.001);
    // Positive inside; continuous rather than a companded byte, so the
    // antialiased edge below stays one pixel wide at any lattice scale.
    float signedEdgeDistance = lowResField.x;
    // Box-filtered coverage of one physical pixel, as Core Animation
    // rasterizes the silhouette: a pixel-aligned edge stays hard, so the
    // glint's first row is not diluted by a wider feather.
    float materialAlpha = clamp(signedEdgeDistance + 0.5, 0.0, 1.0);
    if (
        materialAlpha < 0.01 &&
        contourCoverage(signedEdgeDistance).x * gContourAlpha < 0.01
    ) {
        fragColor = vec4(0.0);
        return;
    }
    // The normal is only derived (a normalize) where something consumes it:
    // pixels beyond the refraction profile have a zero magnitude, and the rim
    // effects need the normal only near the edge.
    vec2 surfaceNormal = vec2(0.0);
    bool hasSurfaceNormal = false;
    vec2 displacement = vec2(0.0);
    // The bevel never reaches deeper than the refraction height, so the
    // half short side, the normal and the profile are only needed within it.
    if (signedEdgeDistance < uLowResOptics.x) {
        float lowResHalfMinor = lowResField.w;
        vec3 lowResSurface = lowResNormalFiltered(lowResField, lowResNode);
        float magnitude = lowResDisplacementMagnitude(
            signedEdgeDistance,
            lowResHalfMinor,
            lowResSurface.z
        );
        if (magnitude > 0.0) {
            surfaceNormal = lowResSurface.xy;
            hasSurfaceNormal = true;
            displacement = surfaceNormal * (-magnitude) * appearanceVisibility;
        }
    }

    vec2 invUSize = 1.0 / uSize;
    vec2 backdropScaleOffset = vec2(0.0);
    if (abs(uBackdropScale - 1.0) > 0.0001) {
        // backdropShrink is one lens over the whole face, about the material
        // center of the layer, uniform up to the silhouette. The bevel
        // displacement adds on top of it. It never enlarges: magnifiers
        // re-render their content instead (see the example's loupe).
        vec2 filterDeltaFromCenter = filterDeltaFromMatteDelta(
            matteCoord - uMaterialCenter,
            uFilterToMatteBasis
        );
        float magnification = clamp(uBackdropScale, 0.25, 1.0);
        backdropScaleOffset =
            filterDeltaFromCenter *
            (1.0 / magnification - 1.0) *
            appearanceVisibility;
    }
    vec4 refractColor;
    // Skip two texture reads only when the maximum channel separation is
    // subpixel. The uniform predicate stays coherent across the layer and the
    // displacement bound keeps this optimization valid for either CA sign.
    if (
        abs(uDispersion) * maxDisplacement <=
        kDispersionSubpixelThreshold
    ) {
        vec2 sourceOffset = backdropScaleOffset + displacement;
        vec2 refractedUV;
        if (sourceOffset.x == 0.0 && sourceOffset.y == 0.0) {
            // Undisplaced glass fetches its own texel, bypassing the sampler,
            // so it reproduces the backdrop exactly even when the sampler is
            // bilinear (whose fixed-point sub-texel weights are never exactly
            // zero at texel centres).
            refractedUV = (floor(fragCoord) + 0.5) * invUSize;
            #ifdef IMPELLER_TARGET_OPENGLES
            // The GLES runtime stages also emit GLSL ES 1.00, which has no
            // texelFetch. The texel centre is exact under nearest sampling;
            // bilinear can differ by a few LSB at hard edges.
            refractColor = texture(uBackgroundTexture, refractedUV);
            #else
            refractColor = texelFetch(
                uBackgroundTexture,
                ivec2(floor(fragCoord)),
                0
            );
            #endif
        } else {
            refractedUV = screenUV +
                mirrorIntoBackdrop(sourceOffset, matteCoord) * invUSize;
            refractColor = texture(
                uBackgroundTexture,
                mirrorBackgroundUV(refractedUV, invUSize)
            );
        }
    } else {
        float dispersionStrength = uDispersion * 0.5;
        vec2 redOffset = displacement * (1.0 + dispersionStrength);
        vec2 blueOffset = displacement * (1.0 - dispersionStrength);
        
        vec2 redUV = mirrorBackgroundUV(
            screenUV + mirrorIntoBackdrop(
                backdropScaleOffset + redOffset,
                matteCoord
            ) * invUSize,
            invUSize
        );
        vec2 greenUV = mirrorBackgroundUV(
            screenUV + mirrorIntoBackdrop(
                backdropScaleOffset + displacement,
                matteCoord
            ) * invUSize,
            invUSize
        );
        vec2 blueUV = mirrorBackgroundUV(
            screenUV + mirrorIntoBackdrop(
                backdropScaleOffset + blueOffset,
                matteCoord
            ) * invUSize,
            invUSize
        );
        
        float red = texture(uBackgroundTexture, redUV).r;
        vec4 greenSample = texture(uBackgroundTexture, greenUV);
        float blue = texture(uBackgroundTexture, blueUV).b;
        
        refractColor = vec4(red, greenSample.g, blue, greenSample.a);
    }
    
    vec3 transmittedColor = vec3(0.0);
    vec3 baseColor = vec3(0.0);
    float directShare = colorModelShares.x;
    if (directShare > 0.0) {
        transmittedColor = pow(
            max(refractColor.rgb, vec3(0.0)),
            vec3(max(uTransmissionGamma, 0.01))
        );
        vec3 materialColor = materialTint.rgb * materialTint.a;
        transmittedColor *= 1.0 - materialTint.a;
        baseColor = materialColor + transmittedColor;
        baseColor = applySaturation(baseColor, uSaturation);
        if (uVibrancy > 0.0) {
            float chroma = max(max(baseColor.r, baseColor.g), baseColor.b) -
                min(min(baseColor.r, baseColor.g), baseColor.b);
            baseColor = clamp(
                baseColor + vec3(chroma * max(uVibrancy, 0.0)),
                0.0,
                1.0
            );
        }
    }
    if (directShare < 1.0) {
        // Apple's public tint is not a flat source-over wash. Its documented
        // "range of tones" is selected from backdrop brightness, while tint
        // opacity linearly mixes that opaque tonal result with the untinted
        // material. The untinted material itself treats luminance and
        // chroma separately (see parametricFaceTransfer). Saturation and
        // gamma stay available as relative adjustments where 1 is Apple's
        // face.
        float adaptiveShare = 1.0 - directShare;
        float backdropLuminance = dot(refractColor.rgb, LUMA_WEIGHTS);
        // Slot-weighted blend of each model's outputs. Wash, face transfer,
        // tint tone, border response and glint target all mix linearly, so
        // merged models cross-fade without passing through a third. The
        // direct share contributes the shared default glint target.
        vec4 washSum = vec4(0.0);
        vec2 transferSum = vec2(0.0);
        vec3 toneSum = vec3(0.0);
        float contourBoost = 0.0;
        vec3 glintSum = vec3(
            directShare * kGlintLuminance,
            0.0,
            directShare * kGlintVibrancy
        );
        for (int slot = 0; slot < 3; slot++) {
            float share = colorModelShares[slot + 1];
            if (share <= 0.0) {
                continue;
            }
            vec4 wash = parametricNeutralTint(slot, uTintAmount);
            washSum += share * vec4(wash.rgb * wash.a, wash.a);
            transferSum +=
                share * parametricFaceTransfer(slot, uTintAmount);
            // A model's border strengthens with the opacity the slider adds.
            contourBoost += share * parametricContourResponse(slot) * (
                parametricTransmittance(slot, 0.0) -
                parametricTransmittance(slot, uTintAmount)
            );
            if (materialTint.a >= 0.001) {
                toneSum += share * parametricTintTone(
                    slot,
                    materialTint.rgb,
                    backdropLuminance
                );
            }
            glintSum += share * parametricGlint(slot);
        }
        gContourAlpha *= 1.0 + contourBoost;
        gGlintLuminance = glintSum.x;
        gGlintFaceGain = glintSum.y;
        gGlintVibrancy = glintSum.z;
        vec4 neutralTint = vec4(
            washSum.rgb / max(washSum.a, 1e-4),
            washSum.a / adaptiveShare
        );
        vec2 faceTransfer = transferSum / adaptiveShare;
        vec3 neutralTransmission = neutralTransmissionOf(
            refractColor.rgb,
            backdropLuminance,
            faceTransfer,
            neutralTint.a
        );
        vec3 neutralBase = clamp(
            neutralTint.rgb * neutralTint.a + neutralTransmission,
            0.0,
            1.0
        );
        if (uVibrancy > 0.0) {
            float neutralChroma =
                max(max(neutralBase.r, neutralBase.g), neutralBase.b) -
                min(min(neutralBase.r, neutralBase.g), neutralBase.b);
            neutralBase = clamp(
                neutralBase + vec3(neutralChroma * max(uVibrancy, 0.0)),
                0.0,
                1.0
            );
        }
        vec3 ios27Base = neutralBase;
        if (materialTint.a >= 0.001) {
            ios27Base = mix(
                neutralBase,
                toneSum / vec3(adaptiveShare),
                materialTint.a
            );
        }
        baseColor = mix(ios27Base, baseColor, directShare);
        transmittedColor = mix(
            neutralTransmission * (1.0 - materialTint.a),
            transmittedColor,
            directShare
        );
    }

    // Reconstruct the original material silhouette from the signed SDF. The
    // geometry alpha is only an expanded support mask, allowing the attached
    // contour to sit outside without turning those pixels into glass.
    // Beyond rimReach() every rim effect is exactly zero: the lit color is the
    // base color and there is no exterior border, so none of it (nor the
    // normal or the transmitted color it consumes) is evaluated.
    vec3 litColor = baseColor;
    float externalContourAlpha = 0.0;
    if (signedEdgeDistance < rimReach()) {
        if (!hasSurfaceNormal) {
            surfaceNormal = lowResNormalFiltered(lowResField, lowResNode).xy;
        }
        litColor = applySpecularHighlights(
            baseColor,
            transmittedColor,
            signedEdgeDistance,
            surfaceNormal
        );
        externalContourAlpha =
            contourCoverage(signedEdgeDistance).x *
            gContourAlpha *
            contourDirection(surfaceNormal) *
            appearanceVisibility;
    }
    // The lit material (face, tint, saturation, lighting and in-material
    // contour) cross-fades to the refracted backdrop, whose refraction
    // scales with visibility. Fading the output rather than each parameter
    // keeps coupled factors, such as the dark face's wash and lift, linear
    // and monotonic.
    vec3 finalColor = mix(refractColor.rgb, litColor, materialVisibility);
    // Inside the material, contour absorption is handled before highlights so
    // specular light can eclipse it. Only the part outside the material is
    // composited as a translucent attached boundary. It lies outside the
    // alpha fade, so it always scales with visibility.
    float fadeAlpha = mix(1.0, appearanceVisibility, uBlurFade);
    float visibleMaterialAlpha = materialAlpha * fadeAlpha;
    float alpha = visibleMaterialAlpha + externalContourAlpha;
    vec3 premultipliedColor = finalColor * visibleMaterialAlpha +
        uContourColor.rgb * externalContourAlpha;

    fragColor = vec4(premultipliedColor, alpha);
}

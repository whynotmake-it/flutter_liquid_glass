// Copyright 2025, Tim Lehmann for whynotmake.it
//
// Final rendering pass for liquid glass with pre-computed geometry
// This shader reads the geometry buffer (edge distance, surface direction,
// half the shorter side) and applies the liquid glass effect efficiently

// Refraction is evaluated in global filter coordinates: the affine mapping and
// everything that holds a position stay highp, as mediump turns the coordinate
// subtraction into visible shimmer on large layers. The rest is mediump, which
// fits the shader in the 32 registers a Mali GPU runs at full occupancy.
precision mediump float;

// The color models a variant shades: every model, the direct model alone,
// or one iOS 27 model in slot 0 alone. A variant that shades one family fits
// in fewer registers (FinalShaderVariant).
#define COLOR_MODELS_ALL 0
#define COLOR_MODELS_DIRECT 1
#define COLOR_MODELS_IOS27 2
#ifndef COLOR_MODELS
#define COLOR_MODELS COLOR_MODELS_ALL
#endif

// Whether the variant frosts an unblurred copy itself (uBackdropFrost). The
// 32-register variants leave it out and have a frosted twin: with it, the
// Mali-G78 compiler keeps work across the reads and doubles their registers,
// halving their occupancy for clear glass too.
#ifndef FROST
#define FROST 1
#endif

// Whether the variant draws a scroll edge's frost, fade and hairline where
// the glass paints nothing, reading the same copy (FrostBand).
#ifndef FROST_BAND
#define FROST_BAND 0
#endif

// Whether the variant parts colors (uBackdropAberration). Its six reads take
// the 32-register variants to 46 registers and more on the Mali-G78, so
// only the variants that shade every color model do, and glass that parts
// colors draws with one of those.
#ifndef ABERRATION
#define ABERRATION (COLOR_MODELS == COLOR_MODELS_ALL)
#endif

// Whether the variant works its geometry out per fragment, for glass of one
// shape (shape_geometry.glsl), instead of reading an atlas.
#ifndef SHAPE_GEOMETRY
#define SHAPE_GEOMETRY 0
#endif

#include <flutter/runtime_effect.glsl>
#include "render.glsl"
#include "glass_glow.glsl"
#if FROST
#include "frost.glsl"
#endif

// The geometry buffer holds one RGBA16F texel for every matte pixel near an
// edge, in a sparse atlas (geometry_tiling.dart, gpu/tile_*.glsl): a table of
// one texel per 16 x 16 tile points each tile at its ring strip or at a
// constant block for tiles wholly outside or deep inside. The strips are read
// with linear filtering, the table texel by texel. Where the shapes differ
// in look, textures of the atlas's layout hold each texel's look beside it
// (gpu/looks.glsl): the tint premultiplied, the response, and the color
// models' shares.

uniform highp vec2 uSize;

// The floats Dart writes, four to a vec4 in the order it writes them, and the
// names below are lanes of them: impellerc gives every uniform declaration its
// own Metal buffer, bound per draw, where Vulkan binds one struct. A value that
// straddles two vec4s is put back together here. Positions and whatever maps
// them stay highp; values a highp vec4 holds with them are read into mediump
// globals below, or they would turn the arithmetic around them highp.
uniform highp vec4 uGeometryBounds;
#define uGeometryOffset uGeometryBounds.xy
#define uGeometrySize uGeometryBounds.zw

uniform vec4 uFace[7];
#define uTint uFace[0]
#define uOpticalProps uFace[1].xyz
#define uLightDirection uFace[2].zw
#define uHighlightColor uFace[3]
#define uContourColor uFace[4]
#define uLightingShapeConfig uFace[5]
#define uContourConfig uFace[6].xyz

// uMaterialCenter, uSpecularWrap, uTransmissionGamma.
uniform highp vec4 uProfile;

// [1].yz: the color model's code and the visibility.
uniform vec4 uMaterial[2];

uniform highp vec4 uMapping[3];
uniform highp float uMappingEnd;
#define uFilterToMatteBasis uMapping[0]
#define uFilterToMatteOffset uMapping[1].xy
// Matte-space rect (LTRB, device px) the filter captured backdrop for.
// Outside it the filter input is transparent or clamped, so displaced samples
// are mirrored back in at its edge.
#define uBackdropBounds vec4(uMapping[1].w, uMapping[2].xyz)
// Where fragment coordinates start, in device px: zero for a filter, whose
// coordinates are its input's; the origin of the copy a paint samples.
#define uBackdropOrigin vec2(uMapping[2].w, uMappingEnd)

// Per-model parameter blocks for the three adaptive color-model slots the
// layer assigned this frame: slot code 1..3 selects
// uColorModelParams[(code - 1) * 6 .. code * 6 - 1]. The curves over the
// slider arrive evaluated. Packing, mirrored from
// GlassColorParameters.toShaderParameters:
//   +0: premultiplied emission rgb,  transmittance
//   +1: luminanceLift, chromaGain, the border's gain with the slider,
//       bleed opacity (negative where it takes the bright parts)
//   +2: bleed black, white, saturation
//   +3: toneLow   (base, amplitude, pivot, exponent)
//   +4: toneHigh  (base, amplitude, pivot, exponent)
//   +5: toneGammaLuminance, glintLuminance, glintFaceGain, glintVibrancy
uniform vec4 uColorModelParams[18];

//   uGeometryAtlas: the texel of the table's first entry, and the atlas
//                   texture's size in texels.
//   uBevel:         refraction height in px, whether refraction fits the
//                   shape, and half the short side of the surface, which
//                   sizes the bevel: glass over a matte of a group has its
//                   own, not the matte's.
#if !SHAPE_GEOMETRY
uniform highp vec4 uGeometryAtlas;
#endif
uniform vec3 uBevel;
// The inputs of the optional effects, in one declaration: a Metal stage has
// 31 buffer slots, and a shader past them fails to compile on Metal alone
// (Vulkan and GLES accept it).
// [0] uSolidBackdrop: the opaque color the glass is shaded over when it is
//     drawn as a paint instead of a backdrop filter; every backdrop read
//     returns it. Alpha 0 reads the backdrop.
// [1..3] the touch glow of one lit shape (glass_glow.glsl): the spot, the
//     lit shape's box, its corner radius and wash. All zero draws no glow.
// [4] xy uBackdropShrinkAxis: half of the segment backdropShrink shrinks
//     about, in matte device px from the material center; zero shrinks
//     about the center itself. z uBackdropReduced: above zero when the copy
//     the glass samples has fewer pixels than the screen, so no glass reads
//     its own texel; at 1 or more, the copy fills the top-left
//     1 / uBackdropReduced of its texture along each side (a layer whose
//     copy is drawn in its corner). w uBackdropFrost: the Gaussian sigma,
//     in device px, the shader frosts an unblurred copy by; zero reads it
//     as it is.
// [5] uBackdropOverlay: a color laid over the read backdrop at its alpha,
//     the dimming between a cached copy of the page and the glass.
// [6] uBackdropPull: x how far outside itself the glass reads the backdrop
//     at its edge and y how deep from the edge that reaches, both in matte
//     device px; x zero pulls nothing. z half the center line the pull and
//     the aberration point away from, positive along x and negative along
//     y; w half the short side of the material.
// [7] uBackdropAberration: x how far apart the outermost of the seven reads
//     that part the colors lie, and y how deep from the edge the parting
//     fades to nothing, both in matte device px; x zero parts nothing.
uniform highp vec4 uEffects[8];
#define uSolidBackdrop uEffects[0]
#define uGlowSpot uEffects[1]
#define uGlowBox uEffects[2]
#define uGlowShape uEffects[3]
#define uBackdropShrinkAxis uEffects[4].xy
#define uBackdropReduced uEffects[4].z
#define uBackdropFrost uEffects[4].w
#define uBackdropOverlay uEffects[5]
#define uBackdropPull uEffects[6]
#define uBackdropAberration uEffects[7].xy

#if SHAPE_GEOMETRY
#include "shape_geometry.glsl"
#endif

vec4 colorModelSlot(int slot, int field) {
    return uColorModelParams[slot * 6 + field];
}

// 1.0 lets material alpha cross-fade the frost away, and the rest of the
// material with it; 0.0 keeps unfrosted glass opaque and cross-fades the
// material to the refracted backdrop instead, so visibility 0 is an exact
// identity of the backdrop.
float uBlurFade = uMapping[1].z;
float uDisplacementScale = uOpticalProps.x;
float uDispersion = uOpticalProps.y;
// Rim lighting depth.
float uThickness = uOpticalProps.z;
float uLightIntensity = uFace[1].w;
float uBackdropScale = uFace[2].x;
float uSaturation = uFace[2].y;
float uEdgeWidth = uContourConfig.x;
float uContourTransmittance = uContourConfig.y;
float uContourDirectionality = uContourConfig.z;
float uContourOffset = uFace[6].w;
#define uMaterialCenter uProfile.xy
float uSpecularWrap = uProfile.z;
float uTransmissionGamma = uProfile.w;
float uVibrancy = uMaterial[0].x;
float uBevelShadowStrength = uMaterial[0].z;
float uBevelShadowDepth = uMaterial[0].w;
float uBevelShadowOffset = uMaterial[1].x;
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
// The mirror that turns an edge's outward normal into the way glass parts
// colors along, as the rows (x, y) and (y, z): the reflection across the
// line that falls 52.5 degrees from the right to the bottom, cos 105 and
// sin 105.
const vec3 kPartingMirror = vec3(-0.258819, 0.965926, 0.258819);
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

// One iOS 27 model and one appearance: the face in the middle of the glass
// has a fixed shape, and takes it in a few 16-bit operations.
#if COLOR_MODELS == COLOR_MODELS_IOS27 && !SHAPE_APPEARANCE && !SHAPE_TINT
#define PLAIN_INTERIOR 1
#else
#define PLAIN_INTERIOR 0
#endif

uniform sampler2D uBackgroundTexture;
#if !SHAPE_GEOMETRY
uniform sampler2D uGeometryTexture;
uniform sampler2D uGeometryTable;
#endif
#if SHAPE_APPEARANCE || SHAPE_TINT
uniform sampler2D uLookTint;
#endif
#if SHAPE_APPEARANCE
uniform sampler2D uLookResponse;
uniform sampler2D uLookShares;
#endif

layout(location = 0) out vec4 fragColor;

#if FROST_BAND
// [0] the band's rect in fragment coordinates
// [1] x the frost in device pixels; y, z the fragment rows where the fade and
//     the frost are whole and where they are gone; w the color's brightness
// [2] the fade, premultiplied
// [3] xy the fragment rows of the hairline, z its gray, w the presence
// [4] x saturation
uniform highp vec4 uBand[5];

vec4 bandColor(highp vec2 fragment) {
    vec2 inside = clamp(
        min(fragment + 0.5, uBand[0].zw) - max(fragment - 0.5, uBand[0].xy),
        0.0,
        1.0
    );
    float coverage = inside.x * inside.y;
    if (coverage <= 0.0) return vec4(0.0);
    highp vec2 invSize = 1.0 / uSize;
    highp float copyScale = 1.0 / max(uBackdropReduced, 1.0);
    highp vec2 halfTexel = invSize * 0.5;
    vec4 color = frostEight(
        uBackgroundTexture,
        fragment * invSize * copyScale,
        uBand[1].x,
        invSize * copyScale * frostMirror(fragment),
        halfTexel * copyScale,
        (vec2(1.0) - halfTexel) * copyScale
    );
    vec3 rgb = color.rgb;
    float luminance = dot(rgb, LUMA_WEIGHTS);
    rgb = clamp(mix(vec3(luminance), rgb, uBand[4].x) + uBand[1].w * color.a, 0.0, 1.0);
    float whole = clamp(
        (fragment.y - uBand[1].z) / (uBand[1].y - uBand[1].z),
        0.0,
        1.0
    );
    // The frost dissolves into what lies under it where the fade does, with
    // no slope at either end.
    vec4 filtered = vec4(rgb, color.a) * uBand[3].w * frostEase(whole);
    vec4 fade = uBand[2] * whole;
    if (fragment.y >= uBand[3].x && fragment.y < uBand[3].y) {
        fade = vec4(uBand[3].z * 0.1, uBand[3].z * 0.1, uBand[3].z * 0.1, 0.1) * uBand[3].w +
            fade * (1.0 - 0.1 * uBand[3].w);
    }
    return (fade + filtered * (1.0 - fade.a)) * coverage;
}

vec4 bandRim(highp vec2 fragment) {
    highp vec2 uv = fragment / uSize / max(uBackdropReduced, 1.0);
    vec4 color = texture(uBackgroundTexture, uv);
    vec4 fade = uBand[2];
    return fade + color * (1.0 - fade.a);
}
#define EMPTY_FRAGMENT bandColor(FlutterFragCoord().xy - uBackdropOrigin)
#else
#define EMPTY_FRAGMENT vec4(0.0)
#endif

// The wash of one model's untinted face: its premultiplied emission, and its
// opacity, the complement of its transmittance.
vec4 parametricWash(int slot) {
    vec4 face = colorModelSlot(slot, 0);
    return vec4(face.rgb, 1.0 - face.w);
}

// Luminance lift and chroma gain of one model's untinted face.
vec2 parametricFaceTransfer(int slot) {
    return colorModelSlot(slot, 1).xy;
}

// How much of the backdrop's chroma a face of the given lift keeps at the
// backdrop's luminance: the lift is a cap on luminance, 1 - lift / (1 + lift)
// of white, and iOS takes chroma down with it.
float parametricChromaKeep(float lift, float luminance) {
    float keep = 1.0 - luminance * lift / (1.0 + lift);
    return keep * (1.3 - 0.3 * keep);
}

// One model's bleed, weighted by its opacity so models blend by how much
// they bleed: black, white and saturation times the opacity, then the
// opacity.
vec4 parametricBleed(int slot) {
    float opacity = abs(colorModelSlot(slot, 1).w);
    return vec4(colorModelSlot(slot, 2).xyz * opacity, opacity);
}

// The opacity of one model's bleed where it takes the bright parts of the
// face, which the slot holds as a negative opacity, else zero.
float parametricBleedOnBright(int slot) {
    return max(-colorModelSlot(slot, 1).w, 0.0);
}

// The face under a bleed (see GlassColorBleed): pulled toward a wash of the
// backdrop by the fourth power of its own luminance, or of what it lacks to
// white, or of a blend of the two where models of both kinds merge
// (onBright is the part of bleed.w that takes the bright parts).
vec3 applyBleed(
    vec3 face,
    vec3 backdrop,
    float backdropLuminance,
    vec4 bleed,
    float onBright
) {
    if (bleed.w < 1e-4) {
        return face;
    }
    vec3 matrix = bleed.xyz / bleed.w;
    float weight = clamp(dot(face, LUMA_WEIGHTS), 0.0, 1.0);
    weight = mix(1.0 - weight, weight, onBright / bleed.w);
    weight *= weight;
    return mix(
        face,
        vec3(mix(matrix.x, matrix.y, backdropLuminance)) +
            (backdrop - backdropLuminance) * matrix.z,
        weight * weight * bleed.w
    );
}

// The range of tint tones of one model by the luminance of the face the
// tint covers, evaluated per channel as clamp(lo + (hi - lo) * tint^gamma)
// where lo and hi are luminance ramps
// base + amplitude * (min(1, F / pivot))^exponent and the gamma is
// 1 + toneGammaLuminance * (1 - F).
vec3 parametricTintTone(int slot, vec3 tint, float faceLuminance) {
    float luminance = clamp(faceLuminance, 0.0, 1.0);
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

// How much stronger a model's border is for the opacity the slider adds.
float parametricContourBoost(int slot) {
    return colorModelSlot(slot, 1).z;
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

highp vec2 mirrorBackgroundUV(highp vec2 uv, highp vec2 inverseTextureSize) {
    // Image-filter sampler edge behavior differs between Impeller backends.
    // Preserve every coordinate inside the input texture exactly, and mirror
    // only displaced samples that genuinely leave it. This avoids GLES decal
    // black without clamping Metal samples into stretched edge pixels.
    highp vec2 mirrored = vec2(1.0) - abs(mod(uv, vec2(2.0)) - vec2(1.0));
    highp vec2 halfTexel = inverseTextureSize * 0.5;
    return clamp(mirrored, halfTexel, vec2(1.0) - halfTexel);
}

highp vec2 filterDeltaFromMatteDelta(highp vec2 matteDelta, highp vec4 basis) {
    // Invert the live filter->matte affine basis so material-centered source
    // mapping remains stable under ancestor transforms.
    highp float determinant = basis.x * basis.w - basis.y * basis.z;
    if (abs(determinant) < 1e-6) {
        return vec2(0.0);
    }
    return vec2(
        basis.w * matteDelta.x - basis.y * matteDelta.y,
        -basis.z * matteDelta.x + basis.x * matteDelta.y
    ) / determinant;
}

highp vec2 mirrorIntoBackdrop(highp vec2 sourceOffset, highp vec2 matteCoord) {
    highp vec2 sampleMatte = matteCoord + vec2(
        dot(uFilterToMatteBasis.xy, sourceOffset),
        dot(uFilterToMatteBasis.zw, sourceOffset)
    );
    // Keep bilinear footprints off the uncaptured side of the edge.
    float margin = 0.5;
    highp vec2 lo = uBackdropBounds.xy + margin;
    highp vec2 hi = uBackdropBounds.zw - margin;
    if (all(greaterThanEqual(sampleMatte, lo)) &&
        all(lessThanEqual(sampleMatte, hi))) {
        return sourceOffset;
    }
    highp vec2 extent = max(hi - lo, vec2(0.0));
    highp vec2 mirrored = lo + extent - abs(extent - abs(sampleMatte - lo));
    mirrored = clamp(mirrored, lo, max(hi, lo));
    return sourceOffset + filterDeltaFromMatteDelta(
        mirrored - sampleMatte,
        uFilterToMatteBasis
    );
}

// From the nearest point of the material's long center line to
// [fromCenter], a point given from the material's center, in the matte.
highp vec2 fromCenterLine(highp vec2 fromCenter) {
    highp vec2 line = uBackdropPull.z > 0.0 ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
    return fromCenter - line * clamp(
        dot(fromCenter, line),
        -abs(uBackdropPull.z),
        abs(uBackdropPull.z)
    );
}

// How far inside the edge, in device px, the rim lighting and the border can
// reach. Deeper pixels get no rim light and no border, so their color is the
// base color. It depends only on settings, not on the pixel. An effect whose
// strength is zero adds nothing. It may be larger than the real reach, never
// smaller.
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
        float surfaceHalfMinor = uBevel.z;
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


#if !SHAPE_GEOMETRY
// Where the atlas holds matte pixel position [pixel], from the geometry
// buffer's corner: the table names the atlas texel of the tile's first pixel
// and how many texels a pixel spans (1, a fraction where the tile is coarse,
// 0 for a constant tile). A tile's strip carries a texel of apron on each
// side, so the filtered read never blends in another tile's texels.
highp vec2 atlasPoint(highp vec2 pixel) {
    highp vec2 tile = min(
        floor(pixel / 16.0),
        ceil(uGeometrySize / 16.0) - 1.0
    );
    highp vec3 entry = texture(
        uGeometryTable,
        (uGeometryAtlas.xy + tile + 0.5) / uGeometryAtlas.zw
    ).xyz;
    return (entry.xy + (pixel - tile * 16.0) * entry.z) / uGeometryAtlas.zw;
}
#endif

// The surface direction (xy) and refraction strength (z) of a geometry
// texel, which stores the direction with its length set to the strength.
vec3 surfaceOf(vec4 geometry) {
    float strength = length(geometry.yz);
    return vec3(
        strength > 0.0001 ? geometry.yz / strength : vec2(0.0),
        strength
    );
}

#if PLAIN_INTERIOR
// How deep a pixel needs no bevel and no rim light. Glass that carries
// anything else over its whole face never takes this path.
float plainInteriorDepth() {
    bool plain = abs(uBackdropScale - 1.0) <= 0.0001 &&
        uBackdropPull.x <= 0.0 &&
        uBackdropFrost <= 0.0 &&
        uTint.a < 0.001 &&
        uMaterial[1].z >= 1.0 &&
        uTransmissionGamma == 1.0 &&
        uVibrancy <= 0.0 &&
        uGlowSpot.w <= 0.0 &&
        uGlowShape.y <= 0.0 &&
        uSolidBackdrop.a <= 0.5 &&
        uBackdropOverlay.a <= 0.0;
    return plain ? max(uBevel.x, rimReach()) + 1.0 : 32000.0;
}
#endif

// How far the backdrop is shifted at this pixel, in px, toward the inside of
// the shape. The glass is flat in the middle with a rounded (quarter-circle)
// bevel at the edge, and the bevel gets narrower on smaller shapes.
float displacementMagnitude(
    float inward,
    float halfMinor,
    float shortening
) {
    float refractionHeight = uBevel.x;
    float refractionAmount = max(uDisplacementScale, 0.001);
    float bevel;
    float amount;
    if (uBevel.y > 0.5) {
        // iOS 27 regular glass: the bevel is at most a quarter of the
        // shorter side, and the edge never shifts the backdrop past the
        // shape's center line.
        bevel = min(refractionHeight, 0.5 * halfMinor);
        amount = min(refractionAmount, halfMinor);
    } else {
        // iOS 27 clear glass: the bevel is at most 0.36 of the shorter side
        // and the edge shifts the backdrop by at most 0.65 of it, past the
        // shape's center line.
        bevel = min(refractionHeight, 0.72 * halfMinor);
        amount = min(refractionAmount, 1.3 * halfMinor);
    }
    float bevelX = 1.0 - clamp(max(inward, 0.0) / max(bevel, 0.001), 0.0, 1.0);
    float magnitude = bevel > 0.001
        ? amount * (1.0 - sqrt(1.0 - bevelX * bevelX)) * shortening
        : 0.0;
    return clamp(magnitude, 0.0, refractionAmount);
}

// How far and which way the backdrop pull reads from [fromCenter], a point
// given from the material's center, in the matte: out of a capsule of the
// material, by a quarter circle as the bevel's.
highp vec2 pullOf(highp vec2 fromCenter) {
    highp vec2 fromLine = fromCenterLine(fromCenter);
    highp float reach = length(fromLine);
    if (uBackdropPull.x <= 0.0 || reach <= 0.001) {
        return vec2(0.0);
    }
    float pullX = clamp(
        1.0 - (uBackdropPull.w - reach) / uBackdropPull.y,
        0.0,
        1.0
    );
    return fromLine *
        (uBackdropPull.x * (1.0 - sqrt(1.0 - pullX * pullX)) / reach);
}

#if ABERRATION
// From [fromCenter] to what the glass shows there, in the matte, with the
// glass taken for a capsule of the material: its bevel, then the pull of
// the point the bevel reads, and nothing past the capsule's edge, where
// the backdrop shows as it is. What a read beside the fragment takes,
// which has the geometry of the fragment alone.
highp vec2 capsuleSourceOffset(highp vec2 fromCenter, float visibility) {
    highp vec2 fromLine = fromCenterLine(fromCenter);
    highp float reach = length(fromLine);
    highp float depth = uBackdropPull.w - reach;
    if (reach <= 0.001) {
        return vec2(0.0);
    }
    highp vec2 bevel = fromLine * (
        -displacementMagnitude(depth, uBackdropPull.w, 1.0) / reach
    );
    return (bevel + pullOf(fromCenter + bevel)) *
        (visibility * clamp(depth + 0.5, 0.0, 1.0));
}
#endif

void main() {
    // Map image-filter fragment coordinates back into the layer-local geometry
    // matte. Apple Metal surfaces expose global filter coordinates, while
    // other backends may expose clip-local coordinates. These uniforms are
    // snapshotted with the frame, never overwritten through a shared texture.
    highp vec2 fragCoord = FlutterFragCoord().xy - uBackdropOrigin;
    highp vec2 screenUV = fragCoord / uSize;

    highp vec2 matteCoord = vec2(
        dot(uFilterToMatteBasis.xy, fragCoord),
        dot(uFilterToMatteBasis.zw, fragCoord)
    ) + uFilterToMatteOffset;
    highp vec2 geometryUV = (matteCoord - uGeometryOffset) / uGeometrySize;

    if (
        any(lessThan(geometryUV, vec2(0.0))) ||
        any(greaterThan(geometryUV, vec2(1.0)))
    ) {
        fragColor = EMPTY_FRAGMENT;
        return;
    }

    #if SHAPE_GEOMETRY
    // Deeper than the bevel and the rim, only coverage reads the distance.
    vec4 geometryTexel = shapeTexel(
        matteCoord - uGeometryOffset,
        max(uBevel.x, rimReach()) + 1.0
    );
    #else
    highp vec2 atlasUV = atlasPoint(matteCoord - uGeometryOffset);
    vec4 geometryTexel = texture(uGeometryTexture, atlasUV);
    #endif
    #if PLAIN_INTERIOR
    if (geometryTexel.x > plainInteriorDepth()) {
        vec3 backdrop;
        #ifndef IMPELLER_TARGET_OPENGLES
        if (uBackdropReduced == 0.0) {
            backdrop = texelFetch(
                uBackgroundTexture,
                ivec2(floor(fragCoord)),
                0
            ).rgb;
        } else
        #endif
        {
            highp vec2 halfTexel = 0.5 / uSize;
            backdrop = texture(
                uBackgroundTexture,
                clamp(screenUV, halfTexel, vec2(1.0) - halfTexel) /
                    max(uBackdropReduced, 1.0)
            ).rgb;
        }
        vec4 wash = parametricWash(0);
        vec2 transfer = parametricFaceTransfer(0);
        float luminance = dot(backdrop, LUMA_WEIGHTS);
        fragColor = vec4(
            clamp(
                applyBleed(
                    wash.rgb +
                        luminance *
                            (1.0 + transfer.x * (1.0 - luminance)) *
                            (1.0 - wash.a) +
                        (backdrop - luminance) * (
                            transfer.y * uSaturation *
                            parametricChromaKeep(transfer.x, luminance)
                        ),
                    backdrop,
                    luminance,
                    parametricBleed(0),
                    parametricBleedOnBright(0)
                ),
                0.0,
                1.0
            ),
            1.0
        );
        return;
    }
    #endif
    vec4 materialTint = uTint;
    float appearanceVisibility = clamp(uMaterial[1].z, 0.0, 1.0);
    vec4 colorModelShares = colorModelSharesOf(uMaterial[1].y);
    #if SHAPE_TINT || SHAPE_APPEARANCE
    {
        vec4 tint = texture(uLookTint, atlasUV);
        materialTint = vec4(
            tint.a > 0.0001 ? tint.rgb / tint.a : vec3(0.0),
            tint.a
        );
    }
    #endif
    #if SHAPE_APPEARANCE
    {
        vec4 response = texture(uLookResponse, atlasUV);
        uSaturation = response.x;
        uTransmissionGamma = response.y;
        uVibrancy = response.z;
        appearanceVisibility = clamp(response.w, 0.0, 1.0);
        colorModelShares = texture(uLookShares, atlasUV);
    }
    #endif
    // Weight of the material over the refracted backdrop. Frosted glass
    // renders the material in full and its alpha fades it with the frost;
    // opaque unfrosted glass fades it here. Either way it fades linearly,
    // never twice.
    float materialVisibility = mix(appearanceVisibility, 1.0, uBlurFade);

    float maxDisplacement = max(uDisplacementScale, 0.001);
    // Positive inside. It is a smooth value rather than a rounded byte, so
    // the antialiased edge below stays one pixel wide.
    float signedEdgeDistance = geometryTexel.x;
    // Box-filtered coverage of one physical pixel, as Core Animation
    // rasterizes the silhouette: a pixel-aligned edge stays hard, so the
    // glint's first row is not diluted by a wider feather.
    float materialAlpha = clamp(signedEdgeDistance + 0.5, 0.0, 1.0);
    if (
        materialAlpha < 0.01 &&
        contourCoverage(signedEdgeDistance).x * gContourAlpha < 0.01
    ) {
        fragColor = EMPTY_FRAGMENT;
        return;
    }
    // The surface direction is only computed where something uses it: the
    // bevel, for refraction, and the rim lighting near the edge.
    vec2 surfaceNormal = vec2(0.0);
    bool hasSurfaceNormal = false;
    vec2 displacement = vec2(0.0);
    // The bevel is never wider than the refraction height, so deeper pixels
    // have no refraction and skip this.
    if (signedEdgeDistance < uBevel.x) {
        vec3 surface = surfaceOf(geometryTexel);
        float magnitude = displacementMagnitude(
            signedEdgeDistance,
            geometryTexel.w,
            surface.z
        );
        if (magnitude > 0.0) {
            surfaceNormal = surface.xy;
            hasSurfaceNormal = true;
            displacement = surfaceNormal * (-magnitude) * appearanceVisibility;
        }
    }

    highp vec2 invUSize = 1.0 / uSize;
    // From the copy's uv to its texture's.
    highp float copyScale = 1.0 / max(uBackdropReduced, 1.0);
    highp vec2 backdropScaleOffset = vec2(0.0);
    if (abs(uBackdropScale - 1.0) > 0.0001) {
        // backdropShrink is one lens over the whole face, uniform up to the
        // silhouette, about the nearest point of the segment
        // +-uBackdropShrinkAxis through the material center. The bevel
        // displacement adds on top of it. It never enlarges: magnifiers
        // re-render their content instead (see the example's loupe).
        highp vec2 shrinkAnchor = uMaterialCenter;
        highp float axisLengthSquared = dot(uBackdropShrinkAxis, uBackdropShrinkAxis);
        if (axisLengthSquared > 0.0) {
            shrinkAnchor += uBackdropShrinkAxis * clamp(
                dot(matteCoord - uMaterialCenter, uBackdropShrinkAxis) /
                    axisLengthSquared,
                -1.0,
                1.0
            );
        }
        highp vec2 filterDeltaFromAnchor = filterDeltaFromMatteDelta(
            matteCoord - shrinkAnchor,
            uFilterToMatteBasis
        );
        float magnification = clamp(uBackdropScale, 0.25, 1.0);
        backdropScaleOffset =
            filterDeltaFromAnchor *
            (1.0 / magnification - 1.0) *
            appearanceVisibility;
    }
    if (uBackdropPull.x > 0.0) {
        // The bevel lies over the pulled backdrop, so the pull is the one
        // of the point the bevel reads.
        backdropScaleOffset += filterDeltaFromMatteDelta(
            pullOf(
                matteCoord + vec2(
                    dot(uFilterToMatteBasis.xy, displacement),
                    dot(uFilterToMatteBasis.zw, displacement)
                ) - uMaterialCenter
            ),
            uFilterToMatteBasis
        ) * appearanceVisibility;
    }
    vec4 refractColor;
    if (uSolidBackdrop.a > 0.5) {
        // Refracting, frosting or splitting a uniform color returns it.
        refractColor = vec4(uSolidBackdrop.rgb, 1.0);
    } else if (
        abs(uDispersion) * maxDisplacement <=
        kDispersionSubpixelThreshold
    ) {
        // Skip two texture reads only when the maximum channel separation is
        // subpixel. The uniform predicate stays coherent across the layer and
        // the displacement bound keeps this optimization valid for either CA
        // sign.
        highp vec2 sourceOffset = backdropScaleOffset + displacement;
        highp vec2 refractedUV;
        if (
            sourceOffset.x == 0.0 &&
            sourceOffset.y == 0.0 &&
            uBackdropReduced == 0.0
        ) {
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
                mirrorBackgroundUV(refractedUV, invUSize) * copyScale
            );
        }
        #if FROST
        if (uBackdropFrost > 0.0) {
            // The copy is taken unblurred and grown by three sigma, so the
            // taps read real backdrop past the rim; one refracted past it
            // reads the copy's edge.
            highp vec2 halfTexel = invUSize * 0.5;
            refractColor = frostTaps(
                uBackgroundTexture,
                refractedUV * copyScale,
                uBackdropFrost,
                invUSize * copyScale,
                halfTexel * copyScale,
                (vec2(1.0) - halfTexel) * copyScale,
                #if SHAPE_TINT
                // The dither takes this variant past the registers of full
                // occupancy, and a tint hides the most of what it hides.
                vec2(0.0)
                #else
                fragCoord
                #endif
            );
        }
        #endif
    } else {
        float dispersionStrength = uDispersion * 0.5;
        vec2 redOffset = displacement * (1.0 + dispersionStrength);
        vec2 blueOffset = displacement * (1.0 - dispersionStrength);
        
        highp vec2 redUV = mirrorBackgroundUV(
            screenUV + mirrorIntoBackdrop(
                backdropScaleOffset + redOffset,
                matteCoord
            ) * invUSize,
            invUSize
        );
        highp vec2 greenUV = mirrorBackgroundUV(
            screenUV + mirrorIntoBackdrop(
                backdropScaleOffset + displacement,
                matteCoord
            ) * invUSize,
            invUSize
        );
        highp vec2 blueUV = mirrorBackgroundUV(
            screenUV + mirrorIntoBackdrop(
                backdropScaleOffset + blueOffset,
                matteCoord
            ) * invUSize,
            invUSize
        );
        
        float red = texture(uBackgroundTexture, redUV * copyScale).r;
        vec4 greenSample = texture(uBackgroundTexture, greenUV * copyScale);
        float blue = texture(uBackgroundTexture, blueUV * copyScale).b;
        
        refractColor = vec4(red, greenSample.g, blue, greenSample.a);
    }
    #if ABERRATION
    if (uBackdropAberration.x > 0.0 && uSolidBackdrop.a <= 0.5) {
        // Seven reads of the glass a third of the amount apart along the
        // parting's way: red takes the three ahead, blue the three behind
        // and green the five in the middle, each weighted toward its far
        // end, and the parted color lies over the glass by the depth.
        highp vec2 fromCenter = matteCoord - uMaterialCenter;
        highp vec2 fromLine = fromCenterLine(fromCenter);
        highp float reach = length(fromLine);
        float parted = clamp(
            1.0 - (uBackdropPull.w - reach) / uBackdropAberration.y,
            0.0,
            1.0
        ) * appearanceVisibility;
        if (parted > 0.0 && reach > 0.001) {
            // The way is the edge's outward normal mirrored: out of the
            // glass up left and down right, into it up right and down left,
            // and nearly along the edge at the top, bottom and sides.
            highp vec2 third = vec2(
                dot(fromLine, kPartingMirror.xy),
                dot(fromLine, kPartingMirror.yz)
            ) * (uBackdropAberration.x / (3.0 * reach));
            vec3 taps[6];
            for (int i = 0; i < 6; i++) {
                highp vec2 beside = third * float(i < 3 ? i - 3 : i - 2);
                highp vec2 source = capsuleSourceOffset(
                    fromCenter + beside,
                    appearanceVisibility
                );
                taps[i] = texture(
                    uBackgroundTexture,
                    mirrorBackgroundUV(
                        screenUV + mirrorIntoBackdrop(
                            filterDeltaFromMatteDelta(
                                beside + source,
                                uFilterToMatteBasis
                            ),
                            matteCoord
                        ) * invUSize,
                        invUSize
                    ) * copyScale
                ).rgb;
            }
            refractColor.rgb = mix(
                refractColor.rgb,
                vec3(
                    taps[5].r / 2.0 + taps[4].r / 3.0 + taps[3].r / 6.0,
                    refractColor.g / 3.0 +
                        (taps[2].g + taps[3].g) * (2.0 / 9.0) +
                        (taps[1].g + taps[4].g) / 9.0,
                    taps[0].b / 2.0 + taps[1].b / 3.0 + taps[2].b / 6.0
                ),
                parted
            );
        }
    }
    #endif
    if (uBackdropOverlay.a > 0.0) {
        refractColor.rgb = mix(
            refractColor.rgb,
            uBackdropOverlay.rgb,
            uBackdropOverlay.a
        );
    }
    
    vec3 transmittedColor = vec3(0.0);
    vec3 baseColor = vec3(0.0);
    #if COLOR_MODELS == COLOR_MODELS_IOS27
    float directShare = 0.0;
    #elif COLOR_MODELS == COLOR_MODELS_DIRECT
    float directShare = 1.0;
    #else
    float directShare = colorModelShares.x;
    #endif
    #if COLOR_MODELS != COLOR_MODELS_IOS27
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
    #endif
    #if COLOR_MODELS != COLOR_MODELS_DIRECT
    if (directShare < 1.0) {
        // Apple's public tint is not a flat source-over wash. Its documented
        // "range of tones" is selected from backdrop brightness, while tint
        // opacity linearly mixes that opaque tonal result with the untinted
        // material. The untinted material itself treats luminance and
        // chroma separately (see GlassColorParameters). Saturation and
        // gamma stay available as relative adjustments where 1 is Apple's
        // face.
        float adaptiveShare = 1.0 - directShare;
        float backdropLuminance = dot(refractColor.rgb, LUMA_WEIGHTS);
        // Slot-weighted blend of each model's outputs. Wash, face transfer,
        // bleed, tint tone, border response and glint target all mix
        // linearly, so merged models cross-fade without passing through a
        // third. The direct share contributes the shared default glint
        // target.
        vec4 washSum = vec4(0.0);
        vec2 transferSum = vec2(0.0);
        vec4 bleedSum = vec4(0.0);
        float bleedOnBright = 0.0;
        float contourBoost = 0.0;
        vec3 glintSum = vec3(
            directShare * kGlintLuminance,
            0.0,
            directShare * kGlintVibrancy
        );
        #if COLOR_MODELS == COLOR_MODELS_IOS27
        for (int slot = 0; slot < 1; slot++) {
            float share = 1.0;
        #else
        for (int slot = 0; slot < 3; slot++) {
            float share = colorModelShares[slot + 1];
        #endif
            if (share <= 0.0) {
                continue;
            }
            washSum += share * parametricWash(slot);
            transferSum += share * parametricFaceTransfer(slot);
            bleedSum += share * parametricBleed(slot);
            bleedOnBright += share * parametricBleedOnBright(slot);
            // A model's border strengthens with the opacity the slider adds.
            contourBoost += share * parametricContourBoost(slot);
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
        float transmittedLuminance = pow(
            clamp(
                backdropLuminance *
                    (1.0 + faceTransfer.x * (1.0 - backdropLuminance)),
                0.0,
                1.0
            ),
            max(uTransmissionGamma, 0.01)
        );
        vec3 neutralTransmission =
            vec3(transmittedLuminance * (1.0 - neutralTint.a)) +
            (refractColor.rgb - vec3(backdropLuminance)) * (
                faceTransfer.y * uSaturation *
                parametricChromaKeep(faceTransfer.x, backdropLuminance)
            );
        // The bleed takes the face before it is clamped, as iOS's does: a
        // channel past white still pulls its share of the wash. A tint
        // mixes with the clamped face: native glass shows 60 % of white,
        // not of more, through a 40 % tint.
        vec3 neutralBase = clamp(
            applyBleed(
                neutralTint.rgb * neutralTint.a + neutralTransmission,
                refractColor.rgb,
                backdropLuminance,
                bleedSum / adaptiveShare,
                bleedOnBright / adaptiveShare
            ),
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
        // A tint covers the finished face, in a tone picked by the face's
        // own luminance.
        vec3 ios27Base = neutralBase;
        if (materialTint.a >= 0.001) {
            float faceLuminance = dot(neutralBase, LUMA_WEIGHTS);
            vec3 toneSum = vec3(0.0);
            #if COLOR_MODELS == COLOR_MODELS_IOS27
            toneSum = parametricTintTone(
                0,
                materialTint.rgb,
                faceLuminance
            );
            #else
            for (int slot = 0; slot < 3; slot++) {
                float share = colorModelShares[slot + 1];
                if (share > 0.0) {
                    toneSum += share * parametricTintTone(
                        slot,
                        materialTint.rgb,
                        faceLuminance
                    );
                }
            }
            #endif
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
    #endif

    // Reconstruct the original material silhouette from the signed SDF. The
    // geometry alpha is only an expanded support mask, allowing the attached
    // contour to sit outside without turning those pixels into glass.
    // Deeper than rimReach() there is no rim light and no border, so the
    // color is the base color and all of this is skipped.
    vec3 litColor = baseColor;
    float externalContourAlpha = 0.0;
    if (signedEdgeDistance < rimReach()) {
        if (!hasSurfaceNormal) {
            surfaceNormal = surfaceOf(geometryTexel).xy;
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
#if !SHAPE_APPEARANCE
    // Over everything the glass shows, under the content. Skipped in the
    // per-shape appearance variant, whose registers it would spill on
    // Mali GPUs. The matte coordinate is derived again, so no register
    // holds it across the shading.
    if (uGlowSpot.w > 0.0 || uGlowShape.y > 0.0) {
        highp vec2 glowCoord = FlutterFragCoord().xy - uBackdropOrigin;
        finalColor = applyGlassGlow(
            finalColor,
            vec2(
                dot(uFilterToMatteBasis.xy, glowCoord),
                dot(uFilterToMatteBasis.zw, glowCoord)
            ) + uFilterToMatteOffset,
            uGlowSpot,
            uGlowBox,
            uGlowShape
        );
    }
#endif
    vec3 premultipliedColor = finalColor * visibleMaterialAlpha +
        uContourColor.rgb * externalContourAlpha;

    fragColor = vec4(premultipliedColor, alpha);
#if FROST_BAND
    if (alpha < 0.999) fragColor += bandRim(FlutterFragCoord().xy - uBackdropOrigin) * (1.0 - alpha);
#endif
}

// Generated from lib/src/painting/shader_constants.dart by
// test/shader_constants_test.dart: do not edit.

#ifndef FINAL_LANES_GLSL
#define FINAL_LANES_GLSL

uniform highp vec4 uGeometry[2];
#define uGeometryOffset uGeometry[0].xy
#define uGeometrySize uGeometry[0].zw
#define uMaterialCenter uGeometry[1].xy
float uRefractionHeight = uGeometry[1].z;
float uRefractionFits = uGeometry[1].w;

uniform vec4 uFace[6];
#define uTint uFace[0]
float uDisplacementScale = uFace[1].x;
float uDispersion = uFace[1].y;
float uGlintStrength = uFace[1].z;
float uBackdropScale = uFace[1].w;
float uSaturation = uFace[2].x;
#define uContourAlpha uFace[2].y
float uRimReach = uFace[2].z;
float uGlintWidth = uFace[2].w;
float uEdgeWidth = uFace[3].x;
float uContourDirectionality = uFace[3].y;
float uVibrancy = uFace[3].z;
float uBevelShadowStrength = uFace[3].w;
float uBevelShadowDepth = uFace[4].x;
float uBevelShadowOffset = uFace[4].y;
#define uColorModelCode uFace[4].z
#define uVisibility uFace[4].w
float uBlurFade = uFace[5].x;
float uTransmissionGamma = uFace[5].y;
float uReadDepth = uFace[5].z;

uniform highp vec4 uMapping[3];
#define uFilterToMatteBasis uMapping[0]
#define uBackdropBounds uMapping[1]
#define uFilterToMatteOffset uMapping[2].xy
#define uBackdropOrigin uMapping[2].zw

uniform vec4 uColorModelParams[15];
#define modelEmission(slot) uColorModelParams[(slot) * 5].xyz
#define modelTransmittance(slot) uColorModelParams[(slot) * 5].w
#define modelBleed(slot) uColorModelParams[(slot) * 5 + 1].xyz
#define modelBleedOpacity(slot) uColorModelParams[(slot) * 5 + 1].w
#define modelGlint(slot) uColorModelParams[(slot) * 5 + 2].xyz
#define modelContourBoost(slot) uColorModelParams[(slot) * 5 + 2].w
#define modelTones(slot) uColorModelParams[(slot) * 5 + 3]
#define modelFaceTransfer(slot) uColorModelParams[(slot) * 5 + 4].xy

uniform highp vec4 uEffects[6];
#define uSolidBackdrop uEffects[0]
#define uGlowSpot uEffects[1]
#define uGlowBox uEffects[2]
#define uBackdropPull uEffects[3]
#define uBackdropAberration uEffects[4].xy
#define uGlowWash uEffects[4].z
#define uBackdropReduced uEffects[4].w
#define uBackdropFrost uEffects[5].x

#if FROST_BAND
uniform highp vec4 uBand[5];
#define uBandRect uBand[0]
#define uBandFrost uBand[1].x
#define uBandFadeWhole uBand[1].y
#define uBandFadeGone uBand[1].z
#define uBandBrightness uBand[1].w
#define uBandFade uBand[2]
#define uBandHairlineRows uBand[3].xy
#define uBandHairlineAlpha uBand[3].z
#define uBandPresence uBand[3].w
#define uBandSaturation uBand[4].x
#define uBandHairlineColor uBand[4].yzw
#endif

#if !COMPUTED_SHAPE
uniform highp vec4 uAtlasPlace;
#define uAtlasTableOrigin uAtlasPlace.xy
#define uAtlasTextureSize uAtlasPlace.zw
#endif

#endif

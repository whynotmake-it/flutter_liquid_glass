// Generated from lib/src/painting/shader_constants.dart by
// test/shader_constants_test.dart: do not edit.

#ifndef SHADER_CONSTANTS_GLSL
#define SHADER_CONSTANTS_GLSL

#define GEOMETRY_MAX_SHAPES 16
#define SHAPE_INDEX_MASK 15
const float kFarOutside = -4096.0;
#define SHAPE_SQUIRCLE 1.0
#define SHAPE_ELLIPSE 2.0
#define SHAPE_ROUNDED_RECTANGLE 3.0
#define SHAPE_SQUIRCLE_PAIR 4.0

#define ATLAS_TILE_SIZE 16.0
#define RAMP_FILL 128.0
#define RAMP_RUN 64.0
#define MEMBER_STARTS_GROUP 16.0
#define MEMBER_NONE 32.0

#define SHAPE_ROW_VEC4S 3
#define SHAPE_PRIMITIVE 0
#define SHAPE_INVERSE_BASIS 1
#define SHAPE_PLACEMENT 2
#define SQUIRCLE_ROW_VEC4S 3
#define SQUIRCLE_DEGREES_AND_SPANS 0
#define SQUIRCLE_CIRCLE_CENTERS 1
#define SQUIRCLE_AXES_AND_RADII 2
const float kOpticalCornerRadiusScale = 1.5;

const float kGlintBleed = 0.21;
const float kGlintBleedReach = 4.0;
const float kGlintPeak = 0.252;
const float kGlintLuminance = 1.6;
const float kGlintVibrancy = 2.85;
const float kClearShiftRatio = 1.3;
const float kDispersionSpread = 0.5;
const float kFrostEightMost = 2.8;
#define FROST_SPIRAL_TAPS 12
#define FROST_EIGHT_TAPS(TAP) TAP(0.48914, 0.1211) TAP(-0.36984, 0.5692) TAP(0.19721, -0.76661) TAP(0.79118, 0.99744) TAP(-1.1841, -0.10946) TAP(1.44405, -0.7216) TAP(-0.36967, 1.94006) TAP(-0.99796, -2.03012)
#define FROST_SIXTEEN_TAPS(TAP) TAP(0.29397, 0.08599) TAP(-0.29282, 0.38966) TAP(0.0903, -0.50235) TAP(0.47182, 0.65096) TAP(-0.77215, -0.05743) TAP(0.8233, -0.41313) TAP(-0.2299, 1.08504) TAP(-0.48656, -0.92531) TAP(1.2102, 0.51383) TAP(-1.21835, 0.60487) TAP(0.66623, -1.25508) TAP(0.52164, 1.6258) TAP(-1.48966, -0.79971) TAP(1.94532, -0.33318) TAP(-1.2292, 1.8894) TAP(-0.30413, -2.55934)
const float kFakeFieldInside = 24.0;
const float kFakeFieldOutside = 8.0;
#define HAZE_MOST_READS 32
const vec3 LUMA_WEIGHTS = vec3(0.2126, 0.7152, 0.0722);
const vec3 kPartingMirror = vec3(-0.258819, 0.965926, 0.258819);
const vec3 kPartingSide = vec3(0.16666666666666666, 0.3333333333333333, 0.5);
const vec3 kPartingMiddle = vec3(0.3333333333333333, 0.2222222222222222, 0.1111111111111111);
const float kChromaKeepRise = 0.3;
#define COLOR_MODEL_SLOTS 3
vec4 colorModelWeightsOf(float code) {
    return vec4(equal(vec4(code), vec4(0.0, 1.0, 2.0, 3.0)));
}
const float kLookModelStride = 2.0;
const vec2 kLightDirection = vec2(0.0, 1.0);
const float kGlintWidth = 1.2;
const float kGlintWrap = 0.5;
const float kGlintOppositeStrength = 1.0;
const float kBevelShadowDepth = 16.0;
const float kBevelShadowOffset = 6.0;
const float kBevelShadowDirectionality = 0.5;

#endif

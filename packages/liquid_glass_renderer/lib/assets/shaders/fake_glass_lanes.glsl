// Generated from lib/src/painting/shader_constants.dart by
// test/shader_constants_test.dart: do not edit.

#ifndef FAKE_GLASS_LANES_GLSL
#define FAKE_GLASS_LANES_GLSL

uniform vec4 uFake[6];
#define uShapeType uFake[0].x
#define uCornerRadius uFake[0].y
#define uTint vec4(uFake[0].z, uFake[0].w, uFake[1].x, uFake[1].y)
#define uGlintStrength uFake[1].z
#define uContourStrength uFake[1].w
#define uContourWidth uFake[2].x
#define uContourDirectionality uFake[2].y
#define uBevelStrength uFake[2].z
#define uPixelSize uFake[2].w
#define uExteriorOnly uFake[3].x
#define uGlintLuminance uFake[3].y
#define uFaceEmission vec3(uFake[3].z, uFake[3].w, uFake[4].x)
#define uGlintFaceGain uFake[4].y
#define uGlintVibrancy uFake[4].z
#define uGlintOnly uFake[4].w
#define uBottomRadius uFake[5].x

#endif

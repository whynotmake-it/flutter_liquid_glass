#ifndef FAKE_GLASS_LIGHTING_GLSL
#define FAKE_GLASS_LIGHTING_GLSL

#include "contour.glsl"
#include "fake_glass_lanes.glsl"
#include "rim_light.glsl"
#include "shader_constants.glsl"

// The reference rim's peak is lower than a source-over mix of the same glint
// target. The additive pass only adds light, so scale it to the measured
// profile instead of replacing the face.
const float kAdditiveGlintScale = 0.75;

vec4 fakeGlassLit(float distance, vec2 normal, float coverage) {
  float inward = max(-distance, 0.0);
  float glint = rimGlint(
    uGlintStrength,
    normal,
    glintProfile(inward, kGlintWidth)
  );

  float tintAlpha = uTint.a;
  vec3 faceProxy = uTint.rgb * tintAlpha + uFaceEmission;
  vec3 glintTarget = vec3(uGlintLuminance) +
      uGlintFaceGain * faceProxy +
      uGlintVibrancy * (faceProxy - vec3(dot(faceProxy, LUMA_WEIGHTS)));
  float materialCoverage = uExteriorOnly > 0.5 ? 0.0 : coverage;
  if (uGlintOnly > 0.5) {
    return vec4(
      max(glintTarget, vec3(0.0)) * glint * materialCoverage *
          kAdditiveGlintScale,
      0.0
    );
  }
  float outwardPixels = distance / uPixelSize;
  float contourWidthPixels = uContourWidth / uPixelSize;
  float contourBand = 0.0;
  if (uContourWidth > 0.0) {
    contourBand =
        contourIntegral(max(outwardPixels + 0.5, 0.0), contourWidthPixels) -
        contourIntegral(max(outwardPixels - 0.5, 0.0), contourWidthPixels);
  }
  float contourStrength = clamp(uContourStrength, 0.0, 1.0) *
      contourDirection(normal, uContourDirectionality);

  float shadow = bevelShadow(
    inward,
    normal,
    kBevelShadowDepth,
    kBevelShadowOffset,
    uBevelStrength
  );
  float materialAlpha = 1.0 - (1.0 - tintAlpha) * (1.0 - shadow);
  float exteriorContourAlpha = clamp(contourBand * contourStrength, 0.0, 1.0);
  vec3 emissionUnshadowed = uFaceEmission * shadow * (1.0 - tintAlpha);
  vec3 litPremultiplied = uTint.rgb * tintAlpha + emissionUnshadowed;
  float litAlpha = materialAlpha;
  if (litAlpha < 0.999) {
    litPremultiplied = min(litPremultiplied, vec3(1.0));
    float alphaCoveringColor =
        max(max(litPremultiplied.r, litPremultiplied.g), litPremultiplied.b);
    litAlpha = max(litAlpha, alphaCoveringColor);
  }
  float alpha = litAlpha * materialCoverage + exteriorContourAlpha;
  return vec4(
    max(litPremultiplied * materialCoverage, vec3(0.0)),
    clamp(alpha, 0.0, 1.0)
  );
}

#endif

// Copyright 2025, Tim Lehmann for whynotmake.it

#version 460 core
precision mediump float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uShapeType;
uniform float uCornerRadius;
uniform vec4 uTint;
uniform float uHighlight;
uniform float uHighlightWidth;
uniform float uThickness;
uniform float uHighlightWrap;
uniform float uOppositeHighlight;
uniform float uContourStrength;
uniform float uContourWidth;
uniform float uContourTransmittance;
uniform float uContourOffset;
uniform float uContourDirectionality;
uniform float uBevelStrength;
uniform float uBevelDepth;
uniform float uBevelOffset;
uniform float uBevelDirectionality;
uniform float uBevelSizeResponse;
uniform vec2 uLightDirection;
// Logical size of one physical pixel.
uniform float uPixelSize;
// 1 when drawing only the border ring outside the shape clip. The clip path is
// the silhouette there; the analytic SDF may approximate it by a pixel.
uniform float uExteriorOnly;
// Luminance of the neutral glint target: FakeGlass cannot scale it by the
// face it cannot see, so clear glass uses its best constant.
uniform float uGlintLuminance;
// Premultiplied emission of the face the backdrop filter produced, so the
// inner shadow can shade only the transmitted part of that face.
uniform vec3 uFaceEmission;
// Rounded superellipse parameters (see roundedSuperellipseParameters): the
// degree and spans, the circle centers, the semi-axis and radii, and a
// pair's bottom half after them (see roundedSuperellipsePairParameters). One
// array: Metal gives every uniform declaration a buffer of its own, and a
// stage has 31.
uniform vec4 uRse[6];
#define uRseDegreeAndSpans uRse[0]
#define uRseCircleCenters uRse[1]
#define uRseSemiAxisAndRadii uRse[2]
#define uRseLowerDegreeAndSpans uRse[3]
#define uRseLowerCircleCenters uRse[4]
#define uRseLowerSemiAxisAndRadii uRse[5]
// Face contribution to the glint target (see the color model's
// glintFaceGain and glintVibrancy). FakeGlass approximates the face with
// the surface tint plus emission; clear glass brightens that proxy
// strongly while regular glass brightens mostly the transmitted chroma.
uniform float uGlintFaceGain;
uniform float uGlintVibrancy;
// 1 when drawing only the additive highlight pass. FakeGlass paints the
// surface first and adds the glint in a second draw so the highlight can
// exceed the surface's premultiplied alpha (and SDR white) without clamping
// the translucent face.
uniform float uHighlightsOnly;
// A pair's bottom corner radius (LiquidRoundedSuperellipse.bottomRadius), or
// -1 for one radius. Below the split line the shape is then its bottom half,
// a squircle centered on the line.
uniform float uBottomRadius;

const vec3 LUMA_WEIGHTS = vec3(0.2126, 0.7152, 0.0722);
// The reference rim's peak is lower than a source-over mix of the same glint
// target. The additive pass only adds light, so scale it to the measured
// profile instead of replacing the face.
const float kAdditiveHighlightScale = 0.75;

layout(location = 0) out vec4 fragColor;

#include "fake_glass_shape.glsl"

float shapeDistance(vec2 p) {
  if (uBottomRadius < 0.0) {
    return sdFakeGlassShape(
      uShapeType,
      p,
      uSize * 0.5,
      uCornerRadius,
      uRseDegreeAndSpans,
      uRseCircleCenters,
      uRseSemiAxisAndRadii
    );
  }
  // The pair's halves, as real glass resolves them (gpu/sdf.glsl's
  // resolvePairHalf and pairOtherEdge).
  float upper = uRseSemiAxisAndRadii.y;
  float lower = uRseLowerSemiAxisAndRadii.y;
  vec2 q = vec2(p.x, p.y - 0.5 * (upper - lower));
  if (q.y > 0.0) {
    float d = sdFakeGlassShape(
      2.0,
      q,
      vec2(uSize.x * 0.5, lower),
      uBottomRadius,
      uRseLowerDegreeAndSpans,
      uRseLowerCircleCenters,
      uRseLowerSemiAxisAndRadii
    );
    return max(d, -(upper + q.y));
  }
  float d = sdFakeGlassShape(
    2.0,
    q,
    vec2(uSize.x * 0.5, upper),
    uCornerRadius,
    uRseDegreeAndSpans,
    uRseCircleCenters,
    uRseSemiAxisAndRadii
  );
  return max(d, q.y - lower);
}

vec2 shapeNormal(vec2 p) {
  vec2 halfSize = uSize * 0.5;
  if (uShapeType < 0.5) {
    vec2 radius = max(halfSize, vec2(0.001));
    return normalize(p / (radius * radius) + vec2(0.00001));
  }
  float cornerRadius = uCornerRadius;
  if (uBottomRadius >= 0.0) {
    float upper = uRseSemiAxisAndRadii.y;
    float lower = uRseLowerSemiAxisAndRadii.y;
    p.y -= 0.5 * (upper - lower);
    halfSize.y = p.y > 0.0 ? lower : upper;
    cornerRadius = p.y > 0.0 ? uBottomRadius : uCornerRadius;
  }
  float radius = clamp(cornerRadius, 0.0, min(halfSize.x, halfSize.y));
  vec2 q = abs(p) - halfSize + vec2(radius);
  vec2 corner = max(q, 0.0);
  if (dot(corner, corner) > 0.0001) {
    return normalize(corner) * sign(p);
  }
  return q.x > q.y ? vec2(sign(p.x), 0.0) : vec2(0.0, sign(p.y));
}

// Integral of the border ramp from the silhouette to outward distance t, all
// in physical pixels. See contourIntegral in the final render shader.
float contourIntegral(float t, float offset, float width) {
  float u = clamp(t - offset, 0.0, width);
  return u - u * u / (2.0 * width);
}

void main() {
  vec2 position = FlutterFragCoord().xy - uSize * 0.5;
  float distance = shapeDistance(position);
  float inward = max(-distance, 0.0);

  vec2 normal = shapeNormal(position);
  vec2 lightDirection = normalize(uLightDirection + vec2(0.00001));
  float facing = dot(normal, -lightDirection);

  // Same SDF-space lighting contract as RealGlass (see
  // liquid_glass_final_render_core.glsl): a one-sided exterior border and a
  // glint line anchored at the silhouette.
  float tangency = abs(dot(normal, vec2(-lightDirection.y, lightDirection.x)));

  float glintWidth = max(
    uHighlightWidth > 0.0 ? uHighlightWidth : uContourWidth,
    0.001
  );
  float glintProfile =
      clamp(1.0 - inward / glintWidth, 0.0, 1.0) +
      0.21 * clamp(1.0 - inward / (glintWidth * 4.0), 0.0, 1.0);
  float wrapExponent = exp2(2.0 - 4.0 * clamp(uHighlightWrap, 0.0, 1.0));
  float lobe = pow(max(1.0 - tangency, 0.0), wrapExponent);
  float returnWeight = facing >= 0.0
      ? 1.0
      : clamp(uOppositeHighlight, 0.0, 1.0);
  float glint = clamp(
    max(uHighlight, 0.0) * 0.252 * lobe * returnWeight * glintProfile,
    0.0,
    1.0
  );

  float tintAlpha = uTint.a;
  // The glint adds a bright target on top of the lit face. Without backdrop
  // access FakeGlass approximates the face with the surface tint plus
  // emission; only RealGlass amplifies the true backdrop chroma under the
  // glint and keeps the headroom above white.
  vec3 faceProxy = uTint.rgb * tintAlpha + uFaceEmission;
  vec3 glintTarget = vec3(uGlintLuminance) +
      uGlintFaceGain * faceProxy +
      uGlintVibrancy * (faceProxy - vec3(dot(faceProxy, LUMA_WEIGHTS)));
  float materialCoverage = uExteriorOnly > 0.5
      ? 0.0
      : clamp(0.5 - distance / uPixelSize, 0.0, 1.0);
  if (uHighlightsOnly > 0.5) {
    // Additive pass: emit only the glint's light. Alpha stays zero so the
    // destination face keeps its own coverage; RGB is premultiplied by the
    // glint weight (not by alpha) and may exceed one on an extended-range
    // target.
    fragColor = vec4(
      max(glintTarget, vec3(0.0)) * glint * materialCoverage *
          kAdditiveHighlightScale,
      0.0
    );
    return;
  }
  // The border is box-filtered over one physical pixel, split at the
  // silhouette, so a sub-pixel border does not alias into a dotted line.
  float outwardPixels = distance / uPixelSize;
  float contourOffsetPixels = uContourOffset / uPixelSize;
  float contourWidthPixels = uContourWidth / uPixelSize;
  vec2 contourBand = vec2(0.0);
  if (uContourWidth > 0.0) {
    float lower = outwardPixels - 0.5;
    float upper = outwardPixels + 0.5;
    contourBand = vec2(
      contourIntegral(max(upper, 0.0), contourOffsetPixels, contourWidthPixels) -
          contourIntegral(max(lower, 0.0), contourOffsetPixels, contourWidthPixels),
      contourIntegral(min(upper, 0.0), contourOffsetPixels, contourWidthPixels) -
          contourIntegral(min(lower, 0.0), contourOffsetPixels, contourWidthPixels)
    );
  }
  float contourStrength = clamp(uContourStrength, 0.0, 1.0) *
      mix(1.0, tangency, clamp(uContourDirectionality, 0.0, 1.0));
  float silhouetteCoverage = clamp(0.5 - outwardPixels, 0.0, 1.0);
  // In-material share of the border, relative to the material's coverage.
  float contourAbsorption = clamp(
    contourBand.y / max(silhouetteCoverage, 0.001) * contourStrength,
    0.0,
    1.0
  );
  float backdropContourAbsorption = contourAbsorption *
      (1.0 - clamp(uContourTransmittance, 0.0, 1.0));
  float bevelShadow = 0.0;

  float bevelDepth = max(uBevelDepth, 0.001);
  float sizeProgress = smoothstep(
    bevelDepth * 3.5,
    bevelDepth * 5.0,
    min(uSize.x, uSize.y) * 0.5
  );
  float bevelEnergy = mix(
    1.0,
    1.875,
    sizeProgress * clamp(uBevelSizeResponse, 0.0, 1.0)
  );
  // The rim's band is displaced along the light, as in RealGlass.
  float bevelShift = max(uBevelOffset, 0.0) * facing;
  float bevelPenumbra = 2.0 * bevelShift;
  float bevelLeading = bevelPenumbra > 0.001
      ? smoothstep(0.0, bevelPenumbra, inward)
      : 1.0;
  float bevelFalloff = 1.0 - smoothstep(0.0, bevelDepth, inward - bevelShift);
  float wrappedFacing = smoothstep(0.0, 1.0, facing * 0.5 + 0.5);
  float directionalShadow = mix(
    1.0,
    wrappedFacing,
    clamp(uBevelDirectionality, 0.0, 1.0)
  );
  bevelShadow = clamp(
    bevelLeading * bevelFalloff * directionalShadow *
        uBevelStrength * bevelEnergy,
    0.0,
    1.0
  );
  float backdropAbsorption = 1.0 -
      (1.0 - backdropContourAbsorption) * (1.0 - bevelShadow);
  float materialAlpha = 1.0 - (1.0 - tintAlpha) *
      (1.0 - backdropAbsorption);
  float exteriorContourAlpha = clamp(contourBand.x * contourStrength, 0.0, 1.0);
  // The inner shadow absorbs the filtered face, which includes the face's
  // own emission; adding that share back leaves only the transmitted light
  // shaded, as in RealGlass.
  vec3 litPremultiplied =
      uTint.rgb * tintAlpha * (1.0 - contourAbsorption) +
      uFaceEmission * bevelShadow * (1.0 - tintAlpha) *
          (1.0 - backdropContourAbsorption);
  float litAlpha = materialAlpha;
  // Keep the surface's premultiplied color within alpha as Skia needs. The
  // separate additive highlight pass carries the glint, including headroom
  // above SDR white on an extended-range target.
  if (litAlpha < 0.999) {
    litPremultiplied = min(litPremultiplied, vec3(1.0));
    litAlpha = max(
      litAlpha,
      max(max(litPremultiplied.r, litPremultiplied.g), litPremultiplied.b)
    );
  }
  float alpha = litAlpha * materialCoverage + exteriorContourAlpha;
  fragColor = vec4(
    max(litPremultiplied * materialCoverage, vec3(0.0)),
    clamp(alpha, 0.0, 1.0)
  );
}

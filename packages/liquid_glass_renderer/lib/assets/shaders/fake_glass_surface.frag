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
// Rounded superellipse parameters (see roundedSuperellipseParameters).
uniform vec4 uRseDegreeAndSpans;
uniform vec4 uRseCircleCenters;
uniform vec4 uRseSemiAxisAndRadii;

layout(location = 0) out vec4 fragColor;

#include "fake_glass_shape.glsl"

float shapeDistance(vec2 p) {
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

vec2 shapeNormal(vec2 p) {
  vec2 halfSize = uSize * 0.5;
  if (uShapeType < 0.5) {
    vec2 radius = max(halfSize, vec2(0.001));
    return normalize(p / (radius * radius) + vec2(0.00001));
  }
  float radius = clamp(uCornerRadius, 0.0, min(halfSize.x, halfSize.y));
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
  // The glint pulls the lit face toward a target 1.6x SDR white. Without
  // backdrop access FakeGlass pulls toward it with source-over of an
  // emissive target; only RealGlass also amplifies the face chroma under the
  // glint and keeps the headroom above white.
  float materialCoverage = uExteriorOnly > 0.5
      ? 0.0
      : clamp(0.5 - distance / uPixelSize, 0.0, 1.0);
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
  litPremultiplied =
      litPremultiplied * (1.0 - glint) + vec3(uGlintLuminance * glint);
  litAlpha = 1.0 - (1.0 - litAlpha) * (1.0 - glint);
  // FakeGlass stays SDR, as Skia needs: premultiplied color never exceeds
  // alpha. Where the glint's emission would, the glass covers that much more
  // of the backdrop, so the composite reaches SDR white but never exceeds it.
  litPremultiplied = min(litPremultiplied, vec3(1.0));
  litAlpha = max(
    litAlpha,
    max(max(litPremultiplied.r, litPremultiplied.g), litPremultiplied.b)
  );
  float alpha = litAlpha * materialCoverage + exteriorContourAlpha;
  fragColor = vec4(
    max(litPremultiplied * materialCoverage, vec3(0.0)),
    clamp(alpha, 0.0, 1.0)
  );
}

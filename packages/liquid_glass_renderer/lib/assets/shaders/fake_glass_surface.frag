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
uniform float uBevelStrength;
uniform float uBevelDepth;
uniform float uBevelOffset;
uniform float uBevelDirectionality;
uniform float uBevelSizeResponse;
uniform vec2 uLightDirection;

layout(location = 0) out vec4 fragColor;

float sdRoundedBox(vec2 p, vec2 halfSize, float radius) {
  radius = clamp(radius, 0.0, min(halfSize.x, halfSize.y));
  vec2 q = abs(p) - halfSize + vec2(radius);
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

float sdEllipse(vec2 p, vec2 radius) {
  radius = max(radius, vec2(0.001));
  float k0 = length(p / radius);
  float k1 = length(p / (radius * radius));
  return k0 * (k0 - 1.0) / max(k1, 0.001);
}

float shapeDistance(vec2 p) {
  vec2 halfSize = uSize * 0.5;
  if (uShapeType < 0.5) {
    return sdEllipse(p, halfSize);
  }
  return sdRoundedBox(p, halfSize, uCornerRadius);
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

void main() {
  vec2 position = FlutterFragCoord().xy - uSize * 0.5;
  float distance = shapeDistance(position);
  float inward = max(-distance, 0.0);

  vec2 normal = shapeNormal(position);
  vec2 lightDirection = normalize(uLightDirection + vec2(0.00001));
  float facing = dot(normal, -lightDirection);

  // Keep the public settings in the same SDF-space contract as RealGlass.
  // The fixed feather mirrors the runtime-effect shader, where derivatives
  // are unavailable.
  const float edgeFeather = 0.75;
  const float contourFeather = 1.0;
  float contourHalfWidth = max(uContourWidth, 0.0) * 0.5;
  float contourBand = uContourWidth > 0.0
      ? 1.0 - smoothstep(
          max(contourHalfWidth - contourFeather, 0.0),
          contourHalfWidth + contourFeather,
          abs(distance + uContourOffset)
        )
      : 0.0;
  // Keep contour strength in the same linear contract as RealGlass. The 0.95
  // calibration compensates for fixed-function srcOver coverage; a previous
  // fifth-power response turned the default 0.15 into 0.56 coverage and made
  // the fallback visibly darker when switching materials.
  float displayedContourStrength = clamp(uContourStrength * 0.95, 0.0, 1.0);
  float contourAbsorption = clamp(
    contourBand * displayedContourStrength,
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
  float bevelOffset = min(max(uBevelOffset, 0.0), bevelDepth - 0.001);
  float bevelLeading = bevelOffset > 0.001
      ? smoothstep(0.0, bevelOffset, inward)
      : 1.0;
  float bevelFalloff = 1.0 - smoothstep(
    bevelOffset,
    max(bevelDepth, bevelOffset + 0.001),
    inward
  );
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

  float opticalThickness = max(uThickness, 1.0);
  float edgeWidth = min(max(uHighlightWidth, 0.0), opticalThickness * 0.5);
  float highlightInset = edgeWidth * 0.25;
  float innerRim = edgeWidth > 0.0
      ? smoothstep(
          highlightInset - edgeFeather,
          highlightInset + edgeFeather,
          inward
        )
      : 1.0;
  float thicknessScale = clamp(40.0 / opticalThickness, 1.0, 4.0);
  float edgeThreshold = mix(0.8, 0.5, 1.0 / thicknessScale);
  float shiftedRatio = clamp(
    max(inward - highlightInset, 0.0) / opticalThickness,
    0.0,
    1.0
  );
  float shiftedHeight = sqrt(max(0.0, shiftedRatio * (2.0 - shiftedRatio)));
  float highlightBand =
      (1.0 - smoothstep(0.0, edgeThreshold, shiftedHeight)) * innerRim;
  float wrapCenter = mix(0.96, -0.3, uHighlightWrap);
  float wrapSoftness = mix(0.04, 0.3, uHighlightWrap);
  float primary = smoothstep(wrapCenter - wrapSoftness, 1.0, max(facing, 0.0));
  float opposite = smoothstep(
    wrapCenter - wrapSoftness,
    1.0,
    max(-facing, 0.0)
  ) * uOppositeHighlight;
  float light = highlightBand * (primary + opposite) * uHighlight * 0.8;

  float tintAlpha = uTint.a;
  // Encode attenuation in coverage alpha, but keep incident specular energy
  // in RGB. Including the highlight in alpha turns srcOver into a screen-like
  // blend, which is visibly dimmer than RealGlass's post-material additive
  // highlight on midtone and light backdrops. Runtime-effect output may be
  // emissive (RGB > alpha); the fixed-function blend then evaluates the same
  // affine form as the full material shader without adding a second draw.
  float materialCoverage = 1.0 - smoothstep(
    -edgeFeather,
    edgeFeather,
    distance
  );
  float backdropAbsorption = 1.0 -
      (1.0 - backdropContourAbsorption) * (1.0 - bevelShadow);
  float materialAlpha = 1.0 - (1.0 - tintAlpha) *
      (1.0 - backdropAbsorption);
  // Match RealGlass's affine contour composition under fixed-function
  // srcOver: transmittance preserves only the backdrop component, while the
  // tint is absorbed at the full contour strength and specular remains
  // additive so it can eclipse the dark edge.
  float exteriorContourAlpha = contourAbsorption *
      (1.0 - materialCoverage);
  float alpha = materialAlpha * materialCoverage + exteriorContourAlpha;
  vec3 premultiplied =
      (uTint.rgb * tintAlpha * (1.0 - contourAbsorption) *
          (1.0 - bevelShadow) + vec3(light)) *
      materialCoverage;
  fragColor = vec4(clamp(premultiplied, 0.0, 1.0), alpha);
}

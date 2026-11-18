// Copyright 2025, Tim Lehmann for whynotmake.it

#version 460 core
precision mediump float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
// impellerc gives every uniform declaration its own Metal buffer, bound per
// draw, where Vulkan binds one struct.
#include "fake_glass_lanes.glsl"
#include "shader_constants.glsl"
// Rounded superellipse parameters (see roundedSuperellipseParameters): the
// degree and spans, the circle centers, the semi-axis and radii, and a
// pair's bottom half after them (see roundedSuperellipsePairParameters). One
// array: Metal gives every uniform declaration a buffer of its own, and a
// stage has 31.
uniform vec4 uRse[2 * SQUIRCLE_ROW_VEC4S];
#define uRseDegreeAndSpans uRse[SQUIRCLE_DEGREES_AND_SPANS]
#define uRseCircleCenters uRse[SQUIRCLE_CIRCLE_CENTERS]
#define uRseSemiAxisAndRadii uRse[SQUIRCLE_AXES_AND_RADII]
#define uRseLowerDegreeAndSpans \
    uRse[SQUIRCLE_ROW_VEC4S + SQUIRCLE_DEGREES_AND_SPANS]
#define uRseLowerCircleCenters uRse[SQUIRCLE_ROW_VEC4S + SQUIRCLE_CIRCLE_CENTERS]
#define uRseLowerSemiAxisAndRadii \
    uRse[SQUIRCLE_ROW_VEC4S + SQUIRCLE_AXES_AND_RADII]
layout(location = 0) out vec4 fragColor;

#define SHAPE_SDF_FIRST_ORDER
#include "shape_sdf.glsl"

// Deeper than 6 pt inside, where only the soft bevel reads the distance, a superellipse
// uses its rounded box (they agree to about half a point there).
float fakeGlassShapeDistance(
  float type,
  vec2 p,
  vec2 halfSize,
  float radius,
  vec4 degreeAndSpans,
  vec4 circleCenters,
  vec4 semiAxisAndRadii
) {
  if (abs(type - SHAPE_ELLIPSE) < 0.5) {
    return sdfEllipse(p, halfSize);
  }
  float box = sdfRRect(p, halfSize, radius);
  if (abs(type - SHAPE_ROUNDED_RECTANGLE) < 0.5 || box < -6.0) {
    return box;
  }
  float superellipse = sdfSquircle(
    p,
    halfSize,
    min(radius, min(halfSize.x, halfSize.y)),
    degreeAndSpans,
    circleCenters,
    semiAxisAndRadii
  );
  return mix(superellipse, box, smoothstep(4.0, 6.0, -box));
}

PairSplit pairSplit() {
  return PairSplit(uRseSemiAxisAndRadii.y, uRseLowerSemiAxisAndRadii.y);
}

float shapeDistance(vec2 p) {
  if (uBottomRadius < 0.0) {
    return fakeGlassShapeDistance(
      uShapeType,
      p,
      uSize * 0.5,
      uCornerRadius,
      uRseDegreeAndSpans,
      uRseCircleCenters,
      uRseSemiAxisAndRadii
    );
  }
  PairSplit split = pairSplit();
  vec2 q = fromSplitLine(p, split);
  float d = q.y > 0.0
      ? fakeGlassShapeDistance(
          SHAPE_SQUIRCLE,
          q,
          vec2(uSize.x * 0.5, split.below),
          uBottomRadius,
          uRseLowerDegreeAndSpans,
          uRseLowerCircleCenters,
          uRseLowerSemiAxisAndRadii
        )
      : fakeGlassShapeDistance(
          SHAPE_SQUIRCLE,
          q,
          vec2(uSize.x * 0.5, split.above),
          uCornerRadius,
          uRseDegreeAndSpans,
          uRseCircleCenters,
          uRseSemiAxisAndRadii
        );
  return max(d, -pairOtherEdge(q, split).distance);
}

vec2 shapeNormal(vec2 p) {
  vec2 halfSize = uSize * 0.5;
  if (abs(uShapeType - SHAPE_ELLIPSE) < 0.5) {
    vec2 radius = max(halfSize, vec2(0.001));
    return normalize(p / (radius * radius) + vec2(0.00001));
  }
  float cornerRadius = uCornerRadius;
  if (uBottomRadius >= 0.0) {
    PairSplit split = pairSplit();
    p = fromSplitLine(p, split);
    halfSize.y = p.y > 0.0 ? split.below : split.above;
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

#include "fake_glass_lighting.glsl"

void main() {
  vec2 position = FlutterFragCoord().xy - uSize * 0.5;
  float distance = shapeDistance(position);
  fragColor = fakeGlassLit(
    distance,
    shapeNormal(position),
    clamp(0.5 - distance / uPixelSize, 0.0, 1.0)
  );
}

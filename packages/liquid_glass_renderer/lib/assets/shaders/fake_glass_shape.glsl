// Copyright 2025, Tim Lehmann for whynotmake.it
//
// sdRoundedBox and sdEllipse follow Inigo Quilez's 2D distance functions
// (https://iquilezles.org/articles/distfunctions2d/), MIT License,
// Copyright © 2015 Inigo Quilez; see third_party/inigo_quilez/LICENSE.
// sdRoundedSuperellipse is adapted from Flutter's Impeller
// (impeller/entity/shaders/uber_sdf.frag, Flutter 3.47.1):
//   Copyright 2013 The Flutter Authors. All rights reserved.
//   Use of this source code is governed by a BSD-style license that can be
//   found in third_party/flutter/LICENSE.

// Signed distances of FakeGlass shapes, in logical pixels of the shape's
// centered local space. Shared by the analytic surface and the backdrop edge
// pass so both put the silhouette in the same place.

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

// First-order distance F / |grad F| to the unit superellipse
// |x|^n + |y|^n = 1. Near the silhouette it is within 0.03 pt of the
// six-step bisection real glass uses (0.12 pt within 6 pt), without its loop
// of sin, cos and pow.
float sdSuperellipseArc(vec2 p, float n) {
    p = abs(p) + vec2(1e-6);
    float s = pow(p.x, n) + pow(p.y, n);
    float f = pow(s, 1.0 / n) - 1.0;
    vec2 gradient = vec2(pow(p.x, n - 1.0), pow(p.y, n - 1.0)) *
        pow(s, 1.0 / n - 1.0);
    return f / max(length(gradient), 1e-3);
}

// Flutter 3.47's rounded superellipse (Impeller's symmetric UberSDF): per
// octant, a circular arc around the diagonal and a superellipse arc towards
// the edge midpoint. The parameters come from roundedSuperellipseParameters.
float sdRoundedSuperellipse(
    vec2 p,
    vec2 halfSize,
    float radius,
    vec4 degreeAndSpans,
    vec4 circleCenters,
    vec4 semiAxisAndRadii
) {
    if (radius <= 1e-4) {
        return max(abs(p).x - halfSize.x, abs(p).y - halfSize.y);
    }
    vec2 local = abs(p);
    float c = semiAxisAndRadii.x - semiAxisAndRadii.y;
    vec2 octant;
    float degree;
    float span;
    float axis;
    float circleRadius;
    vec2 circleCenter;
    if (local.y + c > local.x) {
        octant = local + vec2(0.0, c);
        degree = degreeAndSpans.x;
        axis = semiAxisAndRadii.x;
        span = degreeAndSpans.z;
        circleCenter = circleCenters.xy;
        circleRadius = semiAxisAndRadii.z;
    } else {
        octant = local.yx - vec2(0.0, c);
        degree = degreeAndSpans.y;
        axis = semiAxisAndRadii.y;
        span = degreeAndSpans.w;
        circleCenter = circleCenters.zw;
        circleRadius = semiAxisAndRadii.w;
    }
    vec2 relative = octant - circleCenter;
    float deltaTheta = atan(relative.y, relative.x) - 0.78539816;
    deltaTheta = mod(deltaTheta + 3.14159265, 6.28318531) - 3.14159265;
    if (abs(deltaTheta) < abs(span)) {
        return length(relative) - circleRadius;
    }
    if (degree < 2.0) {
        return max(abs(octant).x - axis, abs(octant).y - axis);
    }
    return sdSuperellipseArc(octant / max(axis, 1e-4), degree) * axis;
}

// type: 0 oval, 1 rounded rectangle, 2 rounded superellipse. Deeper than
// 6 pt inside, where only the soft bevel reads the distance, a superellipse
// uses its rounded box (they agree to about half a point there).
float sdFakeGlassShape(
    float type,
    vec2 p,
    vec2 halfSize,
    float radius,
    vec4 degreeAndSpans,
    vec4 circleCenters,
    vec4 semiAxisAndRadii
) {
    if (type < 0.5) {
        return sdEllipse(p, halfSize);
    }
    float box = sdRoundedBox(p, halfSize, radius);
    if (type < 1.5 || box < -6.0) {
        return box;
    }
    float superellipse = sdRoundedSuperellipse(
        p,
        halfSize,
        min(radius, min(halfSize.x, halfSize.y)),
        degreeAndSpans,
        circleCenters,
        semiAxisAndRadii
    );
    return mix(superellipse, box, smoothstep(4.0, 6.0, -box));
}

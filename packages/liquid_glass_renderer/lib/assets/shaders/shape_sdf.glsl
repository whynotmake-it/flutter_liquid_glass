// Copyright 2025, Tim Lehmann for whynotmake.it
//
// sdfRRect, rseSuperellipse, sdfSquircle and sdfEllipse are adapted from
// Flutter's Impeller shaders (impeller/entity/shaders/uber_sdf.frag and
// sdf_functions.glsl, Flutter 3.47.1):
//   Copyright 2013 The Flutter Authors. All rights reserved.
//   Use of this source code is governed by a BSD-style license that can be
//   found in third_party/flutter/LICENSE.
// rseSuperellipse also derives from Inigo Quilez's superellipse distance
// (https://iquilezles.org/articles/ellipsedist/), and sdfEllipse's first
// order from his 2D distance functions
// (https://iquilezles.org/articles/distfunctions2d/), MIT License,
// Copyright © 2015 Inigo Quilez; see third_party/inigo_quilez/LICENSE.

#ifndef SHAPE_SDF_GLSL
#define SHAPE_SDF_GLSL

float sdfRRect( in vec2 p, in vec2 b, in float r ) {
    float shortest = min(b.x, b.y);
    r = min(r, shortest);
    vec2 q = abs(p)-b+r;
    return min(max(q.x,q.y),0.0) + length(max(q,0.0)) - r;
}

// Signed distance to the implicit superellipse used by Flutter's RSE shader.
// The six fixed bisection steps are the same bounded-cost approximation used
// by Flutter and are sufficient at device-pixel scale.
float rseSuperellipse(vec2 p, float n) {
    const float twoPi = 6.28318531;
    p = abs(p);
    if (p.y > p.x) p = p.yx;

    n = 2.0 / n;
    float xa = 0.0;
    float xb = twoPi / 8.0;
    for (int i = 0; i < 6; i++) {
        float x = 0.5 * (xa + xb);
        float c = cos(x);
        float s = sin(x);
        float cn = pow(c, n);
        float sn = pow(s, n);
        float y = (p.x - cn) * cn * s * s -
            (p.y - sn) * sn * c * c;
        if (y < 0.0) xa = x;
        else xb = x;
    }

    vec2 qa = pow(vec2(cos(xa), sin(xa)), vec2(n));
    vec2 qb = pow(vec2(cos(xb), sin(xb)), vec2(n));
    vec2 pa = p - qa;
    vec2 ba = qb - qa;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
    return length(pa - ba * h) * sign(pa.x * ba.y - pa.y * ba.x);
}

#ifdef SHAPE_SDF_FIRST_ORDER
float firstOrderSuperellipse(vec2 p, float n) {
    p = abs(p) + vec2(1e-6);
    float s = pow(p.x, n) + pow(p.y, n);
    float f = pow(s, 1.0 / n) - 1.0;
    vec2 gradient = vec2(pow(p.x, n - 1.0), pow(p.y, n - 1.0)) *
        pow(s, 1.0 / n - 1.0);
    return f / max(length(gradient), 1e-3);
}
#endif

float sdfSquircle(
    vec2 p,
    vec2 b,
    float r,
    vec4 degreeAndSpans,
    vec4 circleCenters,
    vec4 semiAxisAndRadii
) {
    if (r <= 1e-4) {
        return max(abs(p).x - b.x, abs(p).y - b.y);
    }
    // This is Flutter 3.47's distanceFromRoundedSuperellipse from
    // `impeller/entity/shaders/uber_sdf.frag`, with its symmetric scale folded
    // out. Keeping the CPU-fitted semi-axes and circular-cap radii instead of
    // reconstructing the cap radius in the fragment avoids the small
    // straight-to-corner lip caused by divergent floating-point constructions.
    vec2 folded = abs(p);
    float c = semiAxisAndRadii.x - semiAxisAndRadii.y;
    vec2 octant;
    float degree;
    float cosSpan;
    float axis;
    float circleRadius;
    vec2 circleCenter;
    if (folded.y + c > folded.x) {
        octant = folded + vec2(0.0, c);
        degree = degreeAndSpans.x;
        axis = semiAxisAndRadii.x;
        cosSpan = 1.0 - degreeAndSpans.z;
        circleCenter = circleCenters.xy;
        circleRadius = semiAxisAndRadii.z;
    } else {
        octant = folded.yx - vec2(0.0, c);
        degree = degreeAndSpans.y;
        axis = semiAxisAndRadii.y;
        cosSpan = 1.0 - degreeAndSpans.w;
        circleCenter = circleCenters.zw;
        circleRadius = semiAxisAndRadii.w;
    }
    // Inside the circular cap's angular span around the 45-degree diagonal.
    // The span arrives as 1 - cos(span), so this is Flutter's atan2 test
    // without the trigonometry, and a zero payload still means no cap.
    vec2 relative = octant - circleCenter;
    float relativeLength = length(relative);
    if (dot(relative, vec2(0.70710678)) > relativeLength * cosSpan) {
        return relativeLength - circleRadius;
    }
    if (degree < 2.0) {
        return max(abs(octant).x - axis, abs(octant).y - axis);
    }
    // A superellipse of degree 2 is a circle, so a capsule's ends and a
    // circle's outline need no solve, and come out exact where the solve
    // walks 64 chords.
    if (degree == 2.0) {
        return length(octant) - axis;
    }
    // Along its side the curve is y = axis * (1 - u^n / n), u the share of
    // the semi-axis from the side's middle, and its slope is u^(n - 1).
    // While that slope is under 0.02 the distance is the gap to the curve
    // straight across, shortened by the slope's cosine: within 0.004 px of
    // the solve's answer 60 px to either side, which is the solve's own
    // error. It covers most of the ring of a bar or a sheet.
    float side = octant.x / max(axis, 1e-4);
    float sideN = pow(side, degree);
    float slope = sideN / max(side, 1e-3);
    if (slope < 0.02) {
        return (octant.y - axis + axis * sideN / degree) *
            (1.0 - 0.5 * slope * slope);
    }
#ifdef SHAPE_SDF_FIRST_ORDER
    return firstOrderSuperellipse(octant / max(axis, 1e-4), degree) * axis;
#else
    return rseSuperellipse(octant / max(axis, 1e-4), degree) * axis;
#endif
}

float sdfEllipse(vec2 p, vec2 r) {
#ifdef SHAPE_SDF_FIRST_ORDER
    r = max(r, vec2(0.001));
    float k0 = length(p / r);
    float k1 = length(p / (r * r));
    return k0 * (k0 - 1.0) / max(k1, 0.001);
#else
    // Impeller's oval SDF: a fixed five-step Newton solve. Closed-form
    // approximations divide by |p| near the center, which leaves a pinhole in
    // non-circular ovals.
    r = max(r, 1e-4);
    // A circle needs no solve.
    if (r.x == r.y) {
        return length(p) - r.x;
    }
    p = abs(p);
    vec2 q = r * (p - r);
    float angle = q.x < q.y ? 1.570796327 : 0.0;
    for (int i = 0; i < 5; i++) {
        vec2 cs = vec2(cos(angle), sin(angle));
        vec2 u = r * cs;
        vec2 v = r * vec2(-cs.y, cs.x);
        angle += dot(p - u, v) /
            max(dot(p - u, u) + dot(v, v), 1e-6);
    }
    float distance = length(p - r * vec2(cos(angle), sin(angle)));
    return dot(p / r, p / r) > 1.0 ? distance : -distance;
#endif
}

struct PairSplit {
    float above;
    float below;
};

vec2 fromSplitLine(vec2 p, PairSplit split) {
    return vec2(p.x, p.y - 0.5 * (split.above - split.below));
}

struct PairEdge {
    float distance;
    vec2 normal;
};

PairEdge pairOtherEdge(vec2 fromSplit, PairSplit split) {
    if (fromSplit.y > 0.0) {
        return PairEdge(split.above + fromSplit.y, vec2(0.0, -1.0));
    }
    return PairEdge(split.below - fromSplit.y, vec2(0.0, 1.0));
}

#endif

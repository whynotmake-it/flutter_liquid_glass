// Copyright 2025, Tim Lehmann for whynotmake.it
//
// sdfRRect, rseSuperellipse, sdfSquircle and sdfEllipse are adapted from
// Flutter's Impeller shaders (impeller/entity/shaders/uber_sdf.frag and
// sdf_functions.glsl, Flutter 3.47.1):
//   Copyright 2013 The Flutter Authors. All rights reserved.
//   Use of this source code is governed by a BSD-style license that can be
//   found in third_party/flutter/LICENSE.
// rseSuperellipse also derives from Inigo Quilez's superellipse distance
// (https://iquilezles.org/articles/ellipsedist/), MIT License,
// Copyright © 2015 Inigo Quilez; see third_party/inigo_quilez/LICENSE.

// Three vec4s per shape: primitive parameters, inverse affine basis, and
// transformed center/distance/group data. RSE parameters use three vec4s per
// shape: degrees/(1 - cos span), circle centers, and semi-axes/radii. This is the
// lossless symmetric subset of Flutter's Impeller UberSDF payload: corners
// are circular, so its signed scale is always 1.
//
// A pair (type 4) is a rounded superellipse whose two top corners share one
// radius and two bottom corners another, as Impeller's MakeBoundsRadii builds
// it. Its uRseData rows describe the top half and the rows at
// MAX_SHAPES * 3 + index * 3 the bottom half, each a symmetric rounded
// superellipse centered on the split line; the bottom rows' half width slot
// carries the bottom radius.

// The helpers read the shapes from the uniforms rather than taking them as
// parameters, so no shape array is ever passed, and copied, by value. A
// shader that declares uShapeData, uRseData and uShapeBounds itself
// (shape_geometry.glsl) defines GEOMETRY_UNIFORMS_GLSL first.
#ifndef GEOMETRY_UNIFORMS_GLSL
#include "geometry_uniforms.glsl"
#endif

// Whether a scene sample carries its shapes' look (looks.glsl), blended by
// the smooth union's weight over its full radius, as halfMinor is.
#ifndef SCENE_LOOKS
#define SCENE_LOOKS 0
#endif
#if SCENE_LOOKS
#include "looks.glsl"
#endif

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
    vec2 local = abs(p);
    vec2 normalized = local;
    float c = semiAxisAndRadii.x - semiAxisAndRadii.y;
    vec2 octant;
    float degree;
    float cosSpan;
    float axis;
    float circleRadius;
    vec2 circleCenter;
    if (normalized.y + c > normalized.x) {
        octant = normalized + vec2(0.0, c);
        degree = degreeAndSpans.x;
        axis = semiAxisAndRadii.x;
        cosSpan = 1.0 - degreeAndSpans.z;
        circleCenter = circleCenters.xy;
        circleRadius = semiAxisAndRadii.z;
    } else {
        octant = normalized.yx - vec2(0.0, c);
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
    return rseSuperellipse(octant / max(axis, 1e-4), degree) * axis;
}

float sdfEllipse(vec2 p, vec2 r) {
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
}

float getShapeSDF(
    float type,
    vec2 p,
    vec2 center,
    vec2 size,
    float r,
    vec4 rseDegreeAndSpans,
    vec4 rseCircleCenters,
    vec4 rseSemiAxisAndRadii
) {
    if (type == 1.0) { // squircle
        return sdfSquircle(
            p - center,
            size / 2.0,
            r,
            rseDegreeAndSpans,
            rseCircleCenters,
            rseSemiAxisAndRadii
        );
    }
    if (type == 2.0) { // ellipse
        return sdfEllipse(p - center, size / 2.0);
    }
    if (type == 3.0) { // rounded rectangle
        return sdfRRect(p - center, size / 2.0, r);
    }
    return 1e9; // none
}

struct SceneSample {
    float distance;
    float halfMinor;
    // Gradients of the distance (see getShapeGradients), blended like the
    // distance itself for a group. `normal` has the true corners and sets the
    // blend angle; `opticalNormal` has smoothed corners and drives
    // refraction, lighting and antialiasing.
    vec2 normal;
    vec2 opticalNormal;
#if SCENE_LOOKS
    Look look;
#endif
};

// Apple's glass turns its optical normal before a corner starts, as if the
// corner radius were larger; normals from a 1.5x radius match iOS 27 card
// corners. Capsules are unchanged.
const float kOpticalCornerRadiusScale = 1.5;

// Scene-space gradients of a primitive's distance: xy with its true corners
// (the blend angle), zw with corners from a radius scaled by
// kOpticalCornerRadiusScale (refraction and lighting). Both carry the
// distance's gradient magnitude, which the geometry pass also uses for
// antialiasing.
//
// They are analytic, so they are exact per pixel: derivatives of the distance
// are shared by 2x2 quads on many GPUs, which leaves steps on tight curves,
// and fine derivatives do not compile for GLES 3.0. Rounded rectangles and
// continuous corners use the rounded-rectangle gradient; ellipses use the
// gradient of their implicit equation, which is exact on the outline.
vec4 getShapeGradients(
    vec4 primitive,
    vec4 inverseBasis,
    float distanceScale,
    vec2 localPoint,
    bool withExact
) {
    vec2 halfSize = primitive.yz * 0.5;
    vec2 exact;
    vec2 optical;
    if (primitive.x == 2.0) {
        exact = normalize(localPoint / max(halfSize * halfSize, 1e-4));
        optical = exact;
    } else {
        vec2 side = vec2(
            localPoint.x < 0.0 ? -1.0 : 1.0,
            localPoint.y < 0.0 ? -1.0 : 1.0
        );
        vec2 inset = abs(localPoint) - halfSize;
        float halfMinor = min(halfSize.x, halfSize.y);
        vec2 q = inset + min(primitive.w, halfMinor);
        vec2 axis = q.x > q.y ? vec2(side.x, 0.0) : vec2(0.0, side.y);
        exact = withExact && q.x > 0.0 && q.y > 0.0
            ? side * normalize(q)
            : axis;
        q = inset + min(primitive.w * kOpticalCornerRadiusScale, halfMinor);
        axis = q.x > q.y ? vec2(side.x, 0.0) : vec2(0.0, side.y);
        optical = q.x > 0.0 && q.y > 0.0 ? side * normalize(q) : axis;
    }
    // Distances transform with the inverse basis, so gradients use its
    // transpose.
    mat2 toScene = mat2(
        inverseBasis.x, inverseBasis.y,
        inverseBasis.z, inverseBasis.w
    ) * distanceScale;
    return vec4(toScene * exact, toScene * optical);
}

// What turns the optical gradient of a shape of [size], at [localPoint] from
// its center in its own axes, toward the line from its center: added to a
// gradient one long and made one long again, the two are mixed by
// turn / (1 + turn).
//
// iOS 27 mixes the normal of large regular glass half and half with the
// line from its center, taken where the shape is a square, so what shows
// through its rim leans along the edge near the corners. The center itself
// lies deeper than a bevel reads.
vec2 leanToCenter(
    vec2 localPoint,
    vec2 size,
    vec4 inverseBasis,
    float distanceScale,
    float turn
) {
    vec2 line = normalize(localPoint / size + 1e-6) * (turn * distanceScale);
    return vec2(
        inverseBasis.x * line.x + inverseBasis.z * line.y,
        inverseBasis.y * line.x + inverseBasis.w * line.y
    );
}

// Smooth-union radius for two surfaces with normals na and nb:
// k sin^2(theta / 2) = k (1 - cos theta) / 2, theta the angle between them.
// Zero where the surfaces are aligned, such as the collinear sides of shapes
// in a row, and the full blend where they face each other across a gap. A
// plain smooth minimum lifts aligned edges near a join by up to k/4; this
// keeps them straight while concave joins and bridges still round. On an
// iOS 27 device, the necks of UIGlassContainerEffect and SwiftUI's
// GlassEffectContainer give this radius within one percent.
float angularBlendRadius(float k, vec2 na, vec2 nb) {
    // Divided by the lengths so only the angle counts: gradients of stretched
    // shapes and of blended groups can be shorter than 1. The empty-pixel
    // reach a strip's quad carries assumes a radius of k at most.
    float cosine = dot(na, nb) / max(length(na) * length(nb), 1e-8);
    return k * clamp(0.5 * (1.0 - cosine), 0.0, 1.0);
}

// Weight of the first operand in a polynomial smooth minimum of radius k. It
// is also that operand's share of the result's gradient.
float smoothMinWeight(float a, float b, float k) {
    return clamp(0.5 + (b - a) / (2.0 * max(k, 1e-4)), 0.0, 1.0);
}

// The half of pair [index] the local point p lies in: moves p to that half's
// center on the split line and makes primitive that half's own squircle, its
// box twice the half's height. Both halves are vertical at the sides on the
// line, so the outline is continuous and exact there. Returns the half's first
// uRseData row.
int resolvePairHalf(int index, inout vec2 p, inout vec4 primitive) {
    float upper = uRseData[index * 3 + 2].y;
    vec4 lower = uRseData[MAX_SHAPES * 3 + index * 3 + 2];
    p.y -= 0.5 * (upper - lower.y);
    if (p.y > 0.0) {
        primitive = vec4(1.0, primitive.y, 2.0 * lower.y, lower.x);
        return MAX_SHAPES * 3 + index * 3;
    }
    primitive = vec4(1.0, primitive.y, 2.0 * upper, primitive.w);
    return index * 3;
}

// For a pair, with p moved by resolvePairHalf: the distance from p to the
// other half's straight edge across the split line, and that edge's outward
// normal. A half's own squircle is mirrored about the line, so a point near
// it would measure its depth to a mirrored edge instead of the real one, and
// the depth would jump by the halves' difference at the line.
vec3 pairOtherEdge(int index, vec2 p) {
    float upper = uRseData[index * 3 + 2].y;
    float lower = uRseData[MAX_SHAPES * 3 + index * 3 + 2].y;
    return p.y > 0.0
        ? vec3(upper + p.y, 0.0, -1.0)
        : vec3(lower - p.y, 0.0, 1.0);
}

float getShapeDistance(
    int index,
    vec2 p,
    vec4 primitive,
    vec4 inverseBasis,
    vec4 placement
) {
    vec2 delta = p - placement.xy;
    vec2 localPoint = vec2(
        inverseBasis.x * delta.x + inverseBasis.y * delta.y,
        inverseBasis.z * delta.x + inverseBasis.w * delta.y
    );
    int rse = index * 3;
    bool pair = primitive.x == 4.0;
    if (pair) {
        rse = resolvePairHalf(index, localPoint, primitive);
    }
    vec4 rseDegreeAndSpans = uRseData[rse];
    vec4 rseCircleCenters = uRseData[rse + 1];
    vec4 rseSemiAxisAndRadii = uRseData[rse + 2];
    // The bottom rows carry the radius where the shared half width sits.
    if (pair) {
        rseSemiAxisAndRadii.x = 0.5 * primitive.y;
    }
    float localDistance = getShapeSDF(
        primitive.x,
        localPoint,
        vec2(0.0),
        primitive.yz,
        primitive.w,
        rseDegreeAndSpans,
        rseCircleCenters,
        rseSemiAxisAndRadii
    );
    if (pair) {
        localDistance = max(localDistance, -pairOtherEdge(index, localPoint).x);
    }
    return localDistance * placement.z;
}

// Squared distance from p to the matte-space box around a primitive. The box
// contains the primitive under any affine transform, so this is a lower bound
// for the primitive's exact distance without mapping p into its local space.
float shapeBoundsDistanceSquared(vec4 bounds, vec2 p) {
    vec2 outside = max(max(bounds.xy - p, p - bounds.zw), 0.0);
    return dot(outside, outside);
}

// A primitive changes a group's smooth union only where its distance is below
// the group's distance plus the blend radius. Its box distance bounds that
// distance from below; inside the box nothing is proven.
bool cannotAffectGroup(vec4 bounds, vec2 p, float reach) {
    float outsideSquared = shapeBoundsDistanceSquared(bounds, p);
    return reach <= 0.0
        ? outsideSquared > 0.0
        : outsideSquared >= reach * reach;
}

// Squared distance from p to the nearest box of the count shapes from row
// first. Comparing squared values avoids one square root per shape in the
// empty-pixel fast path.
//
// Rows are masked to the block here and below: a software GPU runs both
// sides of a branch, the side not taken on whatever its inputs decode to.
float sceneBoundsOutsideSquared(vec2 p, int first, int count) {
    float lowerBoundSquared = 1e18;
    int shapeCount = count < MAX_SHAPES ? count : MAX_SHAPES;
    for (int i = 0; i < MAX_SHAPES; i++) {
        if (i >= shapeCount) break;
        lowerBoundSquared = min(
            lowerBoundSquared,
            shapeBoundsDistanceSquared(uShapeBounds[(first + i) & 15], p)
        );
    }
    return lowerBoundSquared;
}

// The same over the shapes a strip lists (listedSceneSample).
float listedBoundsOutsideSquared(vec2 p, vec4 members) {
    float lowerBoundSquared = 1e18;
    for (int slot = 0; slot < 4; slot++) {
        float member = members[slot];
        if (member >= 32.0) break;
        int i = int(member) & 15;
        lowerBoundSquared = min(
            lowerBoundSquared,
            shapeBoundsDistanceSquared(uShapeBounds[i], p)
        );
    }
    return lowerBoundSquared;
}

// A single shape is never blended, so it skips the exact-corner gradient.
SceneSample getShapeSampleFromArray(int index, vec2 p, bool blended) {
    int baseIndex = index * 3;
    vec4 primitive = uShapeData[baseIndex];
    vec4 inverseBasis = uShapeData[baseIndex + 1];
    vec4 placement = uShapeData[baseIndex + 2];
    SceneSample resultSample;
    resultSample.distance = getShapeDistance(
        index,
        p,
        primitive,
        inverseBasis,
        placement
    );
#ifdef SHAPE_ALONE
    // The placement scale is the same scale applied to the signed distance,
    // so this is the shape's local half-minor extent in scene pixels. Keeping
    // it beside the SDF avoids a second traversal and lets optical spread be
    // shape-relative rather than thickness-relative.
    resultSample.halfMinor = 0.5 * min(primitive.y, primitive.z) * placement.z;
#else
    // The same of the smallest shape this one blends with: iOS 27 sizes the
    // lens of every glass in a container by its smallest.
    resultSample.halfMinor = uShapeLens[index].x;
#endif
    vec2 delta = p - placement.xy;
    vec2 localPoint = vec2(
        inverseBasis.x * delta.x + inverseBasis.y * delta.y,
        inverseBasis.z * delta.x + inverseBasis.w * delta.y
    );
#ifndef SHAPE_ALONE
    vec2 lean = leanToCenter(
        localPoint,
        primitive.yz,
        inverseBasis,
        placement.z,
        uShapeLens[index].y
    );
#endif
    bool pair = primitive.x == 4.0;
    if (pair) {
        resolvePairHalf(index, localPoint, primitive);
    }
    vec4 gradients = getShapeGradients(
        primitive,
        inverseBasis,
        placement.z,
        localPoint,
        blended
    );
    if (pair) {
        // Where the other half's edge sets the depth, it sets the normal too.
        vec3 edge = pairOtherEdge(index, localPoint);
        if (edge.x * placement.z <= -resultSample.distance + 1e-4) {
            vec2 normal = mat2(
                inverseBasis.x, inverseBasis.y,
                inverseBasis.z, inverseBasis.w
            ) * edge.yz * placement.z;
            gradients = vec4(normal, normal);
        }
    }
    resultSample.normal = gradients.xy;
#ifdef SHAPE_ALONE
    resultSample.opticalNormal = gradients.zw;
#else
    // As long as it was: a smooth union reads how long the gradients are.
    resultSample.opticalNormal = uShapeLens[index].y > 0.0
        ? normalize(gradients.zw + lean) * length(gradients.zw)
        : gradients.zw;
#endif
#if SCENE_LOOKS
    resultSample.look = lookAt(index);
#endif
    return resultSample;
}

SceneSample smoothUnionSample(SceneSample a, SceneSample b, float k) {
    if (k <= 0.0) {
        return a.distance <= b.distance ? a : b;
    }
    float blend = angularBlendRadius(k, a.normal, b.normal);
    float e = max(blend - abs(a.distance - b.distance), 0.0);
    float distance = min(a.distance, b.distance) -
        e * e * 0.25 / max(blend, 1e-4);
    // Weighted over the union's full radius, so the shape-relative profile
    // and the look stay continuous across a smooth group seam.
    float weightA = smoothMinWeight(a.distance, b.distance, k);
    SceneSample result;
    result.distance = distance;
    result.halfMinor = mix(b.halfMinor, a.halfMinor, weightA);
    // The distance's gradient splits by the smooth minimum's own weight. Not
    // renormalized, so it shortens at a bridge's saddle like the distance
    // field's gradient does.
    float gradientWeightA = smoothMinWeight(a.distance, b.distance, blend);
    result.normal = mix(b.normal, a.normal, gradientWeightA);
    result.opticalNormal = mix(
        b.opticalNormal,
        a.opticalNormal,
        gradientWeightA
    );
#if SCENE_LOOKS
    result.look = mixLooks(a.look, b.look, weightA);
#endif
    return result;
}

// The scene of the count shapes from row first, in chain order.
SceneSample sceneSample(vec2 p, int first, int count) {
    SceneSample empty;
    empty.distance = 1e9;
    empty.halfMinor = 0.0;
    empty.normal = vec2(0.0);
    empty.opticalNormal = vec2(0.0);
#if SCENE_LOOKS
    empty.look = Look(vec4(0.0), vec4(0.0), vec4(0.0));
#endif
    if (count <= 0) {
        return empty;
    }
    if (count == 1) {
        return getShapeSampleFromArray(first & 15, p, false);
    }

    SceneSample result = empty;
    SceneSample groupResult = empty;
    int shapeCount = count < MAX_SHAPES ? count : MAX_SHAPES;
    for (int n = 0; n < MAX_SHAPES; n++) {
        if (n >= shapeCount) break;
        int i = (first + n) & 15;
        float marker = uShapeData[i * 3 + 2].w;
        bool startsGroup = marker < 0.0;
        float groupBlend = startsGroup ? -marker - 1.0 : marker;
        // Once a group has an exact candidate, an enclosing-box lower bound
        // beyond its smooth-union support proves this primitive cannot affect
        // the result. This avoids the much more expensive RSE/ellipse solve
        // for distant shapes while retaining original evaluation order.
        if (
            !startsGroup &&
            cannotAffectGroup(
                uShapeBounds[i],
                p,
                groupResult.distance + groupBlend
            )
        ) {
            continue;
        }
        SceneSample shapeValue = getShapeSampleFromArray(i, p, true);
        if (startsGroup) {
            result = result.distance < groupResult.distance ? result : groupResult;
            groupResult = shapeValue;
        } else {
            groupResult = smoothUnionSample(
                groupResult,
                shapeValue,
                groupBlend
            );
        }
    }
    return result.distance <= groupResult.distance ? result : groupResult;
}

// The scene of the up to four shapes a strip lists, in chain order: each
// member a shape's row, plus 16 where the shape is the first of its group
// among them, and 32 past the last. The tiler lists every shape that
// changes the scene anywhere on the strip (geometry_tiling.dart), so this
// is sceneSample without the shapes that leave it as it is.
SceneSample listedSceneSample(vec2 p, vec4 members) {
    if (members.y >= 32.0) {
        return getShapeSampleFromArray(int(members.x) & 15, p, false);
    }
    SceneSample empty;
    empty.distance = 1e9;
    empty.halfMinor = 0.0;
    empty.normal = vec2(0.0);
    empty.opticalNormal = vec2(0.0);
#if SCENE_LOOKS
    empty.look = Look(vec4(0.0), vec4(0.0), vec4(0.0));
#endif
    SceneSample result = empty;
    SceneSample groupResult = empty;
    for (int slot = 0; slot < 4; slot++) {
        float member = members[slot];
        if (member >= 32.0) break;
        bool startsGroup = member >= 16.0;
        int i = int(member) & 15;
        float marker = uShapeData[i * 3 + 2].w;
        float groupBlend = marker < 0.0 ? -marker - 1.0 : marker;
        if (
            !startsGroup &&
            cannotAffectGroup(
                uShapeBounds[i],
                p,
                groupResult.distance + groupBlend
            )
        ) {
            continue;
        }
        SceneSample shapeValue = getShapeSampleFromArray(i, p, true);
        if (startsGroup) {
            result = result.distance < groupResult.distance ? result : groupResult;
            groupResult = shapeValue;
        } else {
            groupResult = smoothUnionSample(
                groupResult,
                shapeValue,
                groupBlend
            );
        }
    }
    return result.distance <= groupResult.distance ? result : groupResult;
}

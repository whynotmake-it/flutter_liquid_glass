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
// lossless symmetric subset of Flutter's Impeller UberSDF payload; the public
// shape API has one uniform corner radius, so its signed scale is always 1.
//
// IMPORTANT: Every shader that includes this file must declare a
// `uniform vec4 uShapeData[MAX_SHAPES * 3];`,
// `uniform vec4 uRseData[MAX_SHAPES * 3];` and
// `uniform vec4 uShapeBounds[MAX_SHAPES];` *before* the include. The SDF
// helpers below read these uniforms directly rather than taking them as
// parameters, so no shape array is ever passed, and copied, by value.
#ifndef MAX_SHAPES
#define MAX_SHAPES 16
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
    return rseSuperellipse(octant / max(axis, 1e-4), degree) * axis;
}

float sdfEllipse(vec2 p, vec2 r) {
    // Impeller's oval SDF: a fixed five-step Newton solve. Closed-form
    // approximations divide by |p| near the center, which leaves a pinhole in
    // non-circular ovals.
    r = max(r, 1e-4);
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

// Reads the globally declared `uShapeData` uniform directly (see note above).
struct SceneSample {
    float distance;
    float halfMinor;
    float curvatureFactor;
    // Gradients of the distance (see getShapeGradients), blended like the
    // distance itself for a group. `normal` has the true corners and sets the
    // blend angle; `opticalNormal` has smoothed corners and drives
    // refraction, lighting and antialiasing.
    vec2 normal;
    vec2 opticalNormal;
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

// Smooth-union radius for two surfaces with normals na and nb. It scales with
// the chord between the normals: zero where the surfaces are aligned, such as
// the collinear sides of shapes in a row, and the full blend where they face
// each other across a gap. A plain smooth minimum lifts aligned edges near a
// join by up to k/4; this keeps them straight while concave joins and
// bridges still round. The iOS 27 GlassEffectContainer captures in
// example/tool/apple_match follow this within half a point, including the
// sub-point rise it leaves where two rounded corners meet.
float angularBlendRadius(float k, vec2 na, vec2 nb) {
    // Clamped because stretched shapes have gradients longer than 1; the
    // empty-pixel budget in sceneBoundsOutsideSquared assumes k at most.
    return k * min(0.5 * length(na - nb), 1.0);
}

// Weight of the first operand in a polynomial smooth minimum of radius k. It
// is also that operand's share of the result's gradient.
float smoothMinWeight(float a, float b, float k) {
    return clamp(0.5 + (b - a) / (2.0 * max(k, 1e-4)), 0.0, 1.0);
}

float getShapeCurvatureFactor(
    float type,
    vec2 localPoint,
    vec2 size,
    float rawRadius
) {
    if (type == 2.0) { // ellipse
        return 1.0;
    }
    vec2 halfSize = size * 0.5;
    float radius = min(rawRadius, min(halfSize.x, halfSize.y));
    if (radius <= 1e-4) {
        return 0.0;
    }
    // Rounded rectangles, capsules, and Flutter's continuous rounded
    // superellipse all share the same straight-to-corner support. A signed
    // one-pixel transition avoids a hard lighting cutoff at the join while
    // leaving the exact distance implementation unchanged.
    vec2 cornerPosition = abs(localPoint) - (halfSize - radius);
    return smoothstep(-1.0, 1.0, min(cornerPosition.x, cornerPosition.y));
}

float getShapeDistance(
    int index,
    vec2 p,
    vec4 primitive,
    vec4 inverseBasis,
    vec4 placement
) {
    vec4 rseDegreeAndSpans = uRseData[index * 3];
    vec4 rseCircleCenters = uRseData[index * 3 + 1];
    vec4 rseSemiAxisAndRadii = uRseData[index * 3 + 2];
    vec2 delta = p - placement.xy;
    vec2 localPoint = vec2(
        inverseBasis.x * delta.x + inverseBasis.y * delta.y,
        inverseBasis.z * delta.x + inverseBasis.w * delta.y
    );
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
    return localDistance * placement.z;
}

float getShapeDistanceFromArray(int index, vec2 p) {
    int baseIndex = index * 3;
    return getShapeDistance(
        index,
        p,
        uShapeData[baseIndex],
        uShapeData[baseIndex + 1],
        uShapeData[baseIndex + 2]
    );
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

// Squared outside distance for the complete scene plus its maximum possible
// smooth-union expansion. Comparing squared values avoids one square root per
// shape in the empty-pixel fast path.
vec2 sceneBoundsOutsideSquared(vec2 p, int numShapes) {
    float lowerBoundSquared = 1e18;
    float smoothingBudget = 0.0;
    int shapeCount = numShapes < MAX_SHAPES ? numShapes : MAX_SHAPES;
    for (int i = 0; i < MAX_SHAPES; i++) {
        if (i >= shapeCount) break;
        vec4 bounds = uShapeBounds[i];
        lowerBoundSquared = min(
            lowerBoundSquared,
            shapeBoundsDistanceSquared(bounds, p)
        );
        float marker = uShapeData[i * 3 + 2].w;
        if (marker >= 0.0) {
            smoothingBudget += marker * 0.25;
        }
    }
    return vec2(lowerBoundSquared, smoothingBudget);
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
    // The placement scale is the same scale applied to the signed distance,
    // so this is the shape's local half-minor extent in scene pixels. Keeping
    // it beside the SDF avoids a second traversal and lets optical spread be
    // shape-relative rather than thickness-relative.
    resultSample.halfMinor = 0.5 * min(primitive.y, primitive.z) * placement.z;
    // Lighting depth is shape-class aware but constant within a primitive.
    // Per-fragment rounded-rect curvature regions expose their medial/sector
    // boundaries as rectangular or V-shaped shading seams. Ellipses need the
    // deeper size response observed in the circle holdout; rounded and
    // continuous-superellipse primitives use the shallower response. Smooth
    // unions interpolate this value below.
    resultSample.curvatureFactor = primitive.x == 2.0 ? 1.0 : 0.0;
    vec2 delta = p - placement.xy;
    vec4 gradients = getShapeGradients(
        primitive,
        inverseBasis,
        placement.z,
        vec2(
            inverseBasis.x * delta.x + inverseBasis.y * delta.y,
            inverseBasis.z * delta.x + inverseBasis.w * delta.y
        ),
        blended
    );
    resultSample.normal = gradients.xy;
    resultSample.opticalNormal = gradients.zw;
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
    // Follow the same bounded smooth-min blend used for the distance field so
    // the shape-relative profile remains continuous at a smooth group seam.
    float weightA = smoothMinWeight(a.distance, b.distance, k);
    SceneSample result;
    result.distance = distance;
    result.halfMinor = mix(b.halfMinor, a.halfMinor, weightA);
    result.curvatureFactor = mix(
        b.curvatureFactor,
        a.curvatureFactor,
        weightA
    );
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
    return result;
}

SceneSample sceneSample(vec2 p, int numShapes) {
    SceneSample empty;
    empty.distance = 1e9;
    empty.halfMinor = 0.0;
    empty.curvatureFactor = 0.0;
    empty.normal = vec2(0.0);
    empty.opticalNormal = vec2(0.0);
    if (numShapes <= 0) {
        return empty;
    }
    if (numShapes == 1) {
        return getShapeSampleFromArray(0, p, false);
    }
    
    SceneSample result = empty;
    SceneSample groupResult = empty;
    int shapeCount = numShapes < MAX_SHAPES ? numShapes : MAX_SHAPES;
    for (int i = 0; i < MAX_SHAPES; i++) {
        if (i >= shapeCount) break;
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

// Copyright 2025, Tim Lehmann for whynotmake.it

// Three vec4s per shape: primitive parameters, inverse affine basis, and
// transformed center/distance/group data. RSE parameters use three vec4s per
// shape: degrees/(1 - cos span), circle centers, and semi-axes/radii. This is the
// lossless symmetric subset of Flutter's Impeller UberSDF payload: corners
// are circular, so its signed scale is always 1.

// The helpers read the shapes from the uniforms rather than taking them as
// parameters, so no shape array is ever passed, and copied, by value. A
// shader that declares uShapeData, uRseData and uShapeBounds itself
// (shape_geometry.glsl) defines GEOMETRY_UNIFORMS_GLSL first.
#ifndef GEOMETRY_UNIFORMS_GLSL
#include "geometry_uniforms.glsl"
#endif

#include "shader_constants.glsl"

#include "shape_sdf.glsl"

// Whether a scene sample carries its shapes' look (looks.glsl), blended by
// the smooth union's weight over its full radius, as halfMinor is.
#ifndef SCENE_LOOKS
#define SCENE_LOOKS 0
#endif
#if SCENE_LOOKS
#include "looks.glsl"
#endif

float getShapeSDF(
    float type,
    vec2 p,
    vec2 size,
    float r,
    vec4 rseDegreeAndSpans,
    vec4 rseCircleCenters,
    vec4 rseSemiAxisAndRadii
) {
    if (type == SHAPE_SQUIRCLE) {
        return sdfSquircle(
            p,
            size / 2.0,
            r,
            rseDegreeAndSpans,
            rseCircleCenters,
            rseSemiAxisAndRadii
        );
    }
    if (type == SHAPE_ELLIPSE) {
        return sdfEllipse(p, size / 2.0);
    }
    if (type == SHAPE_ROUNDED_RECTANGLE) {
        return sdfRRect(p, size / 2.0, r);
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
    if (primitive.x == SHAPE_ELLIPSE) {
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

int pairBottomRow(int index) {
    return (MAX_SHAPES + index) * SQUIRCLE_ROW_VEC4S;
}

PairSplit pairSplit(int index) {
    return PairSplit(
        uRseData[index * SQUIRCLE_ROW_VEC4S + SQUIRCLE_AXES_AND_RADII].y,
        uRseData[pairBottomRow(index) + SQUIRCLE_AXES_AND_RADII].y
    );
}

// The bottom radius sits where the bottom half's half width would, which is
// the top's (SquirclePairParameters.geometryBottomFloats).
float pairBottomRadius(int index) {
    return uRseData[pairBottomRow(index) + SQUIRCLE_AXES_AND_RADII].x;
}

// The half of pair [index] the local point p lies in: moves p to that half's
// center on the split line and makes primitive that half's own squircle, its
// box twice the half's height. Both halves are vertical at the sides on the
// line, so the outline is continuous and exact there. Returns the half's first
// uRseData row.
int resolvePairHalf(int index, inout vec2 p, inout vec4 primitive) {
    PairSplit split = pairSplit(index);
    p = fromSplitLine(p, split);
    if (p.y > 0.0) {
        primitive = vec4(
            SHAPE_SQUIRCLE,
            primitive.y,
            2.0 * split.below,
            pairBottomRadius(index)
        );
        return pairBottomRow(index);
    }
    primitive = vec4(SHAPE_SQUIRCLE, primitive.y, 2.0 * split.above, primitive.w);
    return index * SQUIRCLE_ROW_VEC4S;
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
    int rse = index * SQUIRCLE_ROW_VEC4S;
    bool pair = primitive.x == SHAPE_SQUIRCLE_PAIR;
    if (pair) {
        rse = resolvePairHalf(index, localPoint, primitive);
    }
    vec4 rseDegreeAndSpans = uRseData[rse + SQUIRCLE_DEGREES_AND_SPANS];
    vec4 rseCircleCenters = uRseData[rse + SQUIRCLE_CIRCLE_CENTERS];
    vec4 rseSemiAxisAndRadii = uRseData[rse + SQUIRCLE_AXES_AND_RADII];
    // Back from pairBottomRadius to the half width.
    if (pair) {
        rseSemiAxisAndRadii.x = 0.5 * primitive.y;
    }
    float localDistance = getShapeSDF(
        primitive.x,
        localPoint,
        primitive.yz,
        primitive.w,
        rseDegreeAndSpans,
        rseCircleCenters,
        rseSemiAxisAndRadii
    );
    if (pair) {
        localDistance = max(
            localDistance,
            -pairOtherEdge(localPoint, pairSplit(index)).distance
        );
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
            shapeBoundsDistanceSquared(uShapeBounds[(first + i) & SHAPE_INDEX_MASK], p)
        );
    }
    return lowerBoundSquared;
}

// The same over the shapes a strip lists (listedSceneSample).
float listedBoundsOutsideSquared(vec2 p, vec4 members) {
    float lowerBoundSquared = 1e18;
    for (int slot = 0; slot < 4; slot++) {
        float member = members[slot];
        if (member >= MEMBER_NONE) break;
        int i = int(member) & SHAPE_INDEX_MASK;
        lowerBoundSquared = min(
            lowerBoundSquared,
            shapeBoundsDistanceSquared(uShapeBounds[i], p)
        );
    }
    return lowerBoundSquared;
}

// A single shape is never blended, so it skips the exact-corner gradient.
SceneSample getShapeSampleFromArray(int index, vec2 p, bool blended) {
    int baseIndex = index * SHAPE_ROW_VEC4S;
    vec4 primitive = uShapeData[baseIndex + SHAPE_PRIMITIVE];
    vec4 inverseBasis = uShapeData[baseIndex + SHAPE_INVERSE_BASIS];
    vec4 placement = uShapeData[baseIndex + SHAPE_PLACEMENT];
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
    bool pair = primitive.x == SHAPE_SQUIRCLE_PAIR;
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
        PairEdge edge = pairOtherEdge(localPoint, pairSplit(index));
        if (edge.distance * placement.z <= -resultSample.distance + 1e-4) {
            vec2 normal = mat2(
                inverseBasis.x, inverseBasis.y,
                inverseBasis.z, inverseBasis.w
            ) * edge.normal * placement.z;
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
        return getShapeSampleFromArray(first & SHAPE_INDEX_MASK, p, false);
    }

    SceneSample result = empty;
    SceneSample groupResult = empty;
    int shapeCount = count < MAX_SHAPES ? count : MAX_SHAPES;
    for (int n = 0; n < MAX_SHAPES; n++) {
        if (n >= shapeCount) break;
        int i = (first + n) & SHAPE_INDEX_MASK;
        float marker = uShapeData[i * SHAPE_ROW_VEC4S + SHAPE_PLACEMENT].w;
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
// member a shape's row. The tiler lists every shape that
// changes the scene anywhere on the strip (geometry_tiling.dart), so this
// is sceneSample without the shapes that leave it as it is.
SceneSample listedSceneSample(vec2 p, vec4 members) {
    if (members.y >= MEMBER_NONE) {
        return getShapeSampleFromArray(
            int(members.x) & SHAPE_INDEX_MASK,
            p,
            false
        );
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
        if (member >= MEMBER_NONE) break;
        bool startsGroup = member >= MEMBER_STARTS_GROUP;
        int i = int(member) & SHAPE_INDEX_MASK;
        float marker = uShapeData[i * SHAPE_ROW_VEC4S + SHAPE_PLACEMENT].w;
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

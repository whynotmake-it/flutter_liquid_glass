// Analytic geometry for the final pass: up to ANALYTIC_MAX_SHAPES shapes
// evaluated where the fragment is, with the geometry pass's own scene
// (gpu/sdf.glsl), instead of read from a Flutter GPU matte. It yields the
// matte's texel at the fragment itself - the distance, the normal times its
// strength and half the shorter side - so the rest of the final pass reads
// it as it reads the matte.
//
// The geometry pass shades a texel per block of matte pixels; this runs for
// every pixel, so it skips the work whose result the final pass would not
// read: the shapes deeper inside than the pass reads, and the separate
// shapes that cannot be the nearest.
//
// Included by liquid_glass_final_render_core.glsl after its float uniforms,
// so these start at _FinalUniforms.analytic (liquid_glass_layer.dart).
// impellerc gives every uniform declaration its own Metal buffer slot and
// Metal has 31; these four fit because the core packs its optional effects
// into uEffects.

#define ANALYTIC_MAX_SHAPES 8
#define MAX_SHAPES ANALYTIC_MAX_SHAPES

// x: the number of shapes, y: how far past the shapes' outlines a fragment
// can still matter (the contour extent), device px, z: 1 when a group blends
// two or more shapes.
uniform vec4 uAnalyticHeader;
uniform vec4 uShapeData[MAX_SHAPES * 3];
// Each shape's three rounded superellipse rows, then from MAX_SHAPES * 3
// each pair's bottom-half rows, as gpu/sdf.glsl reads them.
uniform vec4 uRseData[MAX_SHAPES * 6];
// MAX_SHAPES shape bounds (what gpu/sdf.glsl reads), then each shape's cull
// factor, four to a row: its basis's smallest stretch over its largest. A
// shape's distance is at least its box's distance times that.
uniform vec4 uShapeBounds[MAX_SHAPES + MAX_SHAPES / 4];
#define shapeCull(i) uShapeBounds[MAX_SHAPES + (i) / 4][(i) - ((i) / 4) * 4]

#include "gpu/sdf.glsl"

// A lower bound of how deep p lies inside shape [index], device px, or 0.
// A rounded box is convex, and at twice its corner radius from each corner
// (or at the side's middle, if nearer) its outline lies on its box's side
// to within a thousandth of the radius; a rounded superellipse's sides are
// not quite straight. So the shape holds the octagon through those points
// shrunk by a hundredth of the radius
// (test/src/analytic_depth_bound_test.dart), and p's depth in that octagon
// bounds its depth. That needs the radius to be at most half the box's
// shorter side (a capsule at most) and, for a pair, four times its larger
// radius to fit in the shorter side; ellipses and the rest report 0.
float shapeDepthBound(int index, vec2 p) {
    vec4 primitive = uShapeData[index * 3];
    if (primitive.x == 0.0 || primitive.x == 2.0) {
        return 0.0;
    }
    vec4 inverseBasis = uShapeData[index * 3 + 1];
    vec4 placement = uShapeData[index * 3 + 2];
    vec2 halfSize = primitive.yz * 0.5;
    float radius = primitive.w;
    float shorter = min(halfSize.x, halfSize.y);
    if (primitive.x == 4.0) {
        radius = max(radius, uRseData[MAX_SHAPES * 3 + index * 3 + 2].x);
        if (2.0 * radius > shorter) {
            return 0.0;
        }
    } else if (radius > shorter) {
        return 0.0;
    }
    vec2 delta = p - placement.xy;
    vec2 local = abs(vec2(
        inverseBasis.x * delta.x + inverseBasis.y * delta.y,
        inverseBasis.z * delta.x + inverseBasis.w * delta.y
    ));
    vec2 inside = halfSize - local;
    vec2 cut = min(vec2(2.0 * radius), halfSize);
    float depth = min(inside.x, inside.y);
    if (radius > 0.0) {
        // The cut edge from (halfSize.x - cut.x, halfSize.y) to
        // (halfSize.x, halfSize.y - cut.y), measured inward.
        depth = min(
            depth,
            (inside.x * cut.y + inside.y * cut.x - cut.x * cut.y) /
                length(cut)
        );
    }
    return max(depth - 0.01 * radius, 0.0) * placement.z;
}

// The nearest of shapes that never blend, in sceneSample's order and tie
// rule (each its own group: a later equal shape wins, except the last,
// which must be strictly nearer). A shape whose box is farther than the
// nearest so far, by its cull factor, cannot win and is not solved.
SceneSample nearestShape(vec2 p, int count) {
    SceneSample best;
    best.distance = 1e9;
    best.halfMinor = 0.0;
    best.curvatureFactor = 0.0;
    best.normal = vec2(0.0);
    best.opticalNormal = vec2(0.0);
    for (int i = 0; i < MAX_SHAPES; i++) {
        if (i >= count) break;
        float bound = sqrt(shapeBoundsDistanceSquared(uShapeBounds[i], p)) *
            shapeCull(i);
        if (bound > max(best.distance, 0.0)) continue;
        SceneSample shape = getShapeSampleFromArray(i, p, count > 1);
        bool nearer = i == count - 1
            ? shape.distance < best.distance
            : shape.distance <= best.distance;
        if (nearer) {
            best = shape;
        }
    }
    return best;
}

// The geometry pass's texel at p (geometry_fragment.glsl). Where no shape can
// reach, a far-outside texel; deeper inside than [readDepth], where the final
// pass only checks that the distance is past it, some depth past it with no
// normal.
vec4 analyticTexel(vec2 p, float readDepth) {
    int count = int(uAnalyticHeader.x);
    // Most pixels of a sparse layer are far outside: that test comes first.
    vec2 outside = sceneBoundsOutsideSquared(p, count);
    float reach = uAnalyticHeader.y + 2.0 + outside.y;
    if (outside.x > reach * reach) {
        return vec4(-4096.0, 0.0, 0.0, 0.0);
    }
    // A union, smooth or not, is at least as deep as each of its shapes.
    for (int i = 0; i < MAX_SHAPES; i++) {
        if (i >= count) break;
        if (shapeBoundsDistanceSquared(uShapeBounds[i], p) > 0.0) continue;
        float depth = shapeDepthBound(i, p);
        if (depth > readDepth) {
            return vec4(depth, 0.0, 0.0, 0.0);
        }
    }
    SceneSample scene = uAnalyticHeader.z > 0.5
        ? sceneSample(p, count)
        : nearestShape(p, count);
    float gradientLength = length(scene.opticalNormal);
    vec2 normal = gradientLength > 0.0001
        ? scene.opticalNormal / gradientLength
        : vec2(0.0);
    return vec4(
        clamp(-scene.distance, -16000.0, 16000.0),
        normal * sqrt(clamp(gradientLength, 0.0, 1.0)),
        scene.halfMinor
    );
}

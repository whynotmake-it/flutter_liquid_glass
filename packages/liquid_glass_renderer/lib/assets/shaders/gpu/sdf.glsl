// Three vec4s per shape: primitive parameters, inverse affine basis, and
// transformed center/distance/group data. RSE parameters use three vec4s per
// shape: degrees/spans, circle centers, and semi-axes/radii. This is the
// lossless symmetric subset of Flutter's Impeller UberSDF payload; the public
// shape API has one uniform corner radius, so its signed scale is always 1.
//
// IMPORTANT: Every shader that includes this file must declare a
// `uniform vec4 uShapeData[MAX_SHAPES * 3];` and
// `uniform vec4 uRseData[MAX_SHAPES * 3];` *before* the include. The SDF
// helpers below read that global uniform directly instead of taking it as a
// function parameter on purpose: passing an array by value makes spirv-cross
// emit an array copy-initializer (`float param[96] = uShapeData;`) which is
// rejected by SkSL, so the shaders would fail to compile on the Skia backend.
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
    float span;
    float axis;
    float circleRadius;
    vec2 circleCenter;
    if (normalized.y + c > normalized.x) {
        octant = normalized + vec2(0.0, c);
        degree = degreeAndSpans.x;
        axis = semiAxisAndRadii.x;
        span = degreeAndSpans.z;
        circleCenter = circleCenters.xy;
        circleRadius = semiAxisAndRadii.z;
    } else {
        octant = normalized.yx - vec2(0.0, c);
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
    return rseSuperellipse(octant / max(axis, 1e-4), degree) * axis;
}

float sdfEllipse(vec2 p, vec2 r) {
    // Flutter's Impeller oval SDF uses a fixed five-step Newton solve. The
    // former closed-form approximation divided by |p| near the center,
    // producing a zero/direction-dependent pinhole for non-circular ovals.
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

float smoothUnion(float d1, float d2, float k) {
    if (k <= 0.0) {
        return min(d1, d2);
    }
    float e = max(k - abs(d1 - d2), 0.0);
    return min(d1, d2) - e * e * 0.25 / k;
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
};

float getShapeDistanceFromArray(int index, vec2 p) {
    int baseIndex = index * 3;
    vec4 primitive = uShapeData[baseIndex];
    vec4 inverseBasis = uShapeData[baseIndex + 1];
    vec4 placement = uShapeData[baseIndex + 2];
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

SceneSample getShapeSampleFromArray(int index, vec2 p) {
    int baseIndex = index * 3;
    vec4 primitive = uShapeData[baseIndex];
    vec4 placement = uShapeData[baseIndex + 2];
    SceneSample resultSample;
    resultSample.distance = getShapeDistanceFromArray(index, p);
    // The placement scale is the same scale applied to the signed distance,
    // so this is the shape's local half-minor extent in scene pixels. Keeping
    // it beside the SDF avoids a second traversal and lets optical spread be
    // shape-relative rather than thickness-relative.
    resultSample.halfMinor = 0.5 * min(primitive.y, primitive.z) * placement.z;
    return resultSample;
}

SceneSample smoothUnionSample(SceneSample a, SceneSample b, float k) {
    if (k <= 0.0) {
        return a.distance <= b.distance ? a : b;
    }
    float e = max(k - abs(a.distance - b.distance), 0.0);
    float distance = min(a.distance, b.distance) - e * e * 0.25 / k;
    // Follow the same bounded smooth-min blend used for the distance field so
    // the shape-relative profile remains continuous at a smooth group seam.
    float weightA = clamp(0.5 + (b.distance - a.distance) / (2.0 * k), 0.0, 1.0);
    SceneSample result;
    result.distance = distance;
    result.halfMinor = mix(b.halfMinor, a.halfMinor, weightA);
    return result;
}

SceneSample sceneSample(vec2 p, int numShapes) {
    SceneSample empty;
    empty.distance = 1e9;
    empty.halfMinor = 0.0;
    if (numShapes <= 0) {
        return empty;
    }
    if (numShapes == 1) {
        return getShapeSampleFromArray(0, p);
    }
    
    SceneSample result = empty;
    SceneSample groupResult = empty;
    int shapeCount = numShapes < MAX_SHAPES ? numShapes : MAX_SHAPES;
    for (int i = 0; i < MAX_SHAPES; i++) {
        if (i >= shapeCount) break;
        float marker = uShapeData[i * 3 + 2].w;
        bool startsGroup = marker < 0.0;
        float groupBlend = startsGroup ? -marker - 1.0 : marker;
        SceneSample shapeValue = getShapeSampleFromArray(i, p);
        if (startsGroup) {
            result = result.distance < groupResult.distance ? result : groupResult;
            groupResult = shapeValue;
        } else {
            groupResult = smoothUnionSample(groupResult, shapeValue, groupBlend);
        }
    }
    return result.distance <= groupResult.distance ? result : groupResult;
}

float sceneSDF(vec2 p, int numShapes) {
    if (numShapes <= 0) {
        return 1e9;
    }
    int shapeCount = numShapes < MAX_SHAPES ? numShapes : MAX_SHAPES;
    if (shapeCount == 1) {
        return getShapeDistanceFromArray(0, p);
    }

    float result = 1e9;
    float groupResult = 1e9;
    for (int i = 0; i < MAX_SHAPES; i++) {
        if (i >= shapeCount) break;
        float marker = uShapeData[i * 3 + 2].w;
        bool startsGroup = marker < 0.0;
        float groupBlend = startsGroup ? -marker - 1.0 : marker;
        float shapeDistance = getShapeDistanceFromArray(i, p);
        if (startsGroup) {
            result = min(result, groupResult);
            groupResult = shapeDistance;
        } else {
            float e = max(groupBlend - abs(groupResult - shapeDistance), 0.0);
            groupResult = min(groupResult, shapeDistance) -
                e * e * 0.25 / max(groupBlend, 0.0001);
        }
    }
    return min(result, groupResult);
}

// Cheap two-shape appearance interpolation. Geometry remains the exact smooth
// union, while material ownership is approximated from only the two nearest
// primitive distances. This keeps colors solid away from a narrow blend seam.
struct MaterialSceneSample {
    float distance;
    float halfMinor;
    float curvatureFactor;
    float primary;
    float secondary;
    float primaryDistance;
    float secondaryDistance;
    float blendWidth;
};

MaterialSceneSample materialShapeSample(int index, vec2 p) {
    SceneSample shape = getShapeSampleFromArray(index, p);
    MaterialSceneSample result;
    result.distance = shape.distance;
    result.halfMinor = shape.halfMinor;
    result.curvatureFactor = shape.curvatureFactor;
    result.primary = float(index);
    result.secondary = float(index);
    result.primaryDistance = shape.distance;
    result.secondaryDistance = 1e9;
    result.blendWidth = 0.0;
    return result;
}

MaterialSceneSample materialSmoothUnion(
    MaterialSceneSample composite,
    MaterialSceneSample next,
    float k
) {
    if (k <= 0.0) {
        return composite.distance <= next.distance ? composite : next;
    }
    float e = max(k - abs(composite.distance - next.distance), 0.0);
    float geometryWeight = clamp(
        0.5 + (next.distance - composite.distance) / (2.0 * k),
        0.0,
        1.0
    );

    MaterialSceneSample result;
    result.distance = min(composite.distance, next.distance) -
        e * e * 0.25 / k;
    result.halfMinor = mix(
        next.halfMinor,
        composite.halfMinor,
        geometryWeight
    );
    result.curvatureFactor = mix(
        next.curvatureFactor,
        composite.curvatureFactor,
        geometryWeight
    );

    result.primary = composite.primary;
    result.primaryDistance = composite.primaryDistance;
    result.secondary = composite.secondary;
    result.secondaryDistance = composite.secondaryDistance;
    if (next.primaryDistance < result.primaryDistance) {
        result.secondary = result.primary;
        result.secondaryDistance = result.primaryDistance;
        result.primary = next.primary;
        result.primaryDistance = next.primaryDistance;
    } else if (next.primaryDistance < result.secondaryDistance) {
        result.secondary = next.primary;
        result.secondaryDistance = next.primaryDistance;
    }
    result.blendWidth = max(max(composite.blendWidth, next.blendWidth), k);
    return result;
}

MaterialSceneSample materialSceneSample(vec2 p, int numShapes) {
    MaterialSceneSample empty;
    empty.distance = 1e9;
    empty.halfMinor = 0.0;
    empty.curvatureFactor = 0.0;
    empty.primary = 0.0;
    empty.secondary = 0.0;
    empty.primaryDistance = 1e9;
    empty.secondaryDistance = 1e9;
    empty.blendWidth = 0.0;
    if (numShapes <= 0) return empty;

    MaterialSceneSample result = empty;
    MaterialSceneSample groupResult = empty;
    int shapeCount = numShapes < MAX_SHAPES ? numShapes : MAX_SHAPES;
    for (int i = 0; i < MAX_SHAPES; i++) {
        if (i >= shapeCount) break;
        float marker = uShapeData[i * 3 + 2].w;
        bool startsGroup = marker < 0.0;
        float groupBlend = startsGroup ? -marker - 1.0 : marker;
        if (
            !startsGroup &&
            getShapeBoundsDistanceFromArray(i, p) >=
                groupResult.distance + groupBlend
        ) {
            continue;
        }
        MaterialSceneSample shapeValue = materialShapeSample(i, p);
        if (startsGroup) {
            result = result.distance < groupResult.distance
                ? result
                : groupResult;
            groupResult = shapeValue;
        } else {
            groupResult = materialSmoothUnion(
                groupResult,
                shapeValue,
                groupBlend
            );
        }
    }
    return result.distance <= groupResult.distance ? result : groupResult;
}

float materialPrimaryWeight(MaterialSceneSample scene) {
    if (scene.primary == scene.secondary) return 1.0;
    float width = max(scene.blendWidth, 0.001);
    return clamp(
        0.5 + (scene.secondaryDistance - scene.primaryDistance) /
            (2.0 * width),
        0.0,
        1.0
    );
}

// Two-contributor material ownership for the optional appearance geometry
// target. GeometryFragment does not include this file, so the uniform-material
// pipeline retains its original shader workload.
struct MaterialSceneSample {
    float distance;
    float halfMinor;
    float curvatureFactor;
    float primary;
    float secondary;
    float primaryWeight;
};

MaterialSceneSample materialShapeSample(int index, vec2 p) {
    SceneSample shape = getShapeSampleFromArray(index, p);
    MaterialSceneSample result;
    result.distance = shape.distance;
    result.halfMinor = shape.halfMinor;
    result.curvatureFactor = shape.curvatureFactor;
    result.primary = float(index);
    result.secondary = float(index);
    result.primaryWeight = 1.0;
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
    float weightComposite = clamp(
        0.5 + (next.distance - composite.distance) / (2.0 * k),
        0.0,
        1.0
    );
    float firstWeight = composite.primaryWeight * weightComposite;
    float secondWeight = (1.0 - composite.primaryWeight) * weightComposite;
    float nextWeight = 1.0 - weightComposite;

    float primary = composite.primary;
    float primaryWeight = firstWeight;
    float secondary = composite.secondary;
    float secondaryWeight = secondWeight;
    if (secondaryWeight > primaryWeight) {
        primary = composite.secondary;
        primaryWeight = secondWeight;
        secondary = composite.primary;
        secondaryWeight = firstWeight;
    }
    if (nextWeight > primaryWeight) {
        secondary = primary;
        secondaryWeight = primaryWeight;
        primary = next.primary;
        primaryWeight = nextWeight;
    } else if (nextWeight > secondaryWeight) {
        secondary = next.primary;
        secondaryWeight = nextWeight;
    }

    MaterialSceneSample result;
    result.distance = min(composite.distance, next.distance) -
        e * e * 0.25 / k;
    result.halfMinor = mix(
        next.halfMinor,
        composite.halfMinor,
        weightComposite
    );
    result.curvatureFactor = mix(
        next.curvatureFactor,
        composite.curvatureFactor,
        weightComposite
    );
    result.primary = primary;
    result.secondary = secondary;
    result.primaryWeight = primaryWeight /
        max(primaryWeight + secondaryWeight, 1e-6);
    return result;
}

MaterialSceneSample materialSceneSample(vec2 p, int numShapes) {
    MaterialSceneSample empty;
    empty.distance = 1e9;
    empty.halfMinor = 0.0;
    empty.curvatureFactor = 0.0;
    empty.primary = 0.0;
    empty.secondary = 0.0;
    empty.primaryWeight = 1.0;
    if (numShapes <= 0) return empty;

    MaterialSceneSample result = empty;
    MaterialSceneSample groupResult = empty;
    int shapeCount = numShapes < MAX_SHAPES ? numShapes : MAX_SHAPES;
    for (int i = 0; i < MAX_SHAPES; i++) {
        if (i >= shapeCount) break;
        float marker = uShapeData[i * 3 + 2].w;
        bool startsGroup = marker < 0.0;
        float groupBlend = startsGroup ? -marker - 1.0 : marker;
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

vec4 encodeMaterialContributors(MaterialSceneSample scene) {
    return vec4(
        (scene.primary + 0.5) / float(MAX_SHAPES),
        (scene.secondary + 0.5) / float(MAX_SHAPES),
        clamp(scene.primaryWeight, 0.0, 1.0),
        1.0
    );
}

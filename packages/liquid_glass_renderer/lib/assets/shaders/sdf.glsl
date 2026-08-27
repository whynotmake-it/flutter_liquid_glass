// Shape array uniforms - 6 floats per shape (type, centerX, centerY, sizeW, sizeH, cornerRadius)
// Reduced from 64 to 16 shapes to fit Impeller's uniform buffer limit (16 * 6 = 96 floats vs 384)
#ifndef MAX_SHAPES
#define MAX_SHAPES 16
#endif

float sdfRRect( in vec2 p, in vec2 b, in float r ) {
    float shortest = min(b.x, b.y);
    r = min(r, shortest);
    vec2 q = abs(p)-b+r;
    return min(max(q.x,q.y),0.0) + length(max(q,0.0)) - r;
}

float sdfRect(vec2 p, vec2 b) {
    vec2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float sdfSquircle(vec2 p, vec2 b, float r) {
    float shortest = min(b.x, b.y);
    r = min(r, shortest);

    vec2 q = abs(p) - b + r;
    
    vec2 maxQ = max(q, 0.0);
    return min(max(q.x, q.y), 0.0) + sqrt(maxQ.x * maxQ.x + maxQ.y * maxQ.y) - r;
}

float sdfEllipse(vec2 p, vec2 r) {
    r = max(r, 1e-4);
    
    vec2 invR = 1.0 / r;
    vec2 invR2 = invR * invR;
    
    vec2 pInvR = p * invR;
    float k1 = length(pInvR);
    
    vec2 pInvR2 = p * invR2;
    float k2 = length(pInvR2);
    
    return (k1 * (k1 - 1.0)) / max(k2, 1e-4);
}

float smoothUnion(float d1, float d2, float k) {
    if (k <= 0.0) {
        return min(d1, d2);
    }
    float e = max(k - abs(d1 - d2), 0.0);
    return min(d1, d2) - e * e * 0.25 / k;
}

float getShapeSDF(float type, vec2 p, vec2 center, vec2 size, float r) {
    if (type == 1.0) { // squircle
        return sdfSquircle(p - center, size / 2.0, r);
    }
    if (type == 2.0) { // ellipse
        return sdfEllipse(p - center, size / 2.0);
    }
    if (type == 3.0) { // rounded rectangle
        return sdfRRect(p - center, size / 2.0, r);
    }
    return 1e9; // none
}

float getShapeSDFFromArray(int index, vec2 p) {
#define RETURN_SHAPE_SDF(I) \
    if (index == I) { \
        return getShapeSDF( \
            uShapeData[I * 6], \
            p, \
            vec2(uShapeData[I * 6 + 1], uShapeData[I * 6 + 2]), \
            vec2(uShapeData[I * 6 + 3], uShapeData[I * 6 + 4]), \
            uShapeData[I * 6 + 5] \
        ); \
    }

    // SkSL requires uniform-array indices to be compile-time constants. Keep
    // the public shape count while selecting each fixed slot explicitly.
    RETURN_SHAPE_SDF(0)
    RETURN_SHAPE_SDF(1)
    RETURN_SHAPE_SDF(2)
    RETURN_SHAPE_SDF(3)
    RETURN_SHAPE_SDF(4)
    RETURN_SHAPE_SDF(5)
    RETURN_SHAPE_SDF(6)
    RETURN_SHAPE_SDF(7)
    RETURN_SHAPE_SDF(8)
    RETURN_SHAPE_SDF(9)
    RETURN_SHAPE_SDF(10)
    RETURN_SHAPE_SDF(11)
    RETURN_SHAPE_SDF(12)
    RETURN_SHAPE_SDF(13)
    RETURN_SHAPE_SDF(14)
    RETURN_SHAPE_SDF(15)

#undef RETURN_SHAPE_SDF
    return 1e9;
}

float sceneSDF(vec2 p) {
    int numShapes = int(uNumShapes);
    if (numShapes == 0) {
        return 1e9;
    }
    
    float result = getShapeSDFFromArray(0, p);
    
    // Optimized: unroll for common cases (1-4 shapes), use loop for 5+ shapes
    if (numShapes <= 4) {
        // Fully unrolled for 1-4 shapes (covers 90%+ of use cases)
        if (numShapes >= 2) {
            float shapeSDF = getShapeSDFFromArray(1, p);
            result = smoothUnion(result, shapeSDF, uBlend);
        }
        if (numShapes >= 3) {
            float shapeSDF = getShapeSDFFromArray(2, p);
            result = smoothUnion(result, shapeSDF, uBlend);
        }
        if (numShapes >= 4) {
            float shapeSDF = getShapeSDFFromArray(3, p);
            result = smoothUnion(result, shapeSDF, uBlend);
        }
    } else {
        // Dynamic loop for 5+ shapes (uncommon cases)
        for (int i = 1; i < MAX_SHAPES; i++) {
            if (i >= numShapes) {
                break;
            }
            float shapeSDF = getShapeSDFFromArray(i, p);
            result = smoothUnion(result, shapeSDF, uBlend);
        }
    }
    
    return result;
}

// Calculate the SDF gradient explicitly. Flutter runtime-effect shaders do not
// expose screen-space derivative intrinsics on every renderer (notably web),
// so sample one logical pixel on each side instead.
vec3 getNormal(
    vec2 p,
    float sd,
    float thickness
) {
#ifdef SKIA_GRAPHICS_BACKEND
    const float epsilon = 1.0;
    float dx = 0.5 * (
        sceneSDF(p + vec2(epsilon, 0.0))
            - sceneSDF(p - vec2(epsilon, 0.0))
    );
    float dy = 0.5 * (
        sceneSDF(p + vec2(0.0, epsilon))
            - sceneSDF(p - vec2(0.0, epsilon))
    );
#else
    float dx = dFdx(sd);
    float dy = dFdy(sd);
#endif
    
    // The cosine and sine between normal and the xy plane
    float n_cos = max(thickness + sd, 0.0) / thickness;
    float n_sin = sqrt(max(0.0, 1.0 - n_cos * n_cos));
    
    return normalize(vec3(dx * n_cos, dy * n_cos, n_sin));
}

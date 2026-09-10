// Copyright 2025, Tim Lehmann for whynotmake.it
//
// Shared utilities for encoding and decoding displacement data

// Encode the reusable SDF surface plus optical displacement into RGBA.
// RG: Full-strength normalized SDF normal direction.
// B: Signed inward edge distance (positive inside, negative outside)
// A: One-sided optical displacement magnitude (the physical solution always
//    points opposite the outward SDF normal)
vec4 encodeDisplacementData(
    vec2 surfaceNormal,
    float displacementMagnitude,
    float maxDisplacement,
    float signedEdgeDistance,
    float thickness,
    float exteriorRange
) {
    // Use codes 0...254 as an asymmetric signed-normal mapping. Conventional
    // UNORM8 centers zero between codes 127 and 128, so an exactly horizontal
    // or vertical optical wall decodes with a false perpendicular component.
    // Reserving code 255 makes -1, 0, and +1 exactly representable and reduces
    // angular lookup error without another channel or a wider texture.
    const float kNormalCodeScale = 127.0 / 255.0;
    vec2 normalizedNormal = clamp(
        surfaceNormal * kNormalCodeScale + kNormalCodeScale,
        0.0,
        254.0 / 255.0
    );
    // Refraction of the normal-incidence ray through this convex profile can
    // only point opposite surfaceNormal. Encoding a signed value around 0.5
    // wasted half of RGBA8's A channel and made strong refraction jump by more
    // than a logical pixel between adjacent codes. Use the complete channel
    // for the physically reachable magnitude instead.
    float linearMagnitude = clamp(
        -displacementMagnitude / maxDisplacement,
        0.0,
        1.0
    );
    // Peak displacement lives in the narrow optical rim where a single source
    // pixel jump is most visible. Concentrate codes toward that endpoint while
    // leaving low-magnitude precision no worse than the former half-channel
    // signed mapping. The inverse below is multiply-only.
    float normalizedMagnitude = 1.0 - sqrt(1.0 - linearMagnitude);
    
    float inwardRange = thickness * 4.0;
    // The geometry target is RGBA8. A linear mapping across the complete
    // optical profile left fewer than two code points per physical pixel at
    // common thicknesses, which the narrow contour/highlight ramps exposed as
    // concentric bands. Give each side of the mathematical edge half of the
    // channel and apply a square-root compander. This concentrates precision
    // where coverage and lighting consume the SDF without changing texture
    // format, bandwidth, sampling, or pass count. The inverse is only a
    // multiply in the final pass.
    float normalizedEdgeDistance = 0.5;
    if (signedEdgeDistance >= 0.0) {
        float normalizedInward = clamp(
            signedEdgeDistance / max(inwardRange, 0.001),
            0.0,
            1.0
        );
        normalizedEdgeDistance += 0.5 * sqrt(normalizedInward);
    } else {
        float normalizedExterior = clamp(
            -signedEdgeDistance / max(exteriorRange, 0.001),
            0.0,
            1.0
        );
        normalizedEdgeDistance -= 0.5 * sqrt(normalizedExterior);
    }
    
    return vec4(
        normalizedNormal.x,
        normalizedNormal.y,
        normalizedEdgeDistance,
        normalizedMagnitude
    );
}

vec2 decodeSurfaceNormal(vec4 encoded) {
    vec2 normal = (encoded.rg * 255.0 - 127.0) / 127.0;
    float normalLength = length(normal);
    return normalLength > 0.0001 ? normal / normalLength : vec2(0.0);
}

// Reconstruct optical displacement from the shared normal and A magnitude.
vec2 decodeDisplacement(vec4 encoded, float maxDisplacement) {
    float inverseMagnitude = 1.0 - encoded.a;
    float normalizedMagnitude = 1.0 - inverseMagnitude * inverseMagnitude;
    float magnitude = -normalizedMagnitude * maxDisplacement;
    return decodeSurfaceNormal(encoded) * magnitude;
}

// Decode signed inward edge distance from B. Positive values are inside the
// mathematical boundary and negative values are outside it.
float decodeSignedEdgeDistance(
    vec4 encoded,
    float thickness,
    float exteriorRange
) {
    float centeredDistance = (encoded.b - 0.5) * 2.0;
    float normalizedMagnitude = centeredDistance * centeredDistance;
    return centeredDistance >= 0.0
        ? normalizedMagnitude * thickness * 4.0
        : -normalizedMagnitude * exteriorRange;
}

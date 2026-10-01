// Copyright 2025, Tim Lehmann for whynotmake.it
//
// Encodes the matte in the geometry pass and decodes it in the final pass;
// both include this one file.

// Encode the reusable SDF surface plus optical displacement into RGBA8.
// R, G, A: a 12-bit normal direction and a 12-bit displacement magnitude,
//    packed as R = angle[11:4], G = angle[3:0] | magnitude[11:8],
//    A = magnitude[7:0]. The direction is a "diamond angle": the position
//    on the |x| + |y| = 1 diamond, which decodes without trigonometry and
//    represents the four axis directions exactly.
//    Refracted content is placed by these two values, so their steps must
//    stay well below a pixel: 8 bits each would leave magnitude steps of up
//    to 1.4 device pixels at iOS 27's 60 pt edge displacement and turn
//    smooth refracted lines into staircases. The texture must be sampled
//    nearest.
// B: Signed inward edge distance (positive inside, negative outside).
// The displacement always points opposite the outward SDF normal, so the
// magnitude is one-sided.
vec4 encodeDisplacementData(
    vec2 surfaceNormal,
    float displacementMagnitude,
    float maxDisplacement,
    float signedEdgeDistance,
    float inwardRange,
    float exteriorRange
) {
    float angleCode = 0.0;
    float manhattan = abs(surfaceNormal.x) + abs(surfaceNormal.y);
    if (manhattan > 1e-4) {
        vec2 d = surfaceNormal / manhattan;
        float diamond = d.y >= 0.0
            ? (d.x >= 0.0 ? d.y : 1.0 - d.x)
            : (d.x < 0.0 ? 2.0 - d.y : 3.0 + d.x);
        angleCode = mod(floor(diamond * 1024.0 + 0.5), 4096.0);
    }
    float magnitudeCode = floor(
        clamp(-displacementMagnitude / maxDisplacement, 0.0, 1.0) * 4095.0 +
            0.5
    );
    float angleHigh = floor(angleCode / 16.0);
    float angleLow = angleCode - angleHigh * 16.0;
    float magnitudeHigh = floor(magnitudeCode / 256.0);
    float magnitudeLow = magnitudeCode - magnitudeHigh * 256.0;

    // The geometry target is RGBA8. A linear mapping across the complete
    // optical profile leaves fewer than two code points per physical pixel at
    // common thicknesses, which the narrow contour/highlight ramps show as
    // concentric bands. So each side of the mathematical edge gets half of the
    // channel with a square-root compander, which concentrates precision
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
        angleHigh / 255.0,
        (angleLow * 16.0 + magnitudeHigh) / 255.0,
        normalizedEdgeDistance,
        magnitudeLow / 255.0
    );
}

vec2 decodeSurfaceNormal(vec4 encoded) {
    vec2 codes = floor(encoded.rg * 255.0 + 0.5);
    float diamond = (codes.x * 16.0 + floor(codes.y / 16.0)) / 1024.0;
    vec2 d = vec2(
        diamond < 2.0 ? 1.0 - diamond : diamond - 3.0,
        diamond < 1.0 ? diamond : (diamond < 3.0 ? 2.0 - diamond : diamond - 4.0)
    );
    return normalize(d);
}

// Reconstruct optical displacement from the shared normal and magnitude.
vec2 decodeDisplacement(vec4 encoded, float maxDisplacement) {
    vec2 codes = floor(encoded.ga * 255.0 + 0.5);
    float magnitudeCode = mod(codes.x, 16.0) * 256.0 + codes.y;
    float magnitude = -(magnitudeCode / 4095.0) * maxDisplacement;
    return decodeSurfaceNormal(encoded) * magnitude;
}

// Decode signed inward edge distance from B. Positive values are inside the
// mathematical boundary and negative values are outside it.
float decodeSignedEdgeDistance(
    vec4 encoded,
    float inwardRange,
    float exteriorRange
) {
    float centeredDistance = (encoded.b - 0.5) * 2.0;
    float normalizedMagnitude = centeredDistance * centeredDistance;
    return centeredDistance >= 0.0
        ? normalizedMagnitude * inwardRange
        : -normalizedMagnitude * exteriorRange;
}

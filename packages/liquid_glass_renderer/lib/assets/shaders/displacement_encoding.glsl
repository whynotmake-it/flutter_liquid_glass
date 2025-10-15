// Copyright 2025, Tim Lehmann for whynotmake.it
//
// Shared utilities for encoding and decoding displacement data

// Encode displacement offset, height, and alpha into RGBA channels
// R: X displacement offset (0.5 = no offset, 0 = negative, 1 = positive)
// G: Y displacement offset (0.5 = no offset, 0 = negative, 1 = positive)
// B: Height (normalized to thickness)
// A: Alpha for anti-aliasing
vec4 encodeDisplacementData(vec2 displacement, float maxDisplacement, float height, float thickness, float alpha) {
    vec2 normalizedDisp = (displacement / maxDisplacement) * 0.5 + 0.5;
    normalizedDisp = clamp(normalizedDisp, 0.0, 1.0);
    
    float normalizedHeight = thickness > 0.0 ? clamp(height / thickness, 0.0, 1.0) : 0.0;
    
    return vec4(normalizedDisp.x, normalizedDisp.y, normalizedHeight, alpha);
}

// Decode displacement from RG channels
vec2 decodeDisplacement(vec4 encoded, float maxDisplacement) {
    vec2 normalized = encoded.rg;
    vec2 displacement = (normalized - 0.5) * 2.0 * maxDisplacement;
    return displacement;
}

// Decode height from B channel
float decodeHeight(vec4 encoded, float thickness) {
    return encoded.b * thickness;
}

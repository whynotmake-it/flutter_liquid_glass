// Copyright 2025, Tim Lehmann for whynotmake.it
//
// Shared utilities for encoding and decoding displacement data

// Encoding range for specular distance in pixels - THICKNESS INDEPENDENT
// We use 10px range to avoid clamping in the visible specular region
// The actual visual rim width (~1.5px) is controlled by k in final_render
const float SPECULAR_ENCODING_RANGE = 10.0;

// Encode displacement offset and signed distance into RGBA channels
// R: X displacement offset (0.5 = no offset, 0 = negative, 1 = positive)
// G: Y displacement offset (0.5 = no offset, 0 = negative, 1 = positive)
// B: Normalized signed distance for FIXED-WIDTH specular (0 = at edge, 1 = beyond rim)
//    Normalized by SPECULAR_RIM_WIDTH (pixels), NOT thickness
//    This makes specular width identical regardless of thickness or profile
// A: Alpha for anti-aliasing
vec4 encodeDisplacementData(vec2 displacement, float maxDisplacement, float sd, float thickness, float alpha) {
    vec2 normalizedDisp = (displacement / maxDisplacement) * 0.5 + 0.5;
    normalizedDisp = clamp(normalizedDisp, 0.0, 1.0);

    // Encode signed distance normalized by FIXED encoding range (not thickness!)
    // sd is negative inside shape (0 at edge, negative deeper inside)
    // normalizedSd: 0 = at edge, 1 = 10px inside (gives room for natural falloff)
    float normalizedSd = clamp(-sd / SPECULAR_ENCODING_RANGE, 0.0, 1.0);

    return vec4(normalizedDisp.x, normalizedDisp.y, normalizedSd, alpha);
}

// Decode displacement from RG channels
vec2 decodeDisplacement(vec4 encoded, float maxDisplacement) {
    vec2 normalized = encoded.rg;
    vec2 displacement = (normalized - 0.5) * 2.0 * maxDisplacement;
    return displacement;
}

// Decode normalized signed distance from B channel
// Returns: 0 = at edge, 1 = at center (profile-independent)
float decodeNormalizedSd(vec4 encoded) {
    return encoded.b;
}

// Decode height from B channel (legacy - kept for compatibility)
// Note: B channel now stores normalizedSd, not normalizedHeight
float decodeHeight(vec4 encoded, float thickness) {
    return encoded.b * thickness;
}

// Copyright 2025, Tim Lehmann for whynotmake.it
//
// Encodes the matte in the geometry pass and decodes it in the final pass;
// both include this one file.

// The matte is an fp16 target storing decoded fields, so the final pass
// samples it bilinearly: under animated transforms the sampling position
// moves fractionally between texels, and filtering interpolates the field
// smoothly where nearest sampling would pop whole texels at once.
//   R, G: optical displacement in matte pixels — surface normal times signed
//         magnitude, pointing inward. Continuous except across a shape's
//         medial axis, where the opposing sides blend through zero for a
//         sub-texel transition instead of a hard flip. Where the vector is
//         (near) zero the surface normal is undefined; the final pass derives
//         normals from the signed distance instead.
//   B:    signed edge distance in matte pixels (positive inside, negative
//         outside). Stored raw: fp16 keeps sub-0.1px precision across the
//         whole range, so the sqrt compander the 8-bit packing needed is
//         gone.
//   A:    the effect-support mask, for debug visualisation only.

// Signed distance written where the geometry pass early-outs. Far outside
// any contour support so bilinear taps reaching the boundary still read as
// fully exterior.
const float kOutsideDistance = -1024.0;

vec4 encodeDisplacementData(
    vec2 surfaceNormal,
    float displacementMagnitude,
    float maxDisplacement,
    float signedEdgeDistance,
    float inwardRange,
    float exteriorRange,
    float effectSupport
) {
    return vec4(
        surfaceNormal * displacementMagnitude,
        signedEdgeDistance,
        effectSupport
    );
}

// The optical displacement vector, in matte pixels.
vec2 decodeDisplacement(vec4 encoded, float maxDisplacement) {
    return encoded.rg;
}

// Signed inward edge distance in matte pixels. Positive values are inside
// the mathematical boundary and negative values are outside it.
float decodeSignedEdgeDistance(
    vec4 encoded,
    float inwardRange,
    float exteriorRange
) {
    return encoded.b;
}

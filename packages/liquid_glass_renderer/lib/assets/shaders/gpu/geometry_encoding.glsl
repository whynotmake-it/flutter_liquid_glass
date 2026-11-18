// Distances are capped here, well within 16-bit float range. A hidden shape
// reports a distance of 1e9, which would otherwise become infinity and break
// the blending between texels.
const float kInwardLimit = 16000.0;

// R: the distance to the edge, positive inside. GB: the direction the surface
// faces, scaled by the square root of the gradient's length, so it refracts
// less where a smooth union shortens the gradient. A: half the thickness.
vec4 encodeGeometry(float distance, vec2 gradient, float halfMinor) {
    float gradientLength = length(gradient);
    vec2 normal = gradientLength > 0.0001
        ? gradient / gradientLength
        : vec2(0.0);
    return vec4(
        clamp(-distance, -kInwardLimit, kInwardLimit),
        normal * sqrt(clamp(gradientLength, 0.0, 1.0)),
        halfMinor
    );
}

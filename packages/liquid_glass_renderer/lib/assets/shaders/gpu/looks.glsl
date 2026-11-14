// The look of glass whose shapes differ in tint or material, which the atlas
// pass writes beside the geometry for the final shader to read: the tint
// premultiplied, then saturation, transmission gamma, vibrancy and
// visibility, then the shares of the color models (colorModelSharesOf in
// liquid_glass_final_render_core.glsl).

#include "geometry_uniforms.glsl"

struct Look {
    vec4 tint;
    vec4 response;
    vec4 shares;
};

// Entry [index]: a tint, and the response with visibility plus twice the
// color model's code (0 direct, 1..3 the layer's slots) in w.
Look lookAt(int index) {
    vec4 tint = uLookTints[index];
    vec4 response = uLookResponses[index];
    float code = floor(response.w * 0.5);
    return Look(
        vec4(tint.rgb * tint.a, tint.a),
        vec4(response.xyz, response.w - 2.0 * code),
        vec4(equal(vec4(code), vec4(0.0, 1.0, 2.0, 3.0)))
    );
}

Look mixLooks(Look a, Look b, float weightA) {
    return Look(
        mix(b.tint, a.tint, weightA),
        mix(b.response, a.response, weightA),
        mix(b.shares, a.shares, weightA)
    );
}

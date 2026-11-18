#include "geometry_uniforms.glsl"

struct Look {
    vec4 tint;
    vec4 response;
    vec4 weights;
};

Look lookAt(int index) {
    vec4 tint = uLookTints[index];
    vec4 response = uLookResponses[index];
    float code = floor(response.w / kLookModelStride);
    return Look(
        vec4(tint.rgb * tint.a, tint.a),
        vec4(response.xyz, response.w - kLookModelStride * code),
        colorModelWeightsOf(code)
    );
}

Look mixLooks(Look a, Look b, float weightA) {
    return Look(
        mix(b.tint, a.tint, weightA),
        mix(b.response, a.response, weightA),
        mix(b.weights, a.weights, weightA)
    );
}

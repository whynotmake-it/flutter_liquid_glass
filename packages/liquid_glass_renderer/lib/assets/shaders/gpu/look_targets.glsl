// Impeller's OpenGL ES backend draws into one color attachment, so there the
// atlas and each look take a pass of their own.

#if defined(LOOK_ONLY_GEOMETRY)
void writeLook(Look look) {}
#elif defined(LOOK_ONLY_TINT)
void writeLook(Look look) {
    fragColor = look.tint;
}
#elif defined(LOOK_ONLY_RESPONSE)
void writeLook(Look look) {
    fragColor = look.response;
}
#elif defined(LOOK_ONLY_WEIGHTS)
void writeLook(Look look) {
    fragColor = look.weights;
}
#else
layout(location = 1) out vec4 lookTint;
#if LOOKS > 1
layout(location = 2) out vec4 lookResponse;
layout(location = 3) out vec4 lookWeights;
#endif

void writeLook(Look look) {
    lookTint = look.tint;
#if LOOKS > 1
    lookResponse = look.response;
    lookWeights = look.weights;
#endif
}
#endif

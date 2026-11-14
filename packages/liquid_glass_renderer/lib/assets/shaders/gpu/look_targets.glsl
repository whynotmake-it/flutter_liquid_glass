// The atlas pass's targets beside the geometry: the tint alone (LOOKS 1),
// or the whole look (LOOKS 2), at the geometry's texels.
//
// With LOOK_ONLY the pass has the one target of the geometry and writes one
// thing into it: the tint (0), the response (1), the shares (2) or the
// geometry itself (3). Impeller's OpenGL ES backend draws into one color
// attachment, so there the atlas and each look take a pass of their own.

#ifdef LOOK_ONLY
void writeLook(Look look) {
#if LOOK_ONLY == 0
    fragColor = look.tint;
#elif LOOK_ONLY == 1
    fragColor = look.response;
#elif LOOK_ONLY == 2
    fragColor = look.shares;
#endif
}
#else
layout(location = 1) out vec4 lookTint;
#if LOOKS > 1
layout(location = 2) out vec4 lookResponse;
layout(location = 3) out vec4 lookShares;
#endif

void writeLook(Look look) {
    lookTint = look.tint;
#if LOOKS > 1
    lookResponse = look.response;
    lookShares = look.shares;
#endif
}
#endif

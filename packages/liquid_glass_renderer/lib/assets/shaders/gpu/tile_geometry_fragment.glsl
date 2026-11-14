// Draws a geometry atlas of shapes: its constant tiles and its table
// (tile_fill.glsl), and its ring strips, whose texels evaluate the shapes in
// the format of matte_encoding.glsl, with LOOKS their look beside it
// (look_targets.glsl).
//
// A strip's texel spans vValue.z buffer pixels a side; the quad's xy carries
// where gl_FragCoord (0, 0) would sit, so a texel's center is the buffer
// point gl_FragCoord * vValue.z + vValue.xy, and w how far from every shape's
// box a texel still matters. The quad's ramp lists the shapes its texels
// evaluate (listedSceneSample); with 64 or more in x it names a run of rows
// instead, x - 64 the first and y how many.

precision highp float;

#ifndef LOOKS
#define LOOKS 0
#endif
#define SCENE_LOOKS LOOKS

#include "sdf.glsl"
#include "matte_encoding.glsl"

flat in vec4 vValue;
flat in vec4 vRamp;

layout(location = 0) out vec4 fragColor;
#if LOOKS
#include "look_targets.glsl"
#endif

#include "tile_fill.glsl"

void main() {
    if (isFill()) {
        writeFill();
        return;
    }
    vec2 position = gl_FragCoord.xy * vValue.z + vValue.xy;

    bool listed = vRamp.x < 64.0;
    int first = int(vRamp.x) & 15;
    int count = int(vRamp.y);
    // A texel farther from every shape's box than the reach, the blend
    // budget and two texels is past anything a read blends in.
    float outsideSquared = listed
        ? listedBoundsOutsideSquared(position, vRamp)
        : sceneBoundsOutsideSquared(position, first, count);
    float reach = vValue.w + 2.0 * vValue.z;
    if (outsideSquared > reach * reach) {
        fragColor = vec4(kFarInward, 0.0, 0.0, 0.0);
#if LOOKS
        writeLook(Look(vec4(0.0), vec4(0.0), vec4(0.0)));
#endif
        return;
    }

    SceneSample scene;
    if (listed) {
        scene = listedSceneSample(position, vRamp);
    } else {
        scene = sceneSample(position, first, count);
    }
    fragColor = encodeMatte(
        scene.distance,
        scene.opticalNormal,
        scene.halfMinor
    );
#if LOOKS
    writeLook(scene.look);
#endif
}

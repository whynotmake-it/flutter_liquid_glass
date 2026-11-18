precision highp float;

#ifndef LOOKS
#define LOOKS 0
#endif
#define SCENE_LOOKS LOOKS

#include "sdf.glsl"
#include "geometry_encoding.glsl"

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

    bool listed = vRamp.x < RAMP_RUN;
    int first = int(vRamp.x) & SHAPE_INDEX_MASK;
    int count = int(vRamp.y);
    // A texel farther from every shape's box than the reach, the blend
    // budget and two texels is past anything a read blends in.
    float outsideSquared = listed
        ? listedBoundsOutsideSquared(position, vRamp)
        : sceneBoundsOutsideSquared(position, first, count);
    float reach = vValue.w + 2.0 * vValue.z;
    if (outsideSquared > reach * reach) {
        fragColor = vec4(kFarOutside, 0.0, 0.0, 0.0);
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
    fragColor = encodeGeometry(
        scene.distance,
        scene.opticalNormal,
        scene.halfMinor
    );
#if LOOKS
    writeLook(scene.look);
#endif
}

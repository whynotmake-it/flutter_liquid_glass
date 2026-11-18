#version 460 core
precision highp float;

#include <flutter/runtime_effect.glsl>

// What lies over a glass shape as the shape shows it: bent away from the
// rim, and its colors parted the way the glass parts what lies under it.
// Drawn twice over the shape, in its own coordinates: first what the content
// takes of what lies under it, color by color, then the content.

// impellerc gives every uniform declaration its own Metal buffer, bound per
// draw, where Vulkan binds one struct.
#include "bent_content_lanes.glsl"
#include "shader_constants.glsl"
uniform sampler2D uContent;

out vec4 fragColor;

// How deep a point lies inside the shape, a box with circular corners
// centered on the origin (x), the outward normal of its outline there (yz),
// and how fast that normal turns along the outline through the point (w):
// one over the distance to the corner's center, nothing along a straight
// side.
vec4 rim(vec2 fromCenter) {
    vec2 corner = abs(fromCenter) - (uSize * 0.5 - uRadius);
    vec2 outside = max(corner, 0.0);
    float far = length(outside);
    vec2 normal = far > 0.0
        ? outside / far
        : (corner.x > corner.y ? vec2(1.0, 0.0) : vec2(0.0, 1.0));
    // A read beside the point never turns the normal past a right angle.
    float turn = min(outside.x, outside.y) > 0.0
        ? 1.0 / max(far, uParting.x)
        : 0.0;
    return vec4(
        uRadius - far - min(max(corner.x, corner.y), 0.0),
        normal * sign(fromCenter),
        turn
    );
}

// How deep lies what a bend of bend.x at the rim, falling along a quarter
// circle to nothing bend.y deep, shows at a depth.
float bent(float depth, vec2 bend) {
    float x = 1.0 - clamp(depth / max(bend.y, 0.0001), 0.0, 1.0);
    return depth + bend.x * (1.0 - sqrt(1.0 - x * x));
}

// How much deeper lies what the bends show at a depth: no deeper than the
// middle of the shape, where the outline's normals meet.
float sunk(float depth) {
    return min(
        bent(bent(depth, uBends.xy), uBends.zw),
        min(uSize.x, uSize.y) * 0.5
    ) - depth;
}

// The content at a point of the shape's coordinates, shown at a depth inside
// the outline: nothing of the content shows outside the shape.
vec4 read(vec2 source, float depth) {
    return texture(uContent, (source - uPictureOrigin) * uPictureScale) *
        clamp(depth / uPixel + 0.5, 0.0, 1.0);
}

// What the shape shows `steps` thirds of the parting beside a point.
//
// The outline there is the point's own, a circle about the corner's center
// or a straight side, and not worked out anew: that takes 64 work registers
// on a Mali where this takes 32. `step` holds how a third moves what is read
// (xy: the third itself, less what the turn of the normal takes back as deep
// as the point reads), how far it leads out of the shape (z), and how much
// the outline curves away under it (w).
vec4 beside(vec2 at, vec4 edge, vec4 step, float steps) {
    float depth = edge.x - (step.z + step.w * steps) * steps;
    return read(at + step.xy * steps - edge.yz * sunk(depth), depth);
}

void main() {
    vec2 at = FlutterFragCoord().xy;
    vec4 edge = rim(at - uSize * 0.5);
    float deeper = sunk(edge.x);
    vec4 own = read(at - edge.yz * deeper, edge.x);
    // Every pixel takes these reads, also where the parting has faded out: a
    // branch around them costs as many work registers again.
    vec2 third = vec2(
        dot(edge.yz, kPartingMirror.xy),
        dot(edge.yz, kPartingMirror.yz)
    ) * (uParting.x / 3.0);
    vec2 along = vec2(-edge.z, edge.y);
    float sideways = dot(third, along);
    vec4 step = vec4(
        third - along * (sideways * edge.w * deeper),
        dot(third, edge.yz),
        0.5 * sideways * sideways * edge.w
    );
    vec4 tap = beside(at, edge, step, 1.0);
    vec2 red = tap.ra * kPartingSide.x;
    vec2 green = own.ga * kPartingMiddle.x + tap.ga * kPartingMiddle.y;
    tap = beside(at, edge, step, 2.0);
    red += tap.ra * kPartingSide.y;
    green += tap.ga * kPartingMiddle.z;
    red += beside(at, edge, step, 3.0).ra * kPartingSide.z;
    tap = beside(at, edge, step, -1.0);
    vec2 blue = tap.ba * kPartingSide.x;
    green += tap.ga * kPartingMiddle.y;
    tap = beside(at, edge, step, -2.0);
    blue += tap.ba * kPartingSide.y;
    green += tap.ga * kPartingMiddle.z;
    blue += beside(at, edge, step, -3.0).ba * kPartingSide.z;
    float parted = clamp(1.0 - edge.x / max(uParting.y, 0.0001), 0.0, 1.0);
    vec3 color = mix(own.rgb, vec3(red.x, green.x, blue.x), parted);
    vec3 cover = mix(vec3(own.a), vec3(red.y, green.y, blue.y), parted);
    fragColor = mix(
        vec4(1.0 - cover, 1.0),
        vec4(color, max(cover.r, max(cover.g, cover.b))),
        uPass
    );
}

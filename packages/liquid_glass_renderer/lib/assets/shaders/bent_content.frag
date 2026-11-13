#version 460 core
precision highp float;

#include <flutter/runtime_effect.glsl>

// What lies over a glass shape as the shape shows it: bent away from the
// rim, and its colors parted the way the glass parts what lies under it.
// Drawn twice over the shape, in its own coordinates: first what the content
// takes of what lies under it, color by color, then the content.

// The floats Dart writes, four to a vec4 in the order it writes them, and the
// names below are lanes of them: impellerc gives every uniform declaration its
// own Metal buffer, bound per draw, where Vulkan binds one struct.
uniform vec4 uBent[4];
uniform sampler2D uContent;

#define uSize uBent[0].xy
#define uRadius uBent[0].z
// 0 draws what the content takes, 1 the content.
#define uPass uBent[0].w
// Where the picture of the content starts in the shape's coordinates, and
// one over its size.
#define uPictureOrigin uBent[1].xy
#define uPictureScale uBent[1].zw
// The amount and height of the first bend, then of the second.
#define uBends uBent[2]
// How far the colors part and how deep from the rim the parting fades out.
#define uParting uBent[3].xy
// Logical pixels per device pixel.
#define uPixel uBent[3].z

out vec4 fragColor;

// The mirror that turns an edge's outward normal into the way glass parts
// colors along, as the rows (x, y) and (y, z): the same one the glass itself
// parts by.
const vec3 kPartingMirror = vec3(-0.258819, 0.965926, 0.258819);

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
    // Seven reads a third of the reach apart along the parting's way: red
    // takes the three ahead, blue the three behind and green the five in the
    // middle, each weighted toward its far end. Every pixel takes them, also
    // where the parting has faded out: a branch around them costs as many
    // work registers again.
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
    vec2 red = tap.ra / 6.0;
    vec2 green = own.ga / 3.0 + tap.ga * (2.0 / 9.0);
    tap = beside(at, edge, step, 2.0);
    red += tap.ra / 3.0;
    green += tap.ga / 9.0;
    red += beside(at, edge, step, 3.0).ra / 2.0;
    tap = beside(at, edge, step, -1.0);
    vec2 blue = tap.ba / 6.0;
    green += tap.ga * (2.0 / 9.0);
    tap = beside(at, edge, step, -2.0);
    blue += tap.ba / 3.0;
    green += tap.ga / 9.0;
    blue += beside(at, edge, step, -3.0).ba / 2.0;
    float parted = clamp(1.0 - edge.x / max(uParting.y, 0.0001), 0.0, 1.0);
    vec3 color = mix(own.rgb, vec3(red.x, green.x, blue.x), parted);
    vec3 cover = mix(vec3(own.a), vec3(red.y, green.y, blue.y), parted);
    fragColor = mix(
        vec4(1.0 - cover, 1.0),
        vec4(color, max(cover.r, max(cover.g, cover.b))),
        uPass
    );
}

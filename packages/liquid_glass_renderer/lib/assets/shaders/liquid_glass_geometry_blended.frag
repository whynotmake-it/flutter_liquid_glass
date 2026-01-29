// Copyright 2025, Tim Lehmann for whynotmake.it
//
// Geometry precomputation shader for blended liquid glass shapes
// This shader pre-computes the refraction displacement and encodes it into a texture
// Only needs to be re-run when shape geometry or layout changes

#version 460 core
precision mediump float;

#include <flutter/runtime_effect.glsl>
#include "sdf.glsl"
#include "shared.glsl"
#include "displacement_encoding.glsl"

layout(location = 0) uniform vec2 uSize;
layout(location = 1) uniform vec4 uOpticalProps;
// Edge profile type: 0=convexCircle, 1=convexSquircle, 2=concave, 3=lip
layout(location = 2) uniform float uEdgeProfile;
layout(location = 3) uniform float uNumShapes;
layout(location = 4) uniform float uShapeData[MAX_SHAPES * 6];

float uThickness = uOpticalProps.z;
float uRefractiveIndex = uOpticalProps.x;
float uBlend = uOpticalProps.w;

layout(location = 0) out vec4 fragColor;

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;

    #ifdef IMPELLER_TARGET_OPENGLES
        vec2 screenUV = vec2(fragCoord.x / uSize.x, 1.0 - (fragCoord.y / uSize.y));
    #else
        vec2 screenUV = vec2(fragCoord.x / uSize.x, fragCoord.y / uSize.y);
    #endif

    float sd = sceneSDF(fragCoord, int(uNumShapes), uShapeData, uBlend);

    float foregroundAlpha = 1.0 - smoothstep(-2.0, 0.0, sd);
    if (foregroundAlpha < 0.01) {
        fragColor = vec4(0.0);
        return;
    }

    if (sd >= 0.0 || uThickness <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }

    // Get SDF gradient for edge direction
    float dx = dFdx(sd);
    float dy = dFdy(sd);

    // Check for flat top region (center of shape, beyond thickness depth)
    // Original behavior: when sd < -thickness, surface is flat with normal (0,0,1)
    bool isFlatTop = sd < -uThickness;

    // Normalized distance from edge (0 at edge, 1 at center)
    // Clamp to 1.0 for flat top region
    float normalizedDist = clamp(-sd / uThickness, 0.0, 1.0);

    // Get profile height for refraction distance calculation
    float profileHeight = getProfileHeight(normalizedDist, uEdgeProfile);

    // Calculate height - flat top region gets max height
    float height = isFlatTop ? uThickness : profileHeight * uThickness;

    vec3 normal;
    if (isFlatTop) {
        // Flat top region: normal points straight up, no refraction angle
        // This matches the original behavior where center has no distortion
        normal = vec3(0.0, 0.0, 1.0);
    } else {
        // Edge region: compute normal from profile derivative
        float profileDerivative = getProfileDerivative(normalizedDist, uEdgeProfile);

        // Compute edge direction from SDF gradient (points toward nearest edge)
        float gradLen = length(vec2(dx, dy));

        // At center where gradient is tiny, also use flat normal
        if (gradLen < 0.001) {
            normal = vec3(0.0, 0.0, 1.0);
        } else {
            vec2 edgeDir = vec2(dx, dy) / gradLen;

            // Compute normal from profile derivative using proper 2D→3D mapping
            // For a curve y=f(x), the outward normal is (-f'(x), 1) / sqrt(f'^2 + 1)
            // Using NEGATIVE derivative ensures:
            //   - Convex (derivative > 0): normal.xy points toward center → focusing
            //   - Concave (derivative < 0): normal.xy points toward edge → diverging
            float normalLen = sqrt(profileDerivative * profileDerivative + 1.0);
            float nz = 1.0 / normalLen;
            float nxy = -profileDerivative / normalLen;

            // Smoothly blend toward flat normal as we approach center
            // This prevents discontinuities at the boundary
            float centerBlend = smoothstep(0.85, 0.98, normalizedDist);
            nxy *= (1.0 - centerBlend);
            nz = mix(nz, 1.0, centerBlend);

            normal = normalize(vec3(edgeDir.x * nxy, edgeDir.y * nxy, nz));
        }
    }

    float baseHeight = uThickness * 8.0;
    vec3 incident = vec3(0.0, 0.0, -1.0);

    float invRefractiveIndex = 1.0 / uRefractiveIndex;
    vec3 baseRefract = refract(incident, normal, invRefractiveIndex);
    float baseRefractLength = (height + baseHeight) / max(0.001, abs(baseRefract.z));
    vec2 displacement = baseRefract.xy * baseRefractLength;

    float maxDisplacement = uThickness * 10.0;

    // Encode signed distance (not height) for profile-independent specular
    fragColor = encodeDisplacementData(displacement, maxDisplacement, sd, uThickness, foregroundAlpha);
}

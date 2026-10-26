// Copyright 2025, Tim Lehmann for whynotmake.it

#version 460 core

// Validation variant of the shared core. It defines
// LIQUID_GLASS_VALIDATE_MATTE_ORDER, so the final shader paints magenta where
// a frame samples a matte rewritten before that frame was rasterized. The
// shipped liquid_glass_final_render.frag compiles without the define and keeps
// its uniform layout and texture reads unchanged; only this variant, loaded
// under the same-named compile-time flag, carries the check.

#define SHAPE_APPEARANCE 0
#define SHAPE_TINT 0
#define LIQUID_GLASS_VALIDATE_MATTE_ORDER 1
#include "liquid_glass_final_render_core.glsl"

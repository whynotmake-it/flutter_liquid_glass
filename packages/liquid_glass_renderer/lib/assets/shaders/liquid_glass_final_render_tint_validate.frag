// Copyright 2025, Tim Lehmann for whynotmake.it

#version 460 core

// Validation variant of the shared core, with the tint-only material map. See
// liquid_glass_final_render_validate.frag.

#define SHAPE_APPEARANCE 0
#define SHAPE_TINT 1
#define LIQUID_GLASS_VALIDATE_MATTE_ORDER 1
#include "liquid_glass_final_render_core.glsl"

// Copyright 2025, Tim Lehmann for whynotmake.it

#version 460 core

// One shape, worked out per fragment; one appearance, any color models.
// See FinalShaderVariant.

#define SHAPE_APPEARANCE 0
#define SHAPE_TINT 0
#define SHAPE_GEOMETRY 1
#include "liquid_glass_final_render_core.glsl"

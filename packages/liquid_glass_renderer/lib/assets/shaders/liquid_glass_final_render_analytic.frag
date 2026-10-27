// Copyright 2025, Tim Lehmann for whynotmake.it

#version 460 core

// Shapes evaluated per fragment (analytic_geometry.glsl) instead of read
// from a matte. It binds only the backdrop.

#define SHAPE_APPEARANCE 0
#define SHAPE_TINT 0
#define ANALYTIC_GEOMETRY 1
#include "liquid_glass_final_render_core.glsl"

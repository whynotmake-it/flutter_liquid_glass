// Copyright 2025, Tim Lehmann for whynotmake.it

#version 460 core

// Per-shape tints; the direct color model alone.
// See FinalShaderVariant.

#define SHAPE_APPEARANCE 0
#define SHAPE_TINT 1
#define COLOR_MODELS COLOR_MODELS_DIRECT
#include "liquid_glass_final_render_core.glsl"

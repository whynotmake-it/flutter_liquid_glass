// Copyright 2025, Tim Lehmann for whynotmake.it

#version 460 core

// Shapes evaluated per fragment; one iOS 27 color model in slot 0 alone.
// See FinalShaderVariant.

#define SHAPE_APPEARANCE 0
#define SHAPE_TINT 0
#define ANALYTIC_GEOMETRY 1
#define COLOR_MODELS COLOR_MODELS_IOS27
#include "liquid_glass_final_render_core.glsl"

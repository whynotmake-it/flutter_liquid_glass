// Copyright 2025, Tim Lehmann for whynotmake.it

#version 460 core

// Per-shape tints; one iOS 27 color model in slot 0 alone.
// See FinalShaderVariant.

#define SHAPE_APPEARANCE 0
#define SHAPE_TINT 1
#define COLOR_MODELS COLOR_MODELS_IOS27
#include "liquid_glass_final_render_core.glsl"

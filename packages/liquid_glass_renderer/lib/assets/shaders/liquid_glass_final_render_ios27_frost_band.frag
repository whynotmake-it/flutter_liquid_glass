// Copyright 2025, Tim Lehmann for whynotmake.it

#version 460 core

// One appearance; one iOS 27 color model in slot 0 alone.
// Frosts an unblurred copy itself and draws a scroll edge beside the glass
// from the same copy. See FinalShaderVariant.

#define SHAPE_APPEARANCE 0
#define SHAPE_TINT 0
#define COLOR_MODELS COLOR_MODELS_IOS27
#define FROST 1
#define FROST_BAND 1
#include "liquid_glass_final_render_core.glsl"

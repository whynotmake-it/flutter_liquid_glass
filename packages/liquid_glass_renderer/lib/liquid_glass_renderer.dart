/// Liquid Glass Effect for Flutter
library liquid_glass_renderer;

import 'package:flutter/foundation.dart' show kDebugMode;

export 'src/fake_glass.dart' show FakeGlass;
export 'src/glass_glow.dart' show GlassGlow, GlassGlowLayer;
export 'src/liquid_glass.dart' show LiquidGlass;
export 'src/liquid_glass_blend_group.dart' show LiquidGlassBlendGroup;
export 'src/liquid_glass_settings.dart' show LiquidGlassSettings;
export 'src/liquid_shape.dart';
export 'src/logging.dart' show LgrLogs;
export 'src/rendering/liquid_glass_layer.dart' show LiquidGlassLayer;
export 'src/stretch.dart'
    show LiquidStretch, OffsetResistanceExtension, RawLiquidStretch;

/// Whether to paint the liquid glass geometry texture for debugging purposes.
///
/// When enabled, geometry textures will be drawn directly instead of the
/// liquid glass effect.
///
/// Will be set to `false` in release builds.
@pragma('vm:platform-const-if', !kDebugMode)
bool debugPaintLiquidGlassGeometry = false;

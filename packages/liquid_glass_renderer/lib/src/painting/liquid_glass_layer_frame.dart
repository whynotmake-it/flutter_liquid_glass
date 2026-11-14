import 'package:flutter/foundation.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_field.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_glow.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_settings.dart';

/// One frame of a live `LiquidGlassLayer`: what it shades with.
@immutable
class LiquidGlassLayerFrame {
  /// Describes one frame of a layer.
  const LiquidGlassLayerFrame({
    this.settings = const LiquidGlassSettings(),
    this.field,
    this.glow,
  });

  /// See `LiquidGlassLayer.settings`.
  final LiquidGlassSettings settings;

  /// See `LiquidGlassLayer.field`.
  final LiquidGlassField? field;

  /// See `LiquidGlassLayer.glow`.
  final LiquidGlassGlow? glow;
}

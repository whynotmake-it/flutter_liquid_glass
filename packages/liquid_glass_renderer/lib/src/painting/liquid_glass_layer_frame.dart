import 'package:flutter/foundation.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_appearance.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_field.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_settings.dart';

/// One frame of a live `LiquidGlassLayer`: what it shades with.
@immutable
final class LiquidGlassLayerFrame {
  /// Describes one frame of a layer.
  const LiquidGlassLayerFrame({
    required this.settings,
    this.field,
    this.defaultAppearance,
  });

  /// What the layer's glass draws with (`LiquidGlassLayer.settings`).
  final LiquidGlassSettings settings;

  /// See `LiquidGlassLayer.field`.
  final LiquidGlassField? field;

  /// See `LiquidGlassLayer.defaultAppearance`.
  final LiquidGlassAppearance? defaultAppearance;

  @override
  bool operator ==(Object other) =>
      other is LiquidGlassLayerFrame &&
      other.settings == settings &&
      other.field == field &&
      other.defaultAppearance == defaultAppearance;

  @override
  int get hashCode => Object.hash(settings, field, defaultAppearance);

  @override
  String toString() =>
      'LiquidGlassLayerFrame($settings'
      '${field == null ? '' : ', field: $field'}'
      '${defaultAppearance == null ? '' : ', '
                'defaultAppearance: $defaultAppearance'})';
}

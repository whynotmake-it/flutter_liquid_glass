import 'dart:ui' show Brightness, Color;

import 'package:flutter/foundation.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_color_model.dart';

/// Lightweight color and materialization controls for one glass shape.
///
/// Optical geometry and surface lighting belong to the containing
/// `LiquidGlassLayer`. These values may differ between shapes that share a
/// layer.
///
/// Colors and color transfers are display-referred. The defaults of the
/// unnamed constructor may be retuned before 1.0; the version-named presets
/// (`ios27*`) track Apple's appearance on that OS version.
@immutable
final class LiquidGlassAppearance {
  /// Creates a per-shape glass appearance.
  ///
  /// The default [colorModel] is [LiquidGlassColorModel.direct], which adds
  /// no material of its own; [LiquidGlassAppearance.ios27Regular] and
  /// [LiquidGlassAppearance.ios27Clear] are the iOS 27 ones.
  const LiquidGlassAppearance({
    this.tint = const Color(0x00000000),
    this.visibility = 1,
    this.colorModel = const LiquidGlassColorModel.direct(),
  });

  /// The iOS 27 regular material (`Glass.regular`, which Apple also uses
  /// for toolbars and `.glass` buttons) in [brightness]. Its face follows
  /// the size of the shape that wears it (see [LiquidGlassColorModel]).
  const LiquidGlassAppearance.ios27Regular({
    required Brightness brightness,
    this.tint = const Color(0x00000000),
    this.visibility = 1,
  }) : colorModel = brightness == Brightness.dark
           ? const LiquidGlassColorModel.ios27Regular(
               brightness: Brightness.dark,
             )
           : const LiquidGlassColorModel.ios27Regular(
               brightness: Brightness.light,
             );

  /// The iOS 27 `Glass.clear` appearance, identical in light and dark and
  /// at every size.
  const LiquidGlassAppearance.ios27Clear({
    this.tint = const Color(0x00000000),
    this.visibility = 1,
  }) : colorModel = const LiquidGlassColorModel.ios27Clear();

  /// Material tint; alpha controls how strongly it mixes with the backdrop.
  /// Every constructor defaults to no tint.
  final Color tint;

  /// Shape materialization progress from zero to one. Glass draws a value
  /// past either end, such as a spring's overshoot, as that end.
  ///
  /// This is one shape's own visibility; a `LiquidGlassVisibility` above the
  /// shape fades every shape below it, and the shape shows the product of
  /// the two.
  final double visibility;

  /// The transfer model used to combine [tint] with the backdrop.
  ///
  /// [LiquidGlassColorModel.direct] carries its own saturation, gamma and
  /// vibrancy; the iOS 27 models derive the accompanying tonal response
  /// from their fit, for the size of the shape that wears the appearance.
  final LiquidGlassColorModel colorModel;

  /// Returns a copy with the supplied appearance controls replaced.
  LiquidGlassAppearance copyWith({
    Color? tint,
    double? visibility,
    LiquidGlassColorModel? colorModel,
  }) => LiquidGlassAppearance(
    tint: tint ?? this.tint,
    visibility: visibility ?? this.visibility,
    colorModel: colorModel ?? this.colorModel,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiquidGlassAppearance &&
          other.tint == tint &&
          other.visibility == visibility &&
          other.colorModel == colorModel;

  @override
  int get hashCode => Object.hash(tint, visibility, colorModel);

  @override
  String toString() => 'LiquidGlassAppearance($tint, $visibility, $colorModel)';
}

/// [visibility] as glass draws it: within zero to one.
@internal
double drawnVisibility(double visibility) => clampDouble(visibility, 0, 1);

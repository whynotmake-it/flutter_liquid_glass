import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_appearance.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_settings.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_shadow.dart';

/// Settings, an appearance and shadows that belong together: one glass as
/// its layer, its shapes and their shadows draw it.
///
/// The settings go to a `LiquidGlassLayer`, the appearance to the layer as
/// its default or to a `LiquidGlass`, the shadows to a `LiquidGlass`. The
/// `ios27` constructors take the brightness and the Liquid Glass slider
/// position once and give all three for them.
@immutable
final class LiquidGlassMaterial {
  /// A material of [settings], [appearance] and [shadows].
  const LiquidGlassMaterial({
    required this.settings,
    required this.appearance,
    this.shadows = const [],
  });

  /// iOS 27 regular glass (`Glass.regular`, which Apple also uses for
  /// toolbars and `.glass` buttons) in [brightness], at the Liquid Glass
  /// slider position [sliderPosition] and tinted with [tint].
  ///
  /// It is [LiquidGlassSettings.ios27Regular],
  /// [LiquidGlassAppearance.ios27Regular] and
  /// [LiquidGlassShadow.ios27Regular].
  factory LiquidGlassMaterial.ios27Regular({
    required Brightness brightness,
    double sliderPosition = 0,
    Color? tint,
  }) => LiquidGlassMaterial(
    settings: LiquidGlassSettings.ios27Regular(
      brightness: brightness,
      sliderPosition: sliderPosition,
    ),
    appearance: tint == null
        ? LiquidGlassAppearance.ios27Regular(brightness: brightness)
        : LiquidGlassAppearance.ios27Regular(
            brightness: brightness,
            tint: tint,
          ),
    shadows: brightness == Brightness.dark
        ? const [LiquidGlassShadow.ios27Regular(brightness: Brightness.dark)]
        : const [LiquidGlassShadow.ios27Regular(brightness: Brightness.light)],
  );

  /// iOS 27 clear glass (`Glass.clear`), identical in light and dark, at
  /// the Liquid Glass slider position [sliderPosition] and tinted with
  /// [tint].
  ///
  /// It is [LiquidGlassSettings.ios27Clear] and
  /// [LiquidGlassAppearance.ios27Clear]; clear glass casts no shadow on iOS.
  factory LiquidGlassMaterial.ios27Clear({
    double sliderPosition = 0,
    Color? tint,
  }) => LiquidGlassMaterial(
    settings: LiquidGlassSettings.ios27Clear(sliderPosition: sliderPosition),
    appearance: tint == null
        ? const LiquidGlassAppearance.ios27Clear()
        : LiquidGlassAppearance.ios27Clear(tint: tint),
  );

  /// What the layer of the glass draws with.
  final LiquidGlassSettings settings;

  /// How a shape of the glass looks.
  final LiquidGlassAppearance appearance;

  /// The shadows a shape of the glass casts.
  final List<LiquidGlassShadow> shadows;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiquidGlassMaterial &&
          other.settings == settings &&
          other.appearance == appearance &&
          listEquals(other.shadows, shadows);

  @override
  int get hashCode =>
      Object.hash(settings, appearance, Object.hashAll(shadows));

  @override
  String toString() => 'LiquidGlassMaterial($settings, $appearance, $shadows)';
}

import 'dart:math' as math;
import 'dart:ui' show Brightness;

import 'package:meta/meta.dart';

/// A wide blur of the backdrop that glass mixes into what it shows through.
///
/// iOS 27 glass is not one blur. It keeps the backdrop sharp, or blurs it a
/// little, and mixes a far wider blur of the same backdrop into it: light
/// glass takes the lighter of the two in every channel, dark glass the
/// darker, and the Liquid Glass slider covers the backdrop with the wide blur
/// outright. A dark line under light glass turns pale and stays a sharp
/// line, where one blur wide enough to pale it would smear it away.
///
/// The mix runs on the backdrop before the glass refracts and colours it, on
/// display values: every channel moves to the wide blur by [lighten] where
/// the blur is lighter and by [darken] where it is darker, and the wide blur
/// then covers the result by [cover].
///
/// The numbers of the `ios27` constructors are read from UIKit on iOS 27.
/// With them a model of the glass's face lies 1 to 4 levels out of 255 from
/// captures of native glass over a fine grid, where one blur lies 13 to 37.
///
/// Near, not identical: iOS takes its wide blur from the whole screen, the
/// renderer from the part of the backdrop it copies for the glass, a few
/// points wider than the glass. The two part where what lies just outside
/// the glass differs sharply from what lies under it. iOS also mixes the
/// wide blur in where the glass lies and bends only the backdrop at the
/// glass's edge; the renderer bends the mix, so in the bevel the wide blur
/// comes from where the bent backdrop does. The renderer draws its wide blur
/// from averages of the copy over squares about one sigma wide, read
/// smoothly between them, which costs it two small passes a glass.
///
/// Glass draws its haze where it reads a copy of the backdrop taken in the
/// same frame. Where it reads the backdrop live (turned or skewed glass,
/// glass over a platform view, the web, a device without shader filters)
/// and where it is drawn flat, one blur stands in for both:
/// `LiquidGlassSettings.frostSigmaAt`.
@immutable
final class LiquidGlassHaze {
  /// A haze of a blur [sigma] logical pixels wide, mixed in by [lighten],
  /// [darken] and [cover], each from `0` to `1`.
  const LiquidGlassHaze({
    this.sigma = ios27Sigma,
    this.lighten = 0,
    this.darken = 0,
    this.cover = 0,
  });

  /// No haze: the glass shows the backdrop under its frost alone.
  const LiquidGlassHaze.none() : this(sigma: 0);

  /// The haze of iOS 27 regular glass in [brightness] at the Settings Liquid
  /// Glass slider position [tintAmount] (`0` Clear, `1` Tinted).
  ///
  /// Light glass lightens and dark glass darkens, by 0.675 at `0` rising to
  /// 0.9 at the middle tick, and the slider covers the backdrop by its own
  /// position.
  factory LiquidGlassHaze.ios27Regular({
    required Brightness brightness,
    double tintAmount = 0,
  }) {
    final amount = tintAmount.clamp(0.0, 1.0);
    final mix = 0.675 + 0.45 * math.min(amount, 0.5);
    final dark = brightness == Brightness.dark;
    return LiquidGlassHaze(
      lighten: dark ? 0 : mix,
      darken: dark ? mix : 0,
      cover: amount,
    );
  }

  /// The haze of iOS 27 clear glass at the slider position [tintAmount]:
  /// none up to the middle tick, then a cover that is whole at `1`.
  factory LiquidGlassHaze.ios27Clear({double tintAmount = 0}) {
    final amount = tintAmount.clamp(0.0, 1.0);
    return amount > 0.5
        ? LiquidGlassHaze(cover: 2 * (amount - 0.5))
        : const LiquidGlassHaze.none();
  }

  /// Restores a haze produced by [toJson].
  @experimental
  factory LiquidGlassHaze.fromJson(Map<String, Object?> json) {
    double number(String key, double fallback) =>
        (json[key] as num?)?.toDouble() ?? fallback;
    return LiquidGlassHaze(
      sigma: number('sigma', ios27Sigma),
      lighten: number('lighten', 0),
      darken: number('darken', 0),
      cover: number('cover', 0),
    );
  }

  /// The width of the wide blur on iOS 27, as the sigma of a Gaussian in
  /// logical pixels: what its blur of radius 8 over a pyramid of smaller
  /// copies comes to on the screen.
  static const double ios27Sigma = 15.5;

  /// The sigma of the wide blur, in logical pixels.
  final double sigma;

  /// How far each channel moves to the wide blur where the blur is lighter.
  final double lighten;

  /// How far each channel moves to the wide blur where the blur is darker.
  final double darken;

  /// How much of the backdrop the wide blur replaces after [lighten] and
  /// [darken] mix.
  final double cover;

  /// Whether the haze changes nothing.
  bool get isNone => sigma <= 0 || (lighten <= 0 && darken <= 0 && cover <= 0);

  /// Serializes the haze for example presets and tooling.
  @experimental
  Map<String, Object> toJson() => {
    'sigma': sigma,
    'lighten': lighten,
    'darken': darken,
    'cover': cover,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiquidGlassHaze &&
          other.sigma == sigma &&
          other.lighten == lighten &&
          other.darken == darken &&
          other.cover == cover;

  @override
  int get hashCode => Object.hash(sigma, lighten, darken, cover);

  @override
  String toString() => 'LiquidGlassHaze($sigma, $lighten, $darken, $cover)';
}

import 'dart:ui' show Brightness;

import 'package:liquid_glass_renderer/src/painting/ios27_measures.dart';
import 'package:meta/meta.dart';

// How far iOS 27 regular glass moves the backdrop to its haze at slider
// position 0.
const double _ios27HazeMix = 0.675;

// The width of the wide blur on iOS 27, as the sigma of a Gaussian in
// logical pixels: what its blur of radius 8 over a pyramid of smaller
// copies comes to on the screen.
const double _ios27HazeSigma = 8 * ios27BlurUnit;

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
/// display values: every channel moves to the wide blur by
/// [LiquidGlassFixedHaze.lighten] where the blur is lighter and by
/// [LiquidGlassFixedHaze.darken] where it is darker, and the wide blur then
/// covers the result by [LiquidGlassFixedHaze.cover].
///
/// A haze is either a mix the caller names (the unnamed constructor), drawn
/// as given, or the one of iOS 27 glass ([LiquidGlassHaze.ios27Regular],
/// [LiquidGlassHaze.ios27Clear]), which follows the
/// `LiquidGlassSettings.sliderPosition` of the settings that hold it.
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
/// same frame. Where it reads the backdrop (turned or skewed glass,
/// glass over a platform view, the web, a device without shader filters)
/// and where it is drawn flat, one blur stands in for both: the
/// `LiquidGlassSettings.frost`.
@immutable
sealed class LiquidGlassHaze {
  /// A haze of a blur [sigma] logical pixels wide, mixed in by [lighten],
  /// [darken] and [cover], each from `0` to `1`, at every slider position.
  ///
  /// [sigma] defaults to the width of the wide blur on iOS 27, 15.52 logical
  /// pixels. With the defaults it mixes nothing in, as
  /// [LiquidGlassHaze.none].
  const factory LiquidGlassHaze({
    double sigma,
    double lighten,
    double darken,
    double cover,
  }) = LiquidGlassFixedHaze._;

  /// No haze: the glass shows the backdrop under its frost alone.
  const factory LiquidGlassHaze.none() = LiquidGlassFixedHaze._;

  /// The haze of iOS 27 regular glass in [brightness].
  ///
  /// Light glass lightens and dark glass darkens, by 0.675 at slider
  /// position `0` rising to 0.9 at the middle tick, and the slider covers
  /// the backdrop by its own position.
  const factory LiquidGlassHaze.ios27Regular({
    required Brightness brightness,
  }) = LiquidGlassIos27RegularHaze._;

  /// The haze of iOS 27 clear glass: none up to the slider's middle tick,
  /// then a cover that is whole at `1`.
  const factory LiquidGlassHaze.ios27Clear() = LiquidGlassIos27ClearHaze._;

  const LiquidGlassHaze._();
}

/// A [LiquidGlassHaze] of one mix, drawn as given at every slider position.
final class LiquidGlassFixedHaze extends LiquidGlassHaze {
  const LiquidGlassFixedHaze._({
    this.sigma = _ios27HazeSigma,
    this.lighten = 0,
    this.darken = 0,
    this.cover = 0,
  }) : super._();

  /// The sigma of the wide blur, in logical pixels.
  final double sigma;

  /// How far each channel moves to the wide blur where the blur is lighter.
  final double lighten;

  /// How far each channel moves to the wide blur where the blur is darker.
  final double darken;

  /// How much of the backdrop the wide blur replaces after [lighten] and
  /// [darken] mix.
  final double cover;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiquidGlassFixedHaze &&
          other.sigma == sigma &&
          other.lighten == lighten &&
          other.darken == darken &&
          other.cover == cover;

  @override
  int get hashCode => Object.hash(sigma, lighten, darken, cover);

  @override
  String toString() =>
      'LiquidGlassHaze(sigma: $sigma, lighten: $lighten, darken: $darken, '
      'cover: $cover)';
}

/// The [LiquidGlassHaze] of iOS 27 regular glass
/// ([LiquidGlassHaze.ios27Regular]).
final class LiquidGlassIos27RegularHaze extends LiquidGlassHaze {
  const LiquidGlassIos27RegularHaze._({required this.brightness}) : super._();

  /// Whether the glass is light, and lightens, or dark, and darkens.
  final Brightness brightness;

  @override
  bool operator ==(Object other) =>
      other is LiquidGlassIos27RegularHaze && other.brightness == brightness;

  @override
  int get hashCode => Object.hash(LiquidGlassIos27RegularHaze, brightness);

  @override
  String toString() => 'LiquidGlassHaze.ios27Regular(brightness: $brightness)';
}

/// The [LiquidGlassHaze] of iOS 27 clear glass
/// ([LiquidGlassHaze.ios27Clear]).
final class LiquidGlassIos27ClearHaze extends LiquidGlassHaze {
  const LiquidGlassIos27ClearHaze._() : super._();

  @override
  bool operator ==(Object other) => other is LiquidGlassIos27ClearHaze;

  @override
  int get hashCode => (LiquidGlassIos27ClearHaze).hashCode;

  @override
  String toString() => 'LiquidGlassHaze.ios27Clear()';
}

/// What [haze] mixes in at the Liquid Glass slider position
/// [sliderPosition], or null where it changes nothing.
@internal
LiquidGlassFixedHaze? drawnHazeOf(LiquidGlassHaze haze, double sliderPosition) {
  final amount = sliderPosition.clamp(0.0, 1.0);
  final drawn = switch (haze) {
    final LiquidGlassFixedHaze fixed => fixed,
    LiquidGlassIos27RegularHaze(:final brightness) => () {
      final mix = _ios27HazeMix + 0.45 * splitAtMiddleTick(amount).upTo;
      final dark = brightness == Brightness.dark;
      return LiquidGlassFixedHaze._(
        lighten: dark ? 0 : mix,
        darken: dark ? mix : 0,
        cover: amount,
      );
    }(),
    LiquidGlassIos27ClearHaze() => LiquidGlassFixedHaze._(
      cover: splitAtMiddleTick(amount).past / (1 - sliderMiddleTick),
    ),
  };
  final draws =
      drawn.sigma > 0 &&
      (drawn.lighten > 0 || drawn.darken > 0 || drawn.cover > 0);
  return draws ? drawn : null;
}

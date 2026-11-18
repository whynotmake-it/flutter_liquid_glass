import 'package:meta/meta.dart';

/// How far glass blurs the backdrop it shows through.
///
/// A frost is either a blur the caller names ([LiquidGlassFrost.sigma]),
/// drawn as given, or one fitted to iOS 27 glass
/// ([LiquidGlassFrost.ios27Regular], [LiquidGlassFrost.ios27Clear]), which
/// follows the `LiquidGlassSettings.sliderPosition` of the settings that
/// hold it, the size of the glass and the display.
@immutable
sealed class LiquidGlassFrost {
  const LiquidGlassFrost._();

  /// A blur of [sigma], an approximate Gaussian-equivalent sigma in logical
  /// pixels, drawn as given at every size and slider position. `0` leaves
  /// the backdrop sharp; a negative sigma draws as `0`.
  const factory LiquidGlassFrost.sigma(double sigma) = LiquidGlassFixedFrost._;

  /// The frost of iOS 27 regular glass (`Glass.regular`, and the `.glass`
  /// buttons and toolbars built from it).
  ///
  /// Apple keeps part of the backdrop with about 1.5 pt of blur and mixes
  /// the rest toward a fully diffused face; the Liquid Glass slider only
  /// moves that mix. Where the glass draws its `LiquidGlassSettings.haze`
  /// this frost is the little blur iOS leaves the backdrop itself: none up
  /// to 64 points on the glass's short side, where controls and bars show
  /// the page sharp, growing linearly to 6.6 logical pixels at 160 points.
  ///
  /// Where it draws no haze one blur stands in for both, and a single blur
  /// cannot mix: it is the blur whose rendered detail best matches Apple's
  /// at toolbar size (94 pt), light and dark, 4.5, 6.9 and 18.7 logical
  /// pixels at slider positions 0, 0.5 and 1, growing faster beyond the
  /// Settings middle tick. Apple diffuses larger glass more and smaller
  /// glass less, so it grows with the glass's short side by at most 1.78
  /// times, and it is then raised so Impeller downsamples the blur pass on
  /// the display, at most to what a 2x display needs.
  ///
  /// Near, not identical: under a haze iOS blurs the middle of the glass by
  /// 7.8 logical pixels at 160 points and its rim by half of that; the
  /// renderer blurs all of it by one sigma between the two.
  const factory LiquidGlassFrost.ios27Regular() =
      LiquidGlassIos27RegularFrost._;

  /// The frost of iOS 27 `Glass.clear`.
  ///
  /// Clear glass has no wash or tint at any slider position; the slider only
  /// blurs. Apple's blur grows exponentially at one rate up to the Settings
  /// middle tick and at twice that rate beyond it: 0.35, 1.28 and 16.4 pt
  /// at 0, 0.5 and 1. The renderer draws none at slider position 0, where
  /// the glass is completely clear. Where one blur stands in for the haze,
  /// tinted positions floor it at `2.1` logical pixels; where the glass
  /// draws its haze, which clear glass has none of up to the middle tick, it
  /// blurs by up to 1.2 logical pixels with the slider.
  const factory LiquidGlassFrost.ios27Clear() = LiquidGlassIos27ClearFrost._;
}

/// A [LiquidGlassFrost] of one blur, drawn as given
/// ([LiquidGlassFrost.sigma]).
final class LiquidGlassFixedFrost extends LiquidGlassFrost {
  const LiquidGlassFixedFrost._(this.sigma) : super._();

  /// The blur, as an approximate Gaussian-equivalent sigma in logical
  /// pixels.
  final double sigma;

  @override
  bool operator ==(Object other) =>
      other is LiquidGlassFixedFrost && other.sigma == sigma;

  @override
  int get hashCode => sigma.hashCode;

  @override
  String toString() => 'LiquidGlassFrost.sigma($sigma)';
}

/// The [LiquidGlassFrost] of iOS 27 regular glass
/// ([LiquidGlassFrost.ios27Regular]).
final class LiquidGlassIos27RegularFrost extends LiquidGlassFrost {
  const LiquidGlassIos27RegularFrost._() : super._();

  @override
  bool operator ==(Object other) => other is LiquidGlassIos27RegularFrost;

  @override
  int get hashCode => (LiquidGlassIos27RegularFrost).hashCode;

  @override
  String toString() => 'LiquidGlassFrost.ios27Regular()';
}

/// The [LiquidGlassFrost] of iOS 27 clear glass
/// ([LiquidGlassFrost.ios27Clear]).
final class LiquidGlassIos27ClearFrost extends LiquidGlassFrost {
  const LiquidGlassIos27ClearFrost._() : super._();

  @override
  bool operator ==(Object other) => other is LiquidGlassIos27ClearFrost;

  @override
  int get hashCode => (LiquidGlassIos27ClearFrost).hashCode;

  @override
  String toString() => 'LiquidGlassFrost.ios27Clear()';
}

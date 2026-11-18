import 'dart:math' as math;

import 'package:apple_liquid_glass/src/foundation/glass.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// The glow a finger raises on a pressed glass surface, in one frame.
///
/// UIKit lights a pressed glass surface with two glows of its flex
/// interaction, both color matrices over what lies behind them rather than
/// paint of their own: a wash across the whole surface that adds [wash] to
/// every color channel, and a soft spot under the finger, most at [center]
/// and fading as a Gaussian of standard deviation [radius]. Both stay
/// inside the surface's shape and under its content, and clamp at white.
/// How much the spot brightens is the glass's own: a renderer reads it from
/// the surface's glass with [gainOn]. The liquid renderer draws the glow on
/// the surface's glass, real or fake; the flat renderer, and the liquid one
/// wherever it draws a surface flat (Reduce Transparency, a track, an
/// outlined body in a group or without a field), draws none.
///
/// UIKit: the flex interaction's big and little glows. SwiftUI:
/// `.glassEffect(.regular.interactive())`.
@immutable
class GlassTouchGlow {
  /// Creates a glow description.
  const GlassTouchGlow({
    required this.wash,
    required this.center,
    required this.radius,
    required this.spot,
  });

  /// How much every color channel rises across the whole surface, in
  /// `[0, 1]` units.
  final double wash;

  /// The center of the spot, in the body's own coordinates.
  final Offset center;

  /// The standard deviation of the spot's falloff, in pixels.
  final double radius;

  /// How strongly the spot lights its center, as a share of the glass's
  /// own spot gain.
  final double spot;

  /// How much the spot brightens its center on [glass] in [brightness]:
  /// there the channels are multiplied by `1 + gainOn(glass, brightness)`.
  double gainOn(Glass glass, Brightness brightness) =>
      spot *
      TouchGlowGain.spotGainFor(
        brightness,
        tint: glass.tint,
        clear: glass.isClear,
      );

  /// The same glow with its [center] moved by [offset].
  GlassTouchGlow shift(Offset offset) => GlassTouchGlow(
    wash: wash,
    center: center + offset,
    radius: radius,
    spot: spot,
  );

  @override
  bool operator ==(Object other) =>
      other is GlassTouchGlow &&
      other.wash == wash &&
      other.center == center &&
      other.radius == radius &&
      other.spot == spot;

  @override
  int get hashCode => Object.hash(wash, center, radius, spot);
}

/// How much a touch glow's spot brightens each glass, read from UIKit's
/// glow white levels.
@internal
abstract final class TouchGlowGain {
  /// The gain of the spot's color matrix over a gray backdrop, less one:
  /// 3 in the dark appearance, 0.667 in the light one. They are the
  /// color-dodge gains `1 / (1 - white) - 1` of UIKit's glow white levels
  /// 0.75 (dark) and 0.4 (light) (read from UIKit, notes private).
  static double spotGain(Brightness brightness) => switch (brightness) {
    Brightness.dark => 3,
    Brightness.light => 0.667,
  };

  /// The glow white level of clear glass in both appearances (read from
  /// UIKit, notes private).
  static const double clearGlassWhite = 0.7;

  /// The glow white level of tinted glass over the tint's luminance:
  /// UIKit lerps from [tintWhiteFrom] to [tintWhiteTo] by luminance to the
  /// power [tintLuminanceExponent] (read from UIKit, notes private).
  static const double tintWhiteFrom = 0.7;

  /// See [tintWhiteFrom].
  static const double tintWhiteTo = 0.25;

  /// See [tintWhiteFrom].
  static const double tintLuminanceExponent = 1.25;

  /// The gain less one of a spot with color-dodge white level [white].
  static double spotGainOfWhite(double white) => 1 / (1 - white) - 1;

  /// The spot's gain less one for a glass surface: tinted glass by its
  /// [tint]'s luminance (UIKit's Rec. 709 weights of the gamma-encoded
  /// channels, times alpha), clear glass by [clearGlassWhite], regular
  /// glass by [spotGain]. Tinted and clear values are read from UIKit, not
  /// measured on a device.
  static double spotGainFor(
    Brightness brightness, {
    Color? tint,
    bool clear = false,
  }) {
    if (tint != null) {
      final luminance =
          (0.2126 * tint.r + 0.7152 * tint.g + 0.0722 * tint.b) * tint.a;
      final t = math.pow(luminance.clamp(0.0, 1.0), tintLuminanceExponent);
      return spotGainOfWhite(tintWhiteFrom + (tintWhiteTo - tintWhiteFrom) * t);
    }
    if (clear) return spotGainOfWhite(clearGlassWhite);
    return spotGain(brightness);
  }
}

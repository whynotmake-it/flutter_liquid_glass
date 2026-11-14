import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// The shadow iOS 27 casts under regular glass, which widens and deepens
/// with the glass's shorter side.
///
/// Glass up to 64 points on its shorter side casts a faint contact shadow:
/// black at 1.2 % under a blur of 4 points. From 160 points it casts the full
/// one: black at 12 % in light mode and 18 % in dark mode under a blur of 24
/// points. Between the two every part grows linearly. All of them fall 8
/// points below the glass. Clear glass casts no shadow on iOS.
///
/// The numbers are read from UIKit on iOS 27 and agree with captures of
/// native glass over white within half a level out of 255.
///
/// Near, not identical: iOS shades by the distance to the outline, Flutter
/// blurs the shape. The two agree along straight edges and differ by a
/// fraction of a level around a corner.
///
/// Among the shadows of a glass shape the renderer casts [at] the shape's
/// size in its place. Read as a plain [BoxShadow] it is the shadow of the
/// largest glass, so room reserved by its fields is always enough.
@immutable
final class LiquidGlassShadow extends BoxShadow {
  /// The shadow of regular glass in [brightness].
  const LiquidGlassShadow.ios27({this.brightness = Brightness.light})
    : super(
        color: brightness == Brightness.dark
            ? const Color.from(alpha: _alpha * 0.6, red: 0, green: 0, blue: 0)
            : const Color.from(alpha: _alpha * 0.4, red: 0, green: 0, blue: 0),
        offset: _offset,
        blurRadius: (24 / math.sqrt2 - 0.5) / 0.57735,
      );

  /// The colour scheme of the glass, which sets how dark its shadow gets.
  final Brightness brightness;

  static const _offset = Offset(0, 8);

  // The shadow's own colour is black at 30 %; the opacity that grows with
  // the size multiplies it.
  static const _alpha = 0.3;

  /// The shadow of a shape of [size].
  BoxShadow at(Size size) {
    final grown = ((size.shortestSide - 64) / 96).clamp(0.0, 1.0);
    final opacity =
        0.04 + (brightness == Brightness.dark ? 0.56 : 0.36) * grown;
    // iOS fades the shadow as erfc(distance / radius), a Gaussian edge whose
    // sigma is the radius over sqrt 2; Flutter derives sigma from blurRadius
    // as 0.57735 r + 0.5.
    final sigma = (4 + 20 * grown) / math.sqrt2;
    return BoxShadow(
      color: Color.from(alpha: _alpha * opacity, red: 0, green: 0, blue: 0),
      offset: _offset,
      blurRadius: (sigma - 0.5) / 0.57735,
    );
  }

  /// [shadows] as a shape of [size] casts them: every [LiquidGlassShadow]
  /// among them replaced by its shadow [at] that size.
  ///
  /// Returns [shadows] itself when it holds none.
  static List<BoxShadow> resolve(List<BoxShadow> shadows, Size size) {
    if (!shadows.any((shadow) => shadow is LiquidGlassShadow)) return shadows;
    return [
      for (final shadow in shadows)
        if (shadow is LiquidGlassShadow) shadow.at(size) else shadow,
    ];
  }
}

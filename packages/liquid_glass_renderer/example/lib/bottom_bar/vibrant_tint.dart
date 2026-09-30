import 'dart:ui';

import 'package:flutter/foundation.dart';

/// How tinted glyphs on glass composite with the glass behind them, pixel by
/// pixel: the glyphs are painted twice, first with [VibrantTint.multiply]
/// and then with [VibrantTint.screen] on top, so each channel ends up as
///
/// `screen + (1 - screen) * multiply * glass`,
///
/// the tint plus a share of the glass tone. Both paints draw straight into
/// the glass's content, so this needs no extra layer or pass, and the tint
/// follows the backdrop instantly and shows its detail.
///
/// Fitted to the selected item of the iOS 27 system tab bar
/// (`internal/bottom-bar-match/apple-measurements.md` in the project store),
/// whose tint follows the glass beneath it while keeping its hue:
///
/// * In the light appearance it darkens with the glass, from (0, 130, 248)
///   over the light platter on white to (0, 93, 199) over the platter on
///   black, about `tint * (0.67 + 0.37 * glass)` per channel.
/// * In the dark appearance it lightens toward cyan over lighter glass: the
///   glass screens into the tint's unsaturated channels.
///
/// Either way it stays less saturated than a hard light blend, which turned
/// it deep blue over mid-tone glass. Over dark content Apple's tint reads
/// lighter because the whole bar flips to its dark appearance there; the
/// example gets that from the bar's adaptive brightness, not from the blend.
@immutable
class VibrantTint {
  const VibrantTint({required this.multiply, required this.screen});

  /// The tint's paints for glass of [brightness].
  factory VibrantTint.of(Color tint, Brightness brightness) {
    if (brightness == Brightness.dark) {
      return VibrantTint(
        multiply: const Color(0xFFFFFFFF).withValues(alpha: tint.a),
        screen: tint,
      );
    }
    double base(double channel) => channel * _lightBase;
    double share(double channel) =>
        (channel * _lightShare / (1 - base(channel))).clamp(0.0, 1.0);
    return VibrantTint(
      multiply: Color.from(
        alpha: tint.a,
        red: share(tint.r),
        green: share(tint.g),
        blue: share(tint.b),
      ),
      screen: Color.from(
        alpha: tint.a,
        red: base(tint.r),
        green: base(tint.g),
        blue: base(tint.b),
      ),
    );
  }

  /// Fraction of the tint a light glyph keeps over black glass.
  static const _lightBase = .67;

  /// Fraction of the tint a light glyph gains from white glass.
  static const _lightShare = .37;

  /// Painted first with [BlendMode.multiply].
  final Color multiply;

  /// Painted over [multiply] with [BlendMode.screen].
  final Color screen;

  /// The glyph paints, in order.
  List<Paint> get paints => [
    Paint()
      ..color = multiply
      ..blendMode = BlendMode.multiply,
    Paint()
      ..color = screen
      ..blendMode = BlendMode.screen,
  ];

  @override
  bool operator ==(Object other) =>
      other is VibrantTint &&
      other.multiply == multiply &&
      other.screen == screen;

  @override
  int get hashCode => Object.hash(multiply, screen);
}

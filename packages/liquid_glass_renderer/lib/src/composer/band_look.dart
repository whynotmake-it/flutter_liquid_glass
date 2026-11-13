import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:meta/meta.dart';

/// How a scroll edge looks where it lies this frame, which glass over it
/// draws in its own filter.
@immutable
final class BandLook {
  /// Creates the look.
  const BandLook({
    required this.sigma,
    required this.paint,
    required this.origin,
    required this.shown,
    required this.devicePixelRatio,
  });

  /// Its frost, in logical pixels.
  final double sigma;

  /// What it paints over its frost.
  final FrostBandPaint paint;

  /// Where its layer's coordinates begin on the screen.
  final Offset origin;

  /// What it covers on the screen.
  final Rect shown;

  /// The device pixels of its view per logical pixel.
  final double devicePixelRatio;

  @override
  bool operator ==(Object other) =>
      other is BandLook &&
      other.sigma == sigma &&
      other.paint == paint &&
      other.origin == origin &&
      other.shown == shown &&
      other.devicePixelRatio == devicePixelRatio;

  @override
  int get hashCode =>
      Object.hash(sigma, paint, origin, shown, devicePixelRatio);
}

/// What a scroll edge paints over its frost, in its layer's coordinates, and
/// how its frost changes the color.
@immutable
final class FrostBandPaint {
  /// Creates the paint.
  const FrostBandPaint({
    required this.fade,
    required this.whole,
    required this.gone,
    required this.lineStart,
    required this.lineEnd,
    required this.lineGray,
    required this.presence,
    required this.saturation,
    required this.brightness,
  });

  @override
  bool operator ==(Object other) =>
      other is FrostBandPaint &&
      other.fade == fade &&
      other.whole == whole &&
      other.gone == gone &&
      other.lineStart == lineStart &&
      other.lineEnd == lineEnd &&
      other.lineGray == lineGray &&
      other.presence == presence &&
      other.saturation == saturation &&
      other.brightness == brightness;

  @override
  int get hashCode => Object.hash(
    fade,
    whole,
    gone,
    lineStart,
    lineEnd,
    lineGray,
    presence,
    saturation,
    brightness,
  );

  /// The fade, straight.
  final Color fade;

  /// The row where the fade is whole.
  final double whole;

  /// The row where the fade is gone.
  final double gone;

  /// Where the hairline starts.
  final double lineStart;

  /// Where the hairline ends.
  final double lineEnd;

  /// The hairline's gray.
  final double lineGray;

  /// How much of the band shows.
  final double presence;

  /// The saturation of what lies under the band.
  final double saturation;

  /// The brightness added.
  final double brightness;
}

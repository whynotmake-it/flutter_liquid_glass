import 'dart:math';

import 'package:meta/meta.dart';

/// What Impeller's Gaussian blur does to a sigma.
@internal
abstract final class ImpellerBlur {
  /// The device sigma from which Impeller blurs at half resolution: its
  /// share ([share]) is 2 from here.
  static const double halfResolutionSigma = 4 * sqrt2;

  /// The fraction of the sigma asked that Impeller's blur delivers, which the
  /// shader's frost matches: the best of 0.70 to 1.0 against
  /// ImageFilter.blur at 3, 5 and 8 device px, where Impeller's blur passes
  /// deliver 0.84 to 0.87 of the sigma.
  static const double deliveredFraction = 0.84;

  // Impeller downsamples by at most 2^4.
  static const int _mostShareLog2 = 4;

  /// How many device pixels along each side one pixel holds where Impeller's
  /// blur by [sigma] device pixels downsamples (GaussianBlurFilterContents::
  /// CalculateScale: none up to 4, else 2^round(log2(sigma / 4)), at most
  /// 16). Exact up to 8: past it Impeller widens the step of 8 by its
  /// kernel.
  static int share(double sigma) => sigma <= 4
      ? 1
      : 1 << (log(sigma / 4) / ln2).round().clamp(0, _mostShareLog2);

  /// The device-pixel sigma Impeller blurs with for [sigma] logical pixels
  /// at [devicePixelRatio]: its sigma correction, then the canvas scale.
  static double deviceSigma(double sigma, double devicePixelRatio) {
    final clamped = min<double>(sigma, 500);
    return clamped * _correction(clamped) * devicePixelRatio;
  }

  static double _correction(double sigma) =>
      1 - 3.4e-3 * sigma + 3.4e-6 * sigma * sigma;

  /// The logical pixels around a region that Impeller's blur of [sigma]
  /// logical pixels reads at [devicePixelRatio], drawn on a canvas that
  /// stretches it by [stretch]: its kernel reaches 1.732 of its device sigma
  /// (kKernelRadiusPerSigma), plus the texels its downsample and upsample
  /// add, rounded up to whole device pixels.
  static double reach(
    double sigma,
    double devicePixelRatio, {
    double stretch = 1,
  }) {
    final drawnSigma = deviceSigma(sigma, devicePixelRatio * stretch);
    return (1.7320508 * drawnSigma + 2 * share(drawnSigma) + 2).ceilToDouble() /
        devicePixelRatio;
  }

  /// [sigma] raised to the smallest sigma Impeller blurs at half resolution
  /// at [devicePixelRatio] ([halfResolutionSigma]), when that is at most
  /// 1.12 times larger; else [sigma] itself. Just below that threshold
  /// Impeller blurs every device pixel at about three times the cost on a
  /// Mali GPU. NEAR: the blur is up to 12 % wider than asked.
  static double halfResolution(double sigma, double devicePixelRatio) {
    if (sigma <= 0 || devicePixelRatio <= 0) return sigma;
    if (deviceSigma(sigma, devicePixelRatio) >= halfResolutionSigma) {
      return sigma;
    }
    final target = halfResolutionSigma * 1.001 / devicePixelRatio;
    var raised = target;
    for (var i = 0; i < 4; i++) {
      raised = target / _correction(raised);
    }
    return raised <= sigma * 1.12 ? raised : sigma;
  }
}

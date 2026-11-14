import 'dart:math' as math;
import 'dart:ui';

import 'package:liquid_glass_renderer/composer.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/rendering/drawn_values.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_blur.dart';
import 'package:meta/meta.dart';

/// Saturation and a midtone secant of transmissionGamma as Flutter's 4x5
/// color matrix, a native color filter on Impeller and Skia.
@internal
List<double> fakeGlassColorMatrix({
  required double saturation,
  double transmissionGamma = 1,
  double opacity = 1,
}) {
  // Match the final shader's fitted Rec.709 saturation basis.
  const luminanceRed = 0.2126;
  const luminanceGreen = 0.7152;
  const luminanceBlue = 0.0722;
  final inverseSaturation = 1 - saturation;
  final saturationRows = <(double, double, double)>[
    (
      luminanceRed * inverseSaturation + saturation,
      luminanceGreen * inverseSaturation,
      luminanceBlue * inverseSaturation,
    ),
    (
      luminanceRed * inverseSaturation,
      luminanceGreen * inverseSaturation + saturation,
      luminanceBlue * inverseSaturation,
    ),
    (
      luminanceRed * inverseSaturation,
      luminanceGreen * inverseSaturation,
      luminanceBlue * inverseSaturation + saturation,
    ),
  ];
  // A color matrix cannot apply pow() per channel; a secant through 0.25 and
  // 0.75 approximates transmissionGamma at midtones without another pass or
  // backdrop sample.
  final gamma = math.max(transmissionGamma, 0.01);
  const lowerInput = 0.25;
  const upperInput = 0.75;
  final lowerOutput = math.pow(lowerInput, gamma).toDouble();
  final upperOutput = math.pow(upperInput, gamma).toDouble();
  final gammaScale = (upperOutput - lowerOutput) / (upperInput - lowerInput);
  final gammaBias = lowerOutput - gammaScale * lowerInput;

  final filterOpacity = opacity.clamp(0.0, 1.0);
  final result = <double>[];
  for (final row in saturationRows) {
    result
      ..add(row.$1 * gammaScale)
      ..add(row.$2 * gammaScale)
      ..add(row.$3 * gammaScale)
      ..add(0)
      // ColorFilter.matrix biases use the 0-255 channel scale.
      ..add(gammaBias * 255);
  }
  return result..addAll([0, 0, 0, filterOpacity, 0]);
}

// Least-squares line `slope * Y + offset` through [transfer] over `[0, 1]`,
// sampled at 17 points.
(double slope, double offset) _line(double Function(double y) transfer) {
  const samples = 17;
  var meanY = 0.0;
  var meanT = 0.0;
  for (var i = 0; i < samples; i++) {
    final y = i / (samples - 1);
    meanY += y / samples;
    meanT += transfer(y) / samples;
  }
  var covariance = 0.0;
  var variance = 0.0;
  for (var i = 0; i < samples; i++) {
    final y = i / (samples - 1);
    covariance += (y - meanY) * (transfer(y) - meanT);
    variance += (y - meanY) * (y - meanY);
  }
  final slope = covariance / variance;
  return (slope, meanT - slope * meanY);
}

/// The complete untinted iOS 27 face (see `GlassColorParameters`) as a 4x5
/// color matrix.
///
/// Evaluating the whole face in the filter clamps only the final color, so
/// amplified chroma is not clipped before the neutral wash attenuates it.
/// A matrix is linear in the backdrop, so the face of a grey backdrop,
/// lift and [bleed] included, is replaced by its least-squares line, and
/// the chroma takes the mean of its gain over the backdrop's luminance.
@internal
List<double> fakeGlassFaceMatrix({
  required Color emission,
  required double transmittance,
  required double lift,
  required double chromaGain,
  GlassColorBleed bleed = const GlassColorBleed.none(),
  double transmissionGamma = 1,
  double opacity = 1,
}) {
  const luminance = [0.2126, 0.7152, 0.0722];
  final emissionColor = [emission.r, emission.g, emission.b];
  final glow =
      luminance[0] * emission.r +
      luminance[1] * emission.g +
      luminance[2] * emission.b;
  final gamma = math.max(transmissionGamma, 0.01);
  double bare(double y) =>
      glow +
      transmittance * math.pow((y + lift * y * (1 - y)).clamp(0.0, 1.0), gamma);
  final (slope, offset) = _line((y) => bleed.apply(bare(y), y));
  const samples = 17;
  var chroma = 0.0;
  for (var i = 0; i < samples; i++) {
    final y = i / (samples - 1);
    final keep = 1 - y * lift / (1 + lift);
    final share = bleed.share(bare(y));
    chroma +=
        ((1 - share) * chromaGain * keep * (1.3 - 0.3 * keep) +
            share * bleed.saturation) /
        samples;
  }
  final result = <double>[];
  for (var row = 0; row < 3; row++) {
    for (var column = 0; column < 3; column++) {
      result.add(
        luminance[column] * (slope - chroma) + (row == column ? chroma : 0),
      );
    }
    result
      ..add(0)
      // ColorFilter.matrix biases use the 0-255 channel scale.
      ..add((emissionColor[row] - glow + offset) * 255);
  }
  return result..addAll([0, 0, 0, opacity.clamp(0.0, 1.0), 0]);
}

/// A fake glass backdrop filter, its blur-free variant for a pass that has
/// already blurred its backdrop, the blur's logical sigma, and the frost
/// `full` stands for when it blurs.
@internal
typedef FakeGlassFilterParts = ({
  ImageFilter full,
  double sigma,
  LiquidGlassBackdropFrost? frost,
});

/// The backdrop filter of fake glass, standalone or consolidated, with the
/// blur's logical sigma and its frost. Tint stays in the analytic surface
/// pass, so contour transmittance treats tint and backdrop energy apart.
@internal
FakeGlassFilterParts? fakeGlassBackdropFilterParts(
  LiquidGlassSettings settings,
  LiquidGlassAppearance appearance, {
  double deviceScale = 1,
  double? shapeShortSide,
}) {
  final visibility = appearance.visibility.clamp(0.0, 1.0);
  if (visibility <= 0) return null;
  final colorModel = appearance.colorModel;
  final sigma = settings.frostSigmaAt(
    deviceScale,
    shapeShortSide: shapeShortSide,
  );
  final blurs = sigma != 0;
  final faceTransfer = colorModel.parameters?.faceTransfer(
    tintAmount: settings.effectiveTintAmount,
  );
  final List<double>? matrix;
  if (faceTransfer != null) {
    matrix = fakeGlassFaceMatrix(
      emission: faceTransfer.emission,
      transmittance: faceTransfer.transmittance,
      lift: faceTransfer.lift,
      chromaGain: faceTransfer.chromaGain * colorModel.saturation,
      bleed: colorModel.parameters!.bleed,
      transmissionGamma: colorModel.transmissionGamma,
      opacity: visibility,
    );
  } else {
    final hasMaterialColorTransfer =
        colorModel.saturation != 1 || colorModel.transmissionGamma != 1;
    final hasColorTransfer =
        hasMaterialColorTransfer || (blurs && visibility < 1);
    matrix = hasColorTransfer
        ? fakeGlassColorMatrix(
            saturation: colorModel.saturation,
            transmissionGamma: colorModel.transmissionGamma,
            // A partially transparent filtered backdrop composites over the
            // untouched backdrop, matching the shaded glass's material fade
            // without another backdrop sample. The opacity alone fades the
            // transfer, like the face matrix above, so it fades linearly.
            opacity: visibility,
          )
        : null;
  }
  final colorTransfer = matrix == null ? null : ColorFilter.matrix(matrix);
  final frost = blurs
      ? LiquidGlassBackdropFrost(
          sigma: sigma,
          colorMatrix: matrix,
          tileMode: glassBlurTileMode,
        )
      : null;
  final full = frost?.filter ?? colorTransfer;
  if (full == null) return null;
  return (
    full: full,
    sigma: sigma,
    frost: frost,
  );
}

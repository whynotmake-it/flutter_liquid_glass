import 'dart:math' as math;
import 'dart:ui';

import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:meta/meta.dart';

/// Affine tint-over-backdrop followed by saturation, expressed as Flutter's
/// 4x5 color matrix: the same per-pixel result as a shader, but a native color
/// filter on both Impeller and Skia.
@internal
List<double> fakeGlassColorMatrix({
  required double saturation,
  required Color tint,
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
  final backdropWeight = 1 - tint.a;
  // A color matrix cannot reproduce the real renderer's per-channel pow(),
  // but a secant through the useful midtone range is a free approximation in
  // the native filter we already need for tint/saturation. It preserves the
  // characteristic lift from the toolbar preset's sub-unity gamma without
  // adding another shader pass or backdrop sample.
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
      ..add(row.$1 * backdropWeight * gammaScale)
      ..add(row.$2 * backdropWeight * gammaScale)
      ..add(row.$3 * backdropWeight * gammaScale)
      ..add(0)
      // ColorFilter.matrix biases use the 0-255 channel scale.
      ..add(
        (tint.a * (row.$1 * tint.r + row.$2 * tint.g + row.$3 * tint.b) +
                backdropWeight * gammaBias) *
            255,
      );
  }
  return result..addAll([0, 0, 0, filterOpacity, 0]);
}

/// Least-squares line `slope * Y + offset` through the iOS 27 luminance
/// transfer `(Y + lift * Y * (1 - Y)) ^ transmissionGamma` over `[0, 1]`.
/// At unit gamma it is exactly `Y + lift / 6`.
(double slope, double offset) _faceLuminanceLine(
  double lift,
  double transmissionGamma,
) {
  final gamma = math.max(transmissionGamma, 0.01);
  double transfer(double y) =>
      math.pow((y + lift * y * (1 - y)).clamp(0.0, 1.0), gamma).toDouble();
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

/// The complete untinted iOS 27 face as a 4x5 color matrix:
/// `emission + transmittance * lum(Y) + chromaGain * (backdrop - Y)`.
///
/// Evaluating the whole face in the filter clamps only the final color, so
/// amplified chroma is not clipped before the neutral wash attenuates it.
/// The luminance transfer is replaced by its least-squares line.
@internal
List<double> fakeGlassFaceMatrix({
  required Color emission,
  required double transmittance,
  required double lift,
  required double chromaGain,
  double transmissionGamma = 1,
  double opacity = 1,
}) {
  const luminance = [0.2126, 0.7152, 0.0722];
  final (slope, offset) = _faceLuminanceLine(lift, transmissionGamma);
  final emissionColor = [emission.r, emission.g, emission.b];
  final result = <double>[];
  for (var row = 0; row < 3; row++) {
    for (var column = 0; column < 3; column++) {
      result.add(
        luminance[column] * (transmittance * slope - chromaGain) +
            (row == column ? chromaGain : 0),
      );
    }
    result
      ..add(0)
      // ColorFilter.matrix biases use the 0-255 channel scale.
      ..add((emissionColor[row] + transmittance * offset) * 255);
  }
  return result..addAll([0, 0, 0, opacity.clamp(0.0, 1.0), 0]);
}

/// Builds the backdrop-only portion shared by standalone and consolidated
/// fake glass. Tint remains in the analytic surface pass so contour
/// transmittance can treat tint and backdrop energy independently.
@internal
ImageFilter? fakeGlassBackdropFilter(
  LiquidGlassSettings settings,
  LiquidGlassAppearance appearance, {
  double shortSide = 1e4,
}) {
  final visibility = appearance.visibility.clamp(0.0, 1.0);
  if (visibility <= 0) return null;
  final frost = settings.effectiveFrost;
  final blur = frost != 0
      ? ImageFilter.blur(
          sigmaX: frost,
          sigmaY: frost,
          tileMode: TileMode.mirror,
        )
      : null;
  final faceTransfer = appearance.colorModel.faceTransfer(
    shortSide,
    tintAmount: settings.effectiveTintAmount,
  );
  final ColorFilter? colorTransfer;
  if (faceTransfer != null) {
    colorTransfer = ColorFilter.matrix(
      fakeGlassFaceMatrix(
        emission: faceTransfer.emission,
        transmittance: faceTransfer.transmittance,
        lift: faceTransfer.lift,
        chromaGain: faceTransfer.chromaGain * appearance.saturation,
        transmissionGamma: appearance.transmissionGamma,
        opacity: visibility,
      ),
    );
  } else {
    final hasMaterialColorTransfer =
        appearance.saturation != 1 || appearance.transmissionGamma != 1;
    final hasColorTransfer =
        hasMaterialColorTransfer || (blur != null && visibility < 1);
    colorTransfer = hasColorTransfer
        ? ColorFilter.matrix(
            fakeGlassColorMatrix(
              saturation: appearance.saturation,
              tint: const Color(0x00000000),
              transmissionGamma: appearance.transmissionGamma,
              // A partially transparent filtered backdrop composites over the
              // untouched backdrop, matching RealGlass's material fade without
              // another backdrop sample. The opacity alone fades the transfer,
              // like the face matrix above, so it fades linearly.
              opacity: visibility,
            ),
          )
        : null;
  }
  return switch ((blur, colorTransfer)) {
    (final blur?, final colorTransfer?) => ImageFilter.compose(
      inner: blur,
      outer: colorTransfer,
    ),
    (final blur?, null) => blur,
    (null, final colorTransfer?) => colorTransfer,
    (null, null) => null,
  };
}

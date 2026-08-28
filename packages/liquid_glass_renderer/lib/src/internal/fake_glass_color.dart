import 'dart:math' as math;
import 'dart:ui';

import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:meta/meta.dart';

/// Affine tint-over-backdrop followed by saturation, expressed as Flutter's
/// 4x5 color matrix. This is algebraically equivalent to the former runtime
/// shader but remains a native color filter on both Impeller and Skia.
@internal
List<double> fakeGlassColorMatrix({
  required double saturation,
  required Color tint,
  double transmissionGamma = 1,
}) {
  const luminanceRed = 0.299;
  const luminanceGreen = 0.587;
  const luminanceBlue = 0.114;
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
  return result..addAll(const [0, 0, 0, 1, 0]);
}

/// Builds the backdrop-only portion shared by standalone and consolidated
/// fake glass. Tint remains in the analytic surface pass so contour
/// transmittance can treat tint and backdrop energy independently.
@internal
ImageFilter? fakeGlassBackdropFilter(LiquidGlassSettings settings) {
  final blur = settings.effectiveFrost != 0
      ? ImageFilter.blur(
          sigmaX: settings.effectiveFrost,
          sigmaY: settings.effectiveFrost,
          tileMode: TileMode.mirror,
        )
      : null;
  final hasColorTransfer =
      settings.effectiveSaturation != 1 ||
      settings.effectiveTransmissionGamma != 1;
  final colorTransfer = hasColorTransfer
      ? ColorFilter.matrix(
          fakeGlassColorMatrix(
            saturation: settings.effectiveSaturation,
            tint: const Color(0x00000000),
            transmissionGamma: settings.effectiveTransmissionGamma,
          ),
        )
      : null;
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

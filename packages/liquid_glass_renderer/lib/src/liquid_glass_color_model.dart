import 'dart:math' as math;
import 'dart:ui';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Interpolates linearly between the Liquid Glass slider keyframes: Clear
/// (`0`), the Settings middle tick (`0.5`) and Tinted (`1`).
@internal
double sliderKeyframes(
  double tintAmount,
  double clear,
  double middle,
  double tinted,
) {
  final s = tintAmount.clamp(0.0, 1.0);
  return s <= 0.5
      ? clear + (middle - clear) * s * 2
      : middle + (tinted - middle) * (s * 2 - 1);
}

/// Defines how a glass tint is combined with transmitted backdrop content.
///
/// The model owns its transfer functions and renderer encoding. Use
/// [LiquidGlassColorModel.direct] for unrestricted manual color controls or
/// [LiquidGlassColorModel.ios27] or [LiquidGlassColorModel.ios27Clear] for
/// Apple's backdrop-adaptive behavior.
sealed class LiquidGlassColorModel with Equatable {
  const LiquidGlassColorModel();

  /// Applies tint, gamma, saturation, and vibrancy directly.
  const factory LiquidGlassColorModel.direct() = DirectLiquidGlassColorModel;

  /// Derives an iOS 27-style tonal tint response for [brightness].
  const factory LiquidGlassColorModel.ios27({
    required Brightness brightness,
  }) = Ios27LiquidGlassColorModel;

  /// iOS 27 `Glass.clear`, which is identical in light and dark appearance.
  const factory LiquidGlassColorModel.ios27Clear() =
      Ios27ClearLiquidGlassColorModel;

  /// Restores a model identifier emitted by [toJson].
  factory LiquidGlassColorModel.fromJson(Object? value) => switch (value) {
    'ios27Light' => const LiquidGlassColorModel.ios27(
      brightness: Brightness.light,
    ),
    'ios27Dark' => const LiquidGlassColorModel.ios27(
      brightness: Brightness.dark,
    ),
    'ios27Clear' => const LiquidGlassColorModel.ios27Clear(),
    _ => const LiquidGlassColorModel.direct(),
  };

  /// Stable identifier used by appearance preset JSON.
  String toJson();

  /// Compact value consumed by the fragment shader.
  @internal
  double get shaderValue;

  /// The untinted face for a shape whose shorter side is [shortSide] logical
  /// pixels, or `null` when transmitted content is composited per channel.
  ///
  /// The face is `emission + transmittance * lum(Y) + chromaGain *
  /// (backdrop - Y)` with `lum(Y) = Y + lift * Y * (1 - Y)`; `emission` is
  /// premultiplied. Mirrors `ios27NeutralTint` and `ios27FaceTransfer` in the
  /// final shader.
  @internal
  ({Color emission, double transmittance, double lift, double chromaGain})?
  faceTransfer(double shortSide, {double tintAmount = 0});

  /// Factor applied to the border strength at the Liquid Glass slider
  /// position [tintAmount]. Mirrors the dark branch of the final shader.
  @internal
  double contourScale(double shortSide, double tintAmount) => 1;

  /// Luminance of the neutral glint target FakeGlass composites, which
  /// cannot scale with the face it does not sample.
  @internal
  double get fakeGlintLuminance => 1.6;

  /// Maps one opaque tint to the tone selected for backdrop [luminance].
  ///
  /// The direct model returns [tint] unchanged. The iOS 27 model implements
  /// Apple's documented brightness-mapped range of tint tones.
  @visibleForTesting
  Color tintTone(Color tint, double luminance);

  /// Resolves the single-color surface tint painted by FakeGlass.
  ///
  /// FakeGlass cannot inspect backdrop luminance in its analytic surface
  /// shader, so adaptive models evaluate their tonal ramp at a midtone. Their
  /// neutral face is applied by the backdrop color filter instead, so it is
  /// not part of this color.
  @internal
  Color approximateSurfaceTint(Color tint);
}

/// The fully configurable, backdrop-independent color model.
final class DirectLiquidGlassColorModel extends LiquidGlassColorModel {
  /// Creates the direct, backdrop-independent model.
  const DirectLiquidGlassColorModel();

  @override
  String toJson() => 'direct';

  @override
  double get shaderValue => 0;

  @override
  ({Color emission, double transmittance, double lift, double chromaGain})?
  faceTransfer(double shortSide, {double tintAmount = 0}) => null;

  @override
  Color tintTone(Color tint, double luminance) => tint;

  @override
  Color approximateSurfaceTint(Color tint) => tint;

  @override
  List<Object?> get props => const [];
}

/// Apple's luminance-conditioned iOS 27 tint model.
final class Ios27LiquidGlassColorModel extends LiquidGlassColorModel {
  /// Creates the adaptive iOS 27 model for [brightness].
  const Ios27LiquidGlassColorModel({required this.brightness});

  /// Appearance used to select the neutral material and tonal ramp.
  final Brightness brightness;

  @override
  String toJson() => brightness == Brightness.dark ? 'ios27Dark' : 'ios27Light';

  @override
  double get shaderValue => brightness == Brightness.dark ? 2 : 1;

  @override
  ({Color emission, double transmittance, double lift, double chromaGain})
  faceTransfer(double shortSide, {double tintAmount = 0}) {
    if (brightness == Brightness.light) {
      // The Liquid Glass slider makes the near-white wash more opaque and
      // desaturates the transmitted backdrop.
      final alpha = 1 - sliderKeyframes(tintAmount, 0.592, 0.468, 0.286);
      return (
        emission: Color.from(
          alpha: 1,
          red: alpha * 253 / 255,
          green: alpha * 252 / 255,
          blue: alpha * 253 / 255,
        ),
        transmittance: 1 - alpha,
        lift: 0.13,
        chromaGain: sliderKeyframes(tintAmount, 1.17, 0.982, 0.751),
      );
    }
    // Dark glass keeps its emission, becomes denser with size and slider,
    // and compresses its highlights up to the middle tick.
    return (
      emission: const Color.from(
        alpha: 1,
        red: 32 / 255,
        green: 32 / 255,
        blue: 32 / 255,
      ),
      transmittance: _darkTransmittance(shortSide, tintAmount),
      lift: sliderKeyframes(tintAmount, 1, 1.58, 1.13),
      chromaGain: sliderKeyframes(tintAmount, 1.02, 0.955, 0.572),
    );
  }

  @override
  double contourScale(double shortSide, double tintAmount) {
    if (brightness == Brightness.light) return 1;
    final added =
        _darkTransmittance(shortSide, 0) -
        _darkTransmittance(shortSide, tintAmount);
    return 1 + 0.95 * added;
  }

  /// Controls up to 75 pt keep light-mode density until the middle tick;
  /// surfaces from 105 pt are denser from the start. Both roughly halve by
  /// Tinted.
  static double _darkTransmittance(double shortSide, double tintAmount) {
    final t = ((shortSide - 75) / 30).clamp(0.0, 1.0);
    final large = t * t * (3 - 2 * t);
    double blend(double small, double big) => small + (big - small) * large;
    return sliderKeyframes(
      tintAmount,
      blend(0.597, 0.447),
      blend(0.596, 0.346),
      blend(0.295, 0.195),
    );
  }

  @override
  Color tintTone(Color tint, double luminance) {
    final backdropLuminance = luminance.clamp(0.0, 1.0);
    double tone(double channel) => brightness == Brightness.dark
        ? _darkTone(channel, backdropLuminance)
        : _lightTone(channel, backdropLuminance);

    return Color.from(
      alpha: 1,
      red: tone(tint.r).clamp(0.0, 1.0),
      green: tone(tint.g).clamp(0.0, 1.0),
      blue: tone(tint.b).clamp(0.0, 1.0),
    );
  }

  @override
  Color approximateSurfaceTint(Color tint) {
    if (tint.a <= 0) return const Color(0x00000000);
    return tintTone(tint, 0.5).withValues(alpha: tint.a);
  }

  static double _lightTone(double channel, double luminance) =>
      (.76059211 + (1 - .76059211) * math.pow(luminance, .90667748)) *
      math.pow(channel, 1 + .07044432 * (1 - luminance));

  static double _darkTone(double channel, double luminance) {
    final floor =
        .08611765 * math.pow(math.min(1.0, luminance / .62019473), 1.01150514);
    final ceiling =
        1 -
        .01560784 * math.pow(math.min(1.0, luminance / .46837318), 1.85642966);
    return floor + (ceiling - floor) * channel;
  }

  @override
  List<Object?> get props => [brightness];
}

/// iOS 27 `Glass.clear`.
///
/// Measured on the pinned solid palettes, clear glass lifts black to 32/255,
/// transmits 0.954 of the backdrop's luminance, passes chroma through at
/// 1.057 and is identical in light and dark appearance.
final class Ios27ClearLiquidGlassColorModel extends LiquidGlassColorModel {
  /// Creates the appearance-independent clear-glass model.
  const Ios27ClearLiquidGlassColorModel();

  @override
  String toJson() => 'ios27Clear';

  @override
  double get shaderValue => 3;

  @override
  double get fakeGlintLuminance => 3.26;

  @override
  ({Color emission, double transmittance, double lift, double chromaGain})
  faceTransfer(double shortSide, {double tintAmount = 0}) => (
    emission: const Color.from(
      alpha: 1,
      red: 0.126,
      green: 0.126,
      blue: 0.126,
    ),
    transmittance: 0.954,
    lift: 0,
    chromaGain: 1.057,
  );

  @override
  Color tintTone(Color tint, double luminance) =>
      const Ios27LiquidGlassColorModel(
        brightness: Brightness.light,
      ).tintTone(tint, luminance);

  @override
  Color approximateSurfaceTint(Color tint) {
    if (tint.a <= 0) return const Color(0x00000000);
    return tintTone(tint, 0.5).withValues(alpha: tint.a);
  }

  @override
  List<Object?> get props => const [];
}

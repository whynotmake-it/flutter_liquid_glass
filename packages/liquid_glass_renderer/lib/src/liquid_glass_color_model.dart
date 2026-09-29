import 'dart:math' as math;
import 'dart:ui';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Defines how a glass tint is combined with transmitted backdrop content.
///
/// The model owns its transfer functions and renderer encoding. Use
/// [LiquidGlassColorModel.direct] for unrestricted manual color controls or
/// [LiquidGlassColorModel.ios27] for Apple's backdrop-adaptive tint behavior.
sealed class LiquidGlassColorModel with Equatable {
  const LiquidGlassColorModel();

  /// Applies tint, gamma, saturation, and vibrancy directly.
  const factory LiquidGlassColorModel.direct() = DirectLiquidGlassColorModel;

  /// Derives an iOS 27-style tonal tint response for [brightness].
  const factory LiquidGlassColorModel.ios27({
    required Brightness brightness,
  }) = Ios27LiquidGlassColorModel;

  /// Restores a model identifier emitted by [toJson].
  factory LiquidGlassColorModel.fromJson(Object? value) => switch (value) {
    'ios27Light' => const LiquidGlassColorModel.ios27(
      brightness: Brightness.light,
    ),
    'ios27Dark' => const LiquidGlassColorModel.ios27(
      brightness: Brightness.dark,
    ),
    _ => const LiquidGlassColorModel.direct(),
  };

  /// Stable identifier used by appearance preset JSON.
  String toJson();

  /// Compact value consumed by the fragment shader.
  @internal
  double get shaderValue;

  /// Neutral material wash underneath an adaptive tint.
  @internal
  Color get neutralMaterialTint;

  /// Luminance self-screen amount and chroma gain of the untinted face, or
  /// `null` when transmitted content is composited per channel.
  ///
  /// Mirrors `ios27FaceTransfer` in the final shader.
  @internal
  ({double lift, double chromaGain})? get faceTransfer;

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
  Color get neutralMaterialTint => const Color(0x00000000);

  @override
  ({double lift, double chromaGain})? get faceTransfer => null;

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
  Color get neutralMaterialTint => brightness == Brightness.dark
      ? const Color.from(
          alpha: 0.56,
          red: 57.142857 / 255,
          green: 57.142857 / 255,
          blue: 57.142857 / 255,
        )
      : const Color.from(
          alpha: 0.407,
          red: 253 / 255,
          green: 252 / 255,
          blue: 253 / 255,
        );

  @override
  ({double lift, double chromaGain}) get faceTransfer =>
      brightness == Brightness.dark
      ? (lift: 1.0, chromaGain: 1.03)
      : (lift: 0.13, chromaGain: 1.17);

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

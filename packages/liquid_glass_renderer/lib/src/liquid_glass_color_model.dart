import 'dart:math' as math;
import 'dart:ui';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Interpolates linearly between the Liquid Glass slider endpoints: Clear
/// (`0`) and Tinted (`1`).
@internal
double sliderKeyframes(double tintAmount, double clear, double tinted) =>
    clear + (tinted - clear) * tintAmount.clamp(0.0, 1.0);

/// A linear curve over the Liquid Glass slider position.
///
/// The endpoints sit at Clear (`0`) and Tinted (`1`). This mirrors the
/// endpoint interpolation in the final render shader.
@immutable
class GlassColorCurve with Equatable {
  /// A curve through [clear] and [tinted].
  const GlassColorCurve(this.clear, this.tinted);

  /// A curve that holds [value] at every slider position.
  const GlassColorCurve.constant(double value)
    : clear = value,
      tinted = value;

  /// Value at the Clear slider position (`0`).
  final double clear;

  /// Value at the Tinted slider position (`1`).
  final double tinted;

  /// The value at [tintAmount].
  double evaluate(double tintAmount) =>
      sliderKeyframes(tintAmount, clear, tinted);

  @override
  List<Object?> get props => [clear, tinted];
}

/// One boundary of the tint-tone ramp, `base + amplitude *
/// (min(1, luminance / pivot))^exponent`.
///
/// `pivot` normalizes luminance into the ramp; setting it to `1` (with
/// luminance already clamped to `0..1`) leaves the power curve unclamped.
@immutable
class GlassToneRamp with Equatable {
  /// A luminance response `base + amplitude * (min(1, Y / pivot))^exponent`.
  const GlassToneRamp({
    required this.base,
    required this.amplitude,
    required this.pivot,
    required this.exponent,
  });

  /// A ramp that holds [base] at every luminance.
  const GlassToneRamp.constant(double base)
    : this(base: base, amplitude: 0, pivot: 1, exponent: 1);

  /// Ramp value at zero luminance (and the offset everywhere when
  /// [amplitude] is zero).
  final double base;

  /// Scale of the luminance-dependent part.
  final double amplitude;

  /// Luminance at which the ramp saturates; must be positive.
  final double pivot;

  /// Curvature of the response.
  final double exponent;

  /// Evaluates the ramp at [luminance] (unclamped input is clamped here).
  double evaluate(double luminance) {
    final y = luminance.clamp(0.0, 1.0);
    return base +
        amplitude * math.pow(math.min(1.0, y / pivot), exponent).toDouble();
  }

  @override
  List<Object?> get props => [base, amplitude, pivot, exponent];
}

/// Every numeric constant of the adaptive (backdrop-conditioned) color
/// model, driven from Dart and consumed by the final render shader as a
/// uniform block.
///
/// The untinted face of a shape whose shorter side is `shortSide` logical
/// pixels is
/// `emission + transmittance * lum(Y) + chromaGain * (backdrop - Y)` with
/// `lum(Y) = Y + lift * Y * (1 - Y)`; `emission` is premultiplied. The tint
/// response maps each tint channel `c` to
/// `clamp(lo + (hi - lo) * c^gamma)` where `lo`/`hi` are [GlassToneRamp]s of
/// backdrop luminance and `gamma = 1 + toneGammaLuminance * (1 - Y)`.
///
/// The fitted iOS 27 parameter sets ship as [GlassColorParameters.ios27Light],
/// [GlassColorParameters.ios27Dark] and [GlassColorParameters.ios27Clear];
/// subclasses are not needed for custom materials — compose parameters
/// instead.
@immutable
class GlassColorParameters with Equatable {
  /// Creates a fully specified adaptive color parameter set.
  const GlassColorParameters({
    required this.emissionColor,
    required this.emissionAlpha,
    required this.transmittanceSmall,
    required this.luminanceLift,
    required this.chromaGain,
    this.transmittanceLarge,
    this.transmittanceSizeStart = 0,
    this.transmittanceSizeEnd = -1,
    this.toneLow = const GlassToneRamp.constant(0),
    this.toneHigh = const GlassToneRamp.constant(1),
    this.toneGammaLuminance = 0,
    this.glintLuminance = 1.6,
    this.glintFaceGain = 0,
    this.glintVibrancy = 2.85,
    this.contourResponse = 0,
    this.fakeGlintLuminance = 1.6,
  });

  /// Rebuilds parameters from the [toJson] map, optionally merging a
  /// `preset` base (`'ios27Light'`, `'ios27Dark'` or `'ios27Clear'`) so a
  /// fit candidate only has to carry the keys it changes.
  factory GlassColorParameters.fromJson(Map<String, Object?> json) {
    final initial = switch (json['preset']) {
      'ios27Dark' => ios27Dark,
      'ios27Clear' => ios27Clear,
      'ios27Light' || null => ios27Light,
      _ => throw ArgumentError.value(json['preset'], 'preset'),
    };
    var base = initial;
    List<double>? list(String key) =>
        (json[key] as List?)?.map((v) => (v as num).toDouble()).toList();
    GlassColorCurve? curve(String key) => switch (list(key)) {
      null => null,
      [final a, final b] => GlassColorCurve(a, b),
      _ => throw ArgumentError.value(json[key], key),
    };
    GlassToneRamp? ramp(String key) => switch (list(key)) {
      null => null,
      [final a, final b, final c, final d] => GlassToneRamp(
        base: a,
        amplitude: b,
        pivot: c,
        exponent: d,
      ),
      _ => throw ArgumentError.value(json[key], key),
    };
    double? number(String key) => (json[key] as num?)?.toDouble();
    double? at(String key, int index) {
      final values = list(key);
      return values != null && values.length > index ? values[index] : null;
    }

    if (list('emissionColor') case final rgb?) {
      base = base.copyWith(
        emissionColor: Color.fromRGBO(
          (rgb[0] * 255).round(),
          (rgb[1] * 255).round(),
          (rgb[2] * 255).round(),
          1,
        ),
      );
    }
    return base.copyWith(
      emissionAlpha: curve('emissionAlpha'),
      transmittanceSmall: curve('transmittanceSmall'),
      transmittanceLarge: curve('transmittanceLarge'),
      transmittanceSizeStart: at('transmittanceSize', 0),
      transmittanceSizeEnd: at('transmittanceSize', 1),
      luminanceLift: curve('luminanceLift'),
      chromaGain: curve('chromaGain'),
      toneLow: ramp('toneLow'),
      toneHigh: ramp('toneHigh'),
      toneGammaLuminance: number('toneGammaLuminance'),
      glintLuminance: at('glint', 0),
      glintFaceGain: at('glint', 1),
      glintVibrancy: at('glint', 2),
      contourResponse: number('contourResponse'),
      fakeGlintLuminance: number('fakeGlintLuminance'),
    );
  }


  /// Unpremultiplied emission color of the face wash.
  final Color emissionColor;

  /// Premultiplied emission strength over the slider.
  final GlassColorCurve emissionAlpha;

  /// Transmittance over the slider for shapes up to
  /// [transmittanceSizeStart] logical pixels on the short side.
  final GlassColorCurve transmittanceSmall;

  /// Transmittance over the slider for shapes from
  /// [transmittanceSizeEnd] logical pixels on the short side, or `null` to
  /// use [transmittanceSmall] at every size.
  final GlassColorCurve? transmittanceLarge;

  /// Short side where [transmittanceSmall] applies in full. When
  /// `transmittanceSizeEnd <= transmittanceSizeStart` the transmittance is
  /// size-independent and only [transmittanceSmall] is used.
  final double transmittanceSizeStart;

  /// Short side where [transmittanceLarge] applies in full.
  final double transmittanceSizeEnd;

  /// S-curve lift applied to transmitted luminance.
  final GlassColorCurve luminanceLift;

  /// Gain applied to the transmitted chroma.
  final GlassColorCurve chromaGain;

  /// Luminance ramp of the tint tone's lower bound.
  final GlassToneRamp toneLow;

  /// Luminance ramp of the tint tone's upper bound.
  final GlassToneRamp toneHigh;

  /// Change of the tint-channel exponent `1 + toneGammaLuminance * (1 - Y)`
  /// with backdrop luminance `Y`.
  final double toneGammaLuminance;

  /// Luminance of the glint's bright target (real glass: HDR-capable).
  final double glintLuminance;

  /// How much of the lit face is added to the glint target. Clear glass
  /// brightens its own face instead of pulling toward fixed white.
  final double glintFaceGain;

  /// How much the glint amplifies face chroma.
  final double glintVibrancy;

  /// How strongly the slider's added opacity strengthens the dark border.
  /// `1 + contourResponse * (T(0) - T(tintAmount))` scales the border alpha.
  final double contourResponse;

  /// Luminance of the glint target FakeGlass composites, which cannot see
  /// the face. May differ from [glintLuminance] because FakeGlass clamps to
  /// SDR.
  final double fakeGlintLuminance;

  /// The fitted iOS 27 regular material in light appearance: a near-white
  /// wash that becomes more opaque and desaturating along the slider.
  static const ios27Light = GlassColorParameters(
    emissionColor: Color.fromRGBO(253, 252, 253, 1),
    emissionAlpha: GlassColorCurve(1 - 0.592, 1 - 0.286),
    transmittanceSmall: GlassColorCurve(0.592, 0.286),
    luminanceLift: GlassColorCurve.constant(0.13),
    chromaGain: GlassColorCurve(1.17, 0.751),
    toneHigh: _lightToneHigh,
    toneGammaLuminance: .07044432,
    fakeGlintLuminance: 2.9,
  );

  static const _lightToneHigh = GlassToneRamp(
    base: .76059211,
    amplitude: 1 - .76059211,
    pivot: 1,
    exponent: .90667748,
  );

  /// The fitted iOS 27 regular material in dark appearance: constant
  /// `32/255` emission, density rising linearly with size and slider, and a
  /// border that strengthens with the opacity the slider adds.
  static const ios27Dark = GlassColorParameters(
    emissionColor: Color.fromRGBO(32, 32, 32, 1),
    emissionAlpha: GlassColorCurve.constant(1),
    transmittanceSmall: GlassColorCurve(0.597, 0.295),
    transmittanceLarge: GlassColorCurve(0.447, 0.195),
    transmittanceSizeStart: 75,
    transmittanceSizeEnd: 105,
    luminanceLift: GlassColorCurve(1, 1.13),
    chromaGain: GlassColorCurve(1.02, 0.572),
    toneLow: GlassToneRamp(
      base: 0,
      amplitude: .08611765,
      pivot: .62019473,
      exponent: 1.01150514,
    ),
    toneHigh: GlassToneRamp(
      base: 1,
      amplitude: -.01560784,
      pivot: .46837318,
      exponent: 1.85642966,
    ),
    contourResponse: .95,
    fakeGlintLuminance: 2.9,
  );

  /// The fitted iOS 27 `Glass.clear`, identical in light and dark.
  ///
  /// Measured on the pinned solid palettes, clear glass lifts black to
  /// 32/255, transmits 0.954 of the backdrop's luminance, passes chroma
  /// through at 1.057 and uses the light tone ramp. Its glint brightens its
  /// own face rather than pulling toward a fixed bright target.
  static const ios27Clear = GlassColorParameters(
    emissionColor: Color.fromRGBO(255, 255, 255, 1),
    emissionAlpha: GlassColorCurve.constant(.126),
    transmittanceSmall: GlassColorCurve.constant(.954),
    luminanceLift: GlassColorCurve.constant(0),
    chromaGain: GlassColorCurve.constant(1.057),
    toneHigh: _lightToneHigh,
    toneGammaLuminance: .07044432,
    glintLuminance: 2.34,
    glintFaceGain: 3.58,
    glintVibrancy: .78,
    fakeGlintLuminance: 3.26,
  );

  /// Serializes every parameter; parse back with `fromJson`.
  Map<String, Object?> toJson() => {
    'emissionColor': [emissionColor.r, emissionColor.g, emissionColor.b],
    'emissionAlpha': _curveToJson(emissionAlpha),
    'transmittanceSmall': _curveToJson(transmittanceSmall),
    if (transmittanceLarge case final large?)
      'transmittanceLarge': _curveToJson(large),
    'transmittanceSize': [transmittanceSizeStart, transmittanceSizeEnd],
    'luminanceLift': _curveToJson(luminanceLift),
    'chromaGain': _curveToJson(chromaGain),
    'toneLow': _rampToJson(toneLow),
    'toneHigh': _rampToJson(toneHigh),
    'toneGammaLuminance': toneGammaLuminance,
    'glint': [glintLuminance, glintFaceGain, glintVibrancy],
    'contourResponse': contourResponse,
    'fakeGlintLuminance': fakeGlintLuminance,
  };

  static List<double> _curveToJson(GlassColorCurve curve) =>
      [curve.clear, curve.tinted];

  static List<double> _rampToJson(GlassToneRamp ramp) =>
      [ramp.base, ramp.amplitude, ramp.pivot, ramp.exponent];

  /// A copy with the given fields replaced.
  GlassColorParameters copyWith({
    Color? emissionColor,
    GlassColorCurve? emissionAlpha,
    GlassColorCurve? transmittanceSmall,
    GlassColorCurve? transmittanceLarge,
    double? transmittanceSizeStart,
    double? transmittanceSizeEnd,
    GlassColorCurve? luminanceLift,
    GlassColorCurve? chromaGain,
    GlassToneRamp? toneLow,
    GlassToneRamp? toneHigh,
    double? toneGammaLuminance,
    double? glintLuminance,
    double? glintFaceGain,
    double? glintVibrancy,
    double? contourResponse,
    double? fakeGlintLuminance,
  }) => GlassColorParameters(
    emissionColor: emissionColor ?? this.emissionColor,
    emissionAlpha: emissionAlpha ?? this.emissionAlpha,
    transmittanceSmall: transmittanceSmall ?? this.transmittanceSmall,
    transmittanceLarge: transmittanceLarge ?? this.transmittanceLarge,
    transmittanceSizeStart:
        transmittanceSizeStart ?? this.transmittanceSizeStart,
    transmittanceSizeEnd: transmittanceSizeEnd ?? this.transmittanceSizeEnd,
    luminanceLift: luminanceLift ?? this.luminanceLift,
    chromaGain: chromaGain ?? this.chromaGain,
    toneLow: toneLow ?? this.toneLow,
    toneHigh: toneHigh ?? this.toneHigh,
    toneGammaLuminance: toneGammaLuminance ?? this.toneGammaLuminance,
    glintLuminance: glintLuminance ?? this.glintLuminance,
    glintFaceGain: glintFaceGain ?? this.glintFaceGain,
    glintVibrancy: glintVibrancy ?? this.glintVibrancy,
    contourResponse: contourResponse ?? this.contourResponse,
    fakeGlintLuminance: fakeGlintLuminance ?? this.fakeGlintLuminance,
  );

  /// Transmittance at [shortSide] logical pixels and slider [tintAmount].
  ///
  /// The two keyframe curves are blended by a smoothstep across
  /// [transmittanceSizeStart]..[transmittanceSizeEnd]; when the range is
  /// empty the small-side curve applies at every size.
  double transmittanceAt(double shortSide, double tintAmount) {
    var sizeMix = 0.0;
    if (transmittanceSizeEnd > transmittanceSizeStart) {
      final t =
          ((shortSide - transmittanceSizeStart) /
                  (transmittanceSizeEnd - transmittanceSizeStart))
              .clamp(0.0, 1.0);
      sizeMix = t * t * (3 - 2 * t);
    }
    final small = transmittanceSmall.evaluate(tintAmount);
    final large = (transmittanceLarge ?? transmittanceSmall).evaluate(
      tintAmount,
    );
    return small + (large - small) * sizeMix;
  }

  /// The untinted face for a shape whose shorter side is [shortSide]
  /// logical pixels.
  ///
  /// The face is `emission + transmittance * lum(Y) + chromaGain *
  /// (backdrop - Y)` with `lum(Y) = Y + lift * Y * (1 - Y)`; `emission` is
  /// premultiplied. Mirrors `parametricNeutralTint` and
  /// `parametricFaceTransfer` in the final render shader.
  ({Color emission, double transmittance, double lift, double chromaGain})
  faceTransfer(double shortSide, {double tintAmount = 0}) {
    final alpha = emissionAlpha.evaluate(tintAmount);
    return (
      emission: Color.from(
        alpha: 1,
        red: emissionColor.r * alpha,
        green: emissionColor.g * alpha,
        blue: emissionColor.b * alpha,
      ),
      transmittance: transmittanceAt(shortSide, tintAmount),
      lift: luminanceLift.evaluate(tintAmount),
      chromaGain: chromaGain.evaluate(tintAmount),
    );
  }

  /// Factor applied to the border strength at slider [tintAmount] for a
  /// shape of [shortSide] logical pixels.
  double contourScale(double shortSide, double tintAmount) =>
      1 +
      contourResponse *
          (transmittanceAt(shortSide, 0) -
              transmittanceAt(shortSide, tintAmount));

  /// Maps one opaque tint channel triple to the tone selected for backdrop
  /// [luminance].
  Color tintTone(Color tint, double luminance) {
    final lo = toneLow.evaluate(luminance);
    final hi = toneHigh.evaluate(luminance);
    final gamma = 1 + toneGammaLuminance * (1 - luminance);
    double channel(double c) =>
        (lo + (hi - lo) * math.pow(math.max(c, 0.0), gamma)).clamp(0.0, 1.0);
    return Color.from(
      alpha: 1,
      red: channel(tint.r),
      green: channel(tint.g),
      blue: channel(tint.b),
    );
  }

  /// Floats of one slot of `uColorModelParams` in the final render shader.
  /// Eight vec4 slots per model; keep the packing mirrored with
  /// liquid_glass_final_render_core.glsl.
  @internal
  List<double> toShaderParameters() {
    final large = transmittanceLarge ?? transmittanceSmall;
    return [
      emissionColor.r, emissionColor.g, emissionColor.b, emissionAlpha.clear,
      emissionAlpha.tinted, 0, //
      transmittanceSizeStart, transmittanceSizeEnd,
      transmittanceSmall.clear, transmittanceSmall.tinted,
      large.clear, large.tinted,
      luminanceLift.clear, luminanceLift.tinted,
      chromaGain.clear, chromaGain.tinted,
      toneLow.base, toneLow.amplitude, toneLow.pivot, toneLow.exponent,
      toneHigh.base, toneHigh.amplitude, toneHigh.pivot, toneHigh.exponent,
      toneGammaLuminance, glintLuminance, glintFaceGain, glintVibrancy,
      contourResponse, 0, 0, 0,
    ];
  }

  /// Floats per model slot in `uColorModelParams` (eight vec4).
  static const int shaderParameterFloatCount = 32;

  @override
  List<Object?> get props => [
    emissionColor,
    emissionAlpha,
    transmittanceSmall,
    transmittanceLarge,
    transmittanceSizeStart,
    transmittanceSizeEnd,
    luminanceLift,
    chromaGain,
    toneLow,
    toneHigh,
    toneGammaLuminance,
    glintLuminance,
    glintFaceGain,
    glintVibrancy,
    contourResponse,
    fakeGlintLuminance,
  ];
}

/// Defines how a glass tint is combined with transmitted backdrop content.
///
/// [parameters] holds every numeric constant of the model; `null` selects
/// the direct model, which applies tint, gamma, saturation and vibrancy per
/// channel with no backdrop conditioning. The fitted iOS 27 models ship as
/// presets: [LiquidGlassColorModel.ios27] and
/// [LiquidGlassColorModel.ios27Clear]. Compose [GlassColorParameters] for
/// custom materials — for example
/// `LiquidGlassColorModel(GlassColorParameters.ios27Dark.copyWith(...))`.
final class LiquidGlassColorModel with Equatable {
  /// A backdrop-adaptive model driven entirely by [parameters].
  const LiquidGlassColorModel(this.parameters);

  /// Applies tint, gamma, saturation, and vibrancy directly.
  const LiquidGlassColorModel.direct() : parameters = null;

  /// The fitted iOS 27-style tonal response for [brightness].
  const LiquidGlassColorModel.ios27({required Brightness brightness})
    : parameters = brightness == Brightness.dark
          ? GlassColorParameters.ios27Dark
          : GlassColorParameters.ios27Light;

  /// iOS 27 `Glass.clear`, identical in light and dark appearance.
  const LiquidGlassColorModel.ios27Clear()
    : parameters = GlassColorParameters.ios27Clear;

  /// Restores a model written by [toJson]: a preset name or a parameter map
  /// (see [GlassColorParameters.fromJson]).
  factory LiquidGlassColorModel.fromJson(Object? value) => switch (value) {
    'ios27Light' => const LiquidGlassColorModel.ios27(
      brightness: Brightness.light,
    ),
    'ios27Dark' => const LiquidGlassColorModel.ios27(
      brightness: Brightness.dark,
    ),
    'ios27Clear' => const LiquidGlassColorModel.ios27Clear(),
    'direct' => const LiquidGlassColorModel.direct(),
    final Map<String, Object?> map => LiquidGlassColorModel(
      GlassColorParameters.fromJson(map),
    ),
    _ => throw ArgumentError.value(value, 'colorModel'),
  };

  /// The model's constants, or `null` for [LiquidGlassColorModel.direct].
  final GlassColorParameters? parameters;

  /// Stable identifier (or parameter map) used by appearance preset JSON.
  Object toJson() => switch (parameters) {
    null => 'direct',
    GlassColorParameters.ios27Light => 'ios27Light',
    GlassColorParameters.ios27Dark => 'ios27Dark',
    GlassColorParameters.ios27Clear => 'ios27Clear',
    final params => params.toJson(),
  };

  /// The untinted face for a shape whose shorter side is [shortSide] logical
  /// pixels, or `null` when transmitted content is composited per channel
  /// (the direct model).
  ///
  /// See [GlassColorParameters.faceTransfer].
  @internal
  ({Color emission, double transmittance, double lift, double chromaGain})?
  faceTransfer(double shortSide, {double tintAmount = 0}) =>
      parameters?.faceTransfer(shortSide, tintAmount: tintAmount);

  /// Factor applied to the border strength at the Liquid Glass slider
  /// position [tintAmount]. Mirrors the shader's contour response.
  @internal
  double contourScale(double shortSide, double tintAmount) =>
      parameters?.contourScale(shortSide, tintAmount) ?? 1;

  /// Luminance of the neutral glint target FakeGlass composites, which
  /// cannot scale with the face it does not sample.
  @internal
  double get fakeGlintLuminance => parameters?.fakeGlintLuminance ?? 1.6;

  /// How much the face contributes to the FakeGlass glint target.
  /// FakeGlass approximates the face with its surface tint plus emission.
  @internal
  double get fakeGlintFaceGain => parameters?.glintFaceGain ?? 0;

  /// How strongly the FakeGlass glint amplifies the face chroma proxy.
  @internal
  double get fakeGlintVibrancy => parameters?.glintVibrancy ?? 2.85;

  /// Maps one opaque tint to the tone selected for backdrop [luminance].
  ///
  /// The direct model returns [tint] unchanged. Adaptive models implement
  /// Apple's brightness-mapped range of tint tones through
  /// [GlassColorParameters.tintTone].
  @visibleForTesting
  Color tintTone(Color tint, double luminance) =>
      parameters?.tintTone(tint, luminance) ?? tint;

  /// Resolves the single-color surface tint painted by FakeGlass.
  ///
  /// FakeGlass cannot inspect backdrop luminance in its analytic surface
  /// shader, so adaptive models evaluate their tonal ramp at a midtone. Their
  /// neutral face is applied by the backdrop color filter instead, so it is
  /// not part of this color.
  @internal
  Color approximateSurfaceTint(Color tint) {
    if (parameters == null) return tint;
    if (tint.a <= 0) return const Color(0x00000000);
    return tintTone(tint, 0.5).withValues(alpha: tint.a);
  }

  @override
  List<Object?> get props => [parameters];
}

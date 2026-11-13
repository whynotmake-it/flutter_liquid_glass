import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart' show experimental;

/// A curve over the Liquid Glass slider position.
///
/// The endpoints sit at Clear (`0`) and Tinted (`1`). A curve of two values
/// is the line between them; one [GlassColorCurve.through] more values bends
/// at each of them.
@immutable
class GlassColorCurve {
  /// The line through [clear] and [tinted].
  const GlassColorCurve(this.clear, this.tinted) : _values = null;

  /// A curve that holds [value] at every slider position.
  const GlassColorCurve.constant(double value)
    : clear = value,
      tinted = value,
      _values = null;

  /// A curve through [values], spaced evenly over the slider from Clear to
  /// Tinted and linear between neighbours.
  GlassColorCurve.through(List<double> values)
    : assert(values.length >= 2, 'A curve has both of its ends.'),
      clear = values.first,
      tinted = values.last,
      _values = List.unmodifiable(values);

  /// A curve through [value] at every slider position iOS stops at, which
  /// are the multiples of 0.05.
  factory GlassColorCurve.sampled(double Function(double tintAmount) value) =>
      GlassColorCurve.through([for (var i = 0; i <= 20; i++) value(i / 20)]);

  /// Value at the Clear slider position (`0`).
  final double clear;

  /// Value at the Tinted slider position (`1`).
  final double tinted;

  final List<double>? _values;

  /// The value at [tintAmount].
  double evaluate(double tintAmount) {
    final amount = tintAmount.clamp(0.0, 1.0);
    final values = _values;
    if (values == null) return clear + (tinted - clear) * amount;
    final at = amount * (values.length - 1);
    final below = math.min(at.floor(), values.length - 2);
    return values[below] + (values[below + 1] - values[below]) * (at - below);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          other is GlassColorCurve &&
          other.clear == clear &&
          other.tinted == tinted &&
          listEquals(other._values, _values);

  @override
  int get hashCode => Object.hash(
    clear,
    tinted,
    _values == null ? null : Object.hashAll(_values),
  );

  @override
  String toString() =>
      'GlassColorCurve(${(_values ?? [clear, tinted]).join(', ')})';
}

/// The veil iOS 27 lays over the face of glass larger than a control: the
/// face is pulled toward a wash of what lies behind it.
///
/// With `Y` the luminance of the backdrop, the wash is `black + (white -
/// black) * Y + saturation * (backdrop - Y)`. The face mixes toward it by
/// `opacity * w^4`, where `w` is the luminance of the face when the bleed
/// is [onBright] and one minus it otherwise: light glass veils its bright
/// parts with a near-white wash, dark glass its dark parts with a dim one.
///
/// Approximation: iOS washes with a blur of the backdrop as wide as a third
/// of the glass, the renderer with the backdrop the face itself shows. Over
/// a plain backdrop the two are the same.
@immutable
class GlassColorBleed {
  /// A bleed of [opacity] toward a wash from [black] to [white].
  const GlassColorBleed({
    required this.opacity,
    required this.black,
    required this.white,
    this.saturation = 1,
    this.onBright = false,
  });

  /// No bleed.
  const GlassColorBleed.none()
    : opacity = 0,
      black = 0,
      white = 1,
      saturation = 1,
      onBright = false;

  /// How far the face goes toward the wash where the bleed is strongest.
  final double opacity;

  /// The wash over a black backdrop.
  final double black;

  /// The wash over a white backdrop.
  final double white;

  /// The gain of the backdrop's chroma in the wash.
  final double saturation;

  /// Whether the bleed takes the bright parts of the face, not the dark
  /// ones.
  final bool onBright;

  /// How far a face of luminance [face] goes toward the wash.
  double share(double face) {
    final weight = (onBright ? face : 1 - face).clamp(0.0, 1.0);
    return opacity * weight * weight * weight * weight;
  }

  /// A grey face of luminance [face] over a grey backdrop of luminance
  /// [backdrop], after the bleed.
  double apply(double face, double backdrop) =>
      face + (black + (white - black) * backdrop - face) * share(face);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          other is GlassColorBleed &&
          other.opacity == opacity &&
          other.black == black &&
          other.white == white &&
          other.saturation == saturation &&
          other.onBright == onBright;

  @override
  int get hashCode => Object.hash(opacity, black, white, saturation, onBright);

  @override
  String toString() =>
      'GlassColorBleed($opacity, $black, $white, $saturation, $onBright)';
}

/// One boundary of the tint-tone ramp, `base + amplitude *
/// (min(1, luminance / pivot))^exponent`.
///
/// `pivot` normalizes luminance into the ramp; setting it to `1` (with
/// luminance already clamped to `0..1`) leaves the power curve unclamped.
@immutable
class GlassToneRamp {
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
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          other is GlassToneRamp &&
          other.base == base &&
          other.amplitude == amplitude &&
          other.pivot == pivot &&
          other.exponent == exponent;

  @override
  int get hashCode => Object.hash(base, amplitude, pivot, exponent);

  @override
  String toString() => 'GlassToneRamp($base, $amplitude, $pivot, $exponent)';
}

/// Every numeric constant of the adaptive (backdrop-conditioned) color
/// model, driven from Dart and consumed by the final render shader as a
/// uniform block.
///
/// The untinted face of a shape is
/// `emission + transmittance * lum(Y) + chromaGain * k * (1.3 - 0.3 * k) *
/// (backdrop - Y)` with `lum(Y) = Y + lift * Y * (1 - Y)` and
/// `k = 1 - Y * lift / (1 + lift)`; `emission` is premultiplied. This is
/// the face of iOS 27 in other terms: the lift is its cap on luminance, and
/// the chroma falls with that cap as iOS's does. [bleed] then veils the
/// face. A tint then covers the face by its opacity with a tone picked by
/// the luminance `F` of the face: each tint channel `c` becomes
/// `clamp(lo + (hi - lo) * c^gamma)` where `lo`/`hi` are [GlassToneRamp]s of
/// `F` and `gamma = 1 + toneGammaLuminance * (1 - F)`.
///
/// The iOS 27 parameter sets ship as [GlassColorParameters.ios27Regular],
/// which follows the size of the glass, and [GlassColorParameters.ios27Clear];
/// subclasses are not needed for custom materials; compose parameters
/// instead.
@immutable
class GlassColorParameters {
  /// Creates a fully specified adaptive color parameter set.
  const GlassColorParameters({
    required this.emissionColor,
    required this.emissionAlpha,
    required this.transmittance,
    required this.luminanceLift,
    required this.chromaGain,
    this.bleed = const GlassColorBleed.none(),
    this.toneLow = const GlassToneRamp.constant(0),
    this.toneHigh = const GlassToneRamp.constant(1),
    this.toneGammaLuminance = 0,
    this.glintLuminance = _defaultGlintLuminance,
    this.glintFaceGain = _defaultGlintFaceGain,
    this.glintVibrancy = _defaultGlintVibrancy,
    this.contourResponse = 0,
    this.fakeGlintLuminance = _defaultGlintLuminance,
  });

  /// Rebuilds parameters from the [toJson] map, optionally merging a
  /// `preset` base (`'ios27Light'`, `'ios27Dark'` or `'ios27Clear'`) so a
  /// fit candidate only has to carry the keys it changes.
  /// Keys without a field are ignored.
  factory GlassColorParameters.fromJson(Map<String, Object?> json) {
    var base = switch (json['preset']) {
      'ios27Dark' => ios27Dark,
      'ios27Clear' => ios27Clear,
      'ios27Light' || null => ios27Light,
      _ => throw ArgumentError.value(json['preset'], 'preset'),
    };
    List<double>? list(String key) =>
        (json[key] as List?)?.map((v) => (v as num).toDouble()).toList();
    GlassColorCurve? curve(String key) => switch (list(key)) {
      null => null,
      [final a, final b] => GlassColorCurve(a, b),
      final values when values.length > 2 => GlassColorCurve.through(values),
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
      transmittance: curve('transmittance'),
      luminanceLift: curve('luminanceLift'),
      chromaGain: curve('chromaGain'),
      bleed: switch (list('bleed')) {
        null => null,
        [final opacity, final black, final white, final saturation, final on] =>
          GlassColorBleed(
            opacity: opacity,
            black: black,
            white: white,
            saturation: saturation,
            onBright: on != 0,
          ),
        _ => throw ArgumentError.value(json['bleed'], 'bleed'),
      },
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

  /// The iOS 27 regular material in [brightness] as glass whose shorter
  /// side is [shortSide] points wears it.
  ///
  /// iOS gives glass a material by its size. Up to 64 points on the shorter
  /// side it is a control's: light glass lifts black to 40 %, dark glass to
  /// 12.5 % and keeps 60 % of the backdrop's luminance. From 160 points it
  /// is a panel's: a veil ([bleed]) pulls the bright parts of light glass
  /// toward white and the dark parts of dark glass toward a dim grey, and
  /// dark glass keeps 45 % of the luminance. Between the two every part
  /// grows linearly; dark glass reaches its cap on luminance at 104 points.
  /// Along the Liquid Glass slider a fill covers more of the face: white on
  /// light glass, grey on dark glass.
  ///
  /// A tint runs from a darker tone of itself over a black face to itself
  /// over a white one on light glass, and between two tones close to itself
  /// on dark glass. iOS tints with a grey by another law than with a color:
  /// [greyTint] gives the parameters of glass tinted with a grey.
  ///
  /// The numbers are the inputs UIKit gives its glass on iOS 27, and the
  /// face they give agrees with captures of native glass over plain colors
  /// within a level out of 255. Approximation: the tones of a color are
  /// exact for fully saturated colors and up to 0.12 off the darker tone of
  /// a pale one.
  ///
  /// Without [shortSide] it is the material of a panel.
  factory GlassColorParameters.ios27Regular({
    required Brightness brightness,
    double shortSide = double.infinity,
    bool greyTint = false,
  }) {
    final dark = brightness == Brightness.dark;
    final parameters = shortSide <= 64
        ? (dark ? _ios27DarkControl : _ios27LightControl)
        : shortSide >= 160
        ? (dark ? ios27Dark : ios27Light)
        : _ios27Regular(dark, shortSide);
    return greyTint ? parameters._greyTinted : parameters;
  }

  /// Unpremultiplied emission color of the face wash.
  final Color emissionColor;

  /// Premultiplied emission strength over the slider.
  final GlassColorCurve emissionAlpha;

  /// Transmittance of transmitted content over the slider.
  final GlassColorCurve transmittance;

  /// S-curve lift applied to transmitted luminance.
  final GlassColorCurve luminanceLift;

  /// Gain applied to the transmitted chroma.
  final GlassColorCurve chromaGain;

  /// The veil over the face of glass larger than a control.
  final GlassColorBleed bleed;

  /// Luminance ramp of the tint tone's lower bound.
  final GlassToneRamp toneLow;

  /// Luminance ramp of the tint tone's upper bound.
  final GlassToneRamp toneHigh;

  /// Change of the tint-channel exponent `1 + toneGammaLuminance * (1 - F)`
  /// with the luminance `F` of the face.
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
  /// the face.
  final double fakeGlintLuminance;

  static const double _defaultGlintLuminance = 1.6;
  static const double _defaultGlintFaceGain = 0;
  static const double _defaultGlintVibrancy = 2.85;

  static GlassColorParameters _ios27Regular(bool dark, double shortSide) {
    final grown = ((shortSide - 64) / 96).clamp(0.0, 1.0);
    final black = dark ? 0.125 : 0.4;
    final white = dark ? 1.125 : 1.03;
    final saturation = dark ? 1.3 : 1.2;
    // The fill over the face: its grey and how much of the face it covers.
    double fillGrey(double amount) => dark ? 0.125 * (1 - 2 * amount).abs() : 1;
    double fill(double amount) => dark
        ? math.max(amount - 0.5, 0)
        : 0.4 * math.min(amount, 0.5) + 0.6 * math.max(amount - 0.5, 0);
    // The share of the backdrop's luminance white keeps.
    double cap(double amount) => dark
        ? 0.6 +
              (0.45 - 0.2 * math.min(amount, 0.5) - 0.6) *
                  ((shortSide - 64) / 40).clamp(0.0, 1.0)
        : ios27LightLuminanceCap;
    final base = dark ? _ios27DarkTones : _ios27LightTones;
    return base.copyWith(
      emissionAlpha: GlassColorCurve.sampled(
        (a) => black * (1 - fill(a)) + fillGrey(a) * fill(a),
      ),
      transmittance: GlassColorCurve.sampled(
        (a) => (white - black) * (1 - fill(a)) * cap(a),
      ),
      luminanceLift: GlassColorCurve.sampled((a) => (1 - cap(a)) / cap(a)),
      chromaGain: GlassColorCurve.sampled((a) => saturation * (1 - fill(a))),
      bleed: dark
          ? GlassColorBleed(opacity: 0.8 * grown, black: 0.125, white: 0.5)
          : GlassColorBleed(
              opacity: 0.5 * grown,
              black: 0.9,
              white: 1,
              saturation: 1.2,
              onBright: true,
            ),
    );
  }

  /// The share of a white backdrop's luminance light glass keeps before its
  /// own white point brightens it.
  ///
  /// iOS takes 1 on a display with headroom over white, which an iPhone
  /// has, and 0.94 on one without, such as the simulator's: there the
  /// brightest greys under light glass come out up to five levels darker.
  static const double ios27LightLuminanceCap = 1;

  // What the size and the slider do not set: the face's white emission and
  // the tones of a tint.
  static const _ios27LightTones = GlassColorParameters(
    emissionColor: Color.fromRGBO(255, 255, 255, 1),
    emissionAlpha: GlassColorCurve.constant(0),
    transmittance: GlassColorCurve.constant(1),
    luminanceLift: GlassColorCurve.constant(0),
    chromaGain: GlassColorCurve.constant(1),
    toneLow: _lightToneLow,
    toneHigh: _lightToneHigh,
  );

  // A channel c of a tint on light glass is 0.6706 c - 0.0706 over a black
  // face and c over a white one.
  static const _lightToneLow = GlassToneRamp(
    base: -.0706,
    amplitude: .0706,
    pivot: 1,
    exponent: 1,
  );
  static const _lightToneHigh = GlassToneRamp(
    base: .6,
    amplitude: .4,
    pivot: 1,
    exponent: 1,
  );

  // On dark glass it is 1.0362 c - 0.0306 over a black face and
  // 0.7946 c + 0.1735 over a white one.
  static const _ios27DarkTones = GlassColorParameters(
    emissionColor: Color.fromRGBO(255, 255, 255, 1),
    emissionAlpha: GlassColorCurve.constant(0),
    transmittance: GlassColorCurve.constant(1),
    luminanceLift: GlassColorCurve.constant(0),
    chromaGain: GlassColorCurve.constant(1),
    toneLow: GlassToneRamp(
      base: -.0306,
      amplitude: .2041,
      pivot: 1,
      exponent: 1,
    ),
    toneHigh: GlassToneRamp(
      base: 1.0056,
      amplitude: -.0375,
      pivot: 1,
      exponent: 1,
    ),
    contourResponse: .95,
  );

  // A grey g of a tint is 1.1875 g - 0.25 over a black face and 0.3125 more
  // over a white one, in both appearances and on clear glass.
  GlassColorParameters get _greyTinted => copyWith(
    toneLow: const GlassToneRamp(
      base: -.25,
      amplitude: .3125,
      pivot: 1,
      exponent: 1,
    ),
    toneHigh: const GlassToneRamp(
      base: .9375,
      amplitude: .3125,
      pivot: 1,
      exponent: 1,
    ),
    toneGammaLuminance: 0,
  );

  static final _ios27LightControl = _ios27Regular(false, 64);
  static final _ios27DarkControl = _ios27Regular(true, 64);

  /// The iOS 27 regular material in light appearance as a panel wears it;
  /// see [GlassColorParameters.ios27Regular].
  static final ios27Light = _ios27Regular(false, 160);

  /// The iOS 27 regular material in dark appearance as a panel wears it;
  /// see [GlassColorParameters.ios27Regular].
  static final ios27Dark = _ios27Regular(true, 160);

  /// The fitted iOS 27 `Glass.clear`, identical in light and dark.
  ///
  /// Clear glass lifts black to 12.5 %, takes white to 108 % and passes
  /// chroma through at 1.06, at every size and slider position: the inputs
  /// UIKit gives it on iOS 27. It takes the tint tones of light glass in
  /// both appearances, and its glint brightens its own face rather than
  /// pulling toward a fixed bright target.
  static const ios27Clear = GlassColorParameters(
    emissionColor: Color.fromRGBO(255, 255, 255, 1),
    emissionAlpha: GlassColorCurve.constant(.125),
    transmittance: GlassColorCurve.constant(.955),
    luminanceLift: GlassColorCurve.constant(0),
    chromaGain: GlassColorCurve.constant(1.06),
    toneLow: _lightToneLow,
    toneHigh: _lightToneHigh,
    glintLuminance: 2.34,
    glintFaceGain: 3.58,
    glintVibrancy: .78,
    fakeGlintLuminance: 3.26,
  );

  /// Serializes every parameter; parse back with `fromJson`.
  Map<String, Object?> toJson() => {
    'emissionColor': [emissionColor.r, emissionColor.g, emissionColor.b],
    'emissionAlpha': _curveToJson(emissionAlpha),
    'transmittance': _curveToJson(transmittance),
    'luminanceLift': _curveToJson(luminanceLift),
    'chromaGain': _curveToJson(chromaGain),
    'bleed': [
      bleed.opacity,
      bleed.black,
      bleed.white,
      bleed.saturation,
      if (bleed.onBright) 1.0 else 0.0,
    ],
    'toneLow': _rampToJson(toneLow),
    'toneHigh': _rampToJson(toneHigh),
    'toneGammaLuminance': toneGammaLuminance,
    'glint': [glintLuminance, glintFaceGain, glintVibrancy],
    'contourResponse': contourResponse,
    'fakeGlintLuminance': fakeGlintLuminance,
  };

  static List<double> _curveToJson(GlassColorCurve curve) =>
      curve._values ?? [curve.clear, curve.tinted];

  static List<double> _rampToJson(GlassToneRamp ramp) => [
    ramp.base,
    ramp.amplitude,
    ramp.pivot,
    ramp.exponent,
  ];

  /// A copy with the given fields replaced.
  GlassColorParameters copyWith({
    Color? emissionColor,
    GlassColorCurve? emissionAlpha,
    GlassColorCurve? transmittance,
    GlassColorCurve? luminanceLift,
    GlassColorCurve? chromaGain,
    GlassColorBleed? bleed,
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
    transmittance: transmittance ?? this.transmittance,
    luminanceLift: luminanceLift ?? this.luminanceLift,
    chromaGain: chromaGain ?? this.chromaGain,
    bleed: bleed ?? this.bleed,
    toneLow: toneLow ?? this.toneLow,
    toneHigh: toneHigh ?? this.toneHigh,
    toneGammaLuminance: toneGammaLuminance ?? this.toneGammaLuminance,
    glintLuminance: glintLuminance ?? this.glintLuminance,
    glintFaceGain: glintFaceGain ?? this.glintFaceGain,
    glintVibrancy: glintVibrancy ?? this.glintVibrancy,
    contourResponse: contourResponse ?? this.contourResponse,
    fakeGlintLuminance: fakeGlintLuminance ?? this.fakeGlintLuminance,
  );

  /// The untinted face under [bleed], as the class describes it, at
  /// [tintAmount]; `emission` is premultiplied.
  ({Color emission, double transmittance, double lift, double chromaGain})
  faceTransfer({double tintAmount = 0}) {
    final alpha = emissionAlpha.evaluate(tintAmount);
    return (
      emission: Color.from(
        alpha: 1,
        red: emissionColor.r * alpha,
        green: emissionColor.g * alpha,
        blue: emissionColor.b * alpha,
      ),
      transmittance: transmittance.evaluate(tintAmount),
      lift: luminanceLift.evaluate(tintAmount),
      chromaGain: chromaGain.evaluate(tintAmount),
    );
  }

  /// Factor applied to the border strength at slider [tintAmount].
  double contourScale(double tintAmount) =>
      1 +
      contourResponse *
          (transmittance.evaluate(0) - transmittance.evaluate(tintAmount));

  /// Maps one opaque tint channel triple to the tone selected for a face of
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          other is GlassColorParameters &&
          other.emissionColor == emissionColor &&
          other.emissionAlpha == emissionAlpha &&
          other.transmittance == transmittance &&
          other.luminanceLift == luminanceLift &&
          other.chromaGain == chromaGain &&
          other.bleed == bleed &&
          other.toneLow == toneLow &&
          other.toneHigh == toneHigh &&
          other.toneGammaLuminance == toneGammaLuminance &&
          other.glintLuminance == glintLuminance &&
          other.glintFaceGain == glintFaceGain &&
          other.glintVibrancy == glintVibrancy &&
          other.contourResponse == contourResponse &&
          other.fakeGlintLuminance == fakeGlintLuminance;

  @override
  int get hashCode => Object.hash(
    emissionColor,
    emissionAlpha,
    transmittance,
    luminanceLift,
    chromaGain,
    bleed,
    toneLow,
    toneHigh,
    toneGammaLuminance,
    glintLuminance,
    glintFaceGain,
    glintVibrancy,
    contourResponse,
    fakeGlintLuminance,
  );

  @override
  String toString() =>
      'GlassColorParameters($emissionColor, $emissionAlpha, $transmittance, '
      '$luminanceLift, $chromaGain, $bleed, $toneLow, $toneHigh, '
      '$toneGammaLuminance, $glintLuminance, $glintFaceGain, $glintVibrancy, '
      '$contourResponse, $fakeGlintLuminance)';
}

/// Defines how a glass tint is combined with transmitted backdrop content.
///
/// [parameters] holds every numeric constant of the model; `null` selects
/// the direct model, which applies tint, gamma, saturation and vibrancy per
/// channel with no backdrop conditioning. The iOS 27 models ship as
/// presets: [LiquidGlassColorModel.ios27], which follows the size of the
/// glass ([at]), and [LiquidGlassColorModel.ios27Clear]. A model of other
/// constants takes a [GlassColorParameters] of its own, or reads one from
/// [LiquidGlassColorModel.fromJson].
@immutable
final class LiquidGlassColorModel {
  /// A backdrop-adaptive model driven entirely by [parameters].
  ///
  /// The relative adjustments ([saturation], [transmissionGamma] and
  /// [vibrancy]) are fixed identity: the fitted parameter set carries the
  /// whole transfer.
  const LiquidGlassColorModel(GlassColorParameters parameters)
    : _parameters = parameters,
      _regular = null,
      saturation = 1,
      transmissionGamma = 1,
      vibrancy = 0;

  const LiquidGlassColorModel._worn(
    GlassColorParameters parameters,
    this.transmissionGamma,
  ) : _parameters = parameters,
      _regular = null,
      saturation = 1,
      vibrancy = 0;

  /// Applies tint, gamma, saturation, and vibrancy directly.
  const LiquidGlassColorModel.direct({
    this.saturation = 1,
    this.transmissionGamma = 1,
    this.vibrancy = 0,
  }) : _parameters = null,
       _regular = null;

  /// The iOS 27 regular material for [brightness], which follows the size
  /// of the glass: a shape draws with the model [at] its own shorter side.
  ///
  /// [transmissionGamma] bends the luminance transfer relative to Apple's
  /// face, which is `1`; above `1` the glass transmits darker.
  const LiquidGlassColorModel.ios27({
    required Brightness brightness,
    this.transmissionGamma = 1,
  }) : _parameters = null,
       _regular = brightness,
       saturation = 1,
       vibrancy = 0;

  /// iOS 27 `Glass.clear`, identical in light and dark appearance.
  const LiquidGlassColorModel.ios27Clear()
    : _parameters = GlassColorParameters.ios27Clear,
      _regular = null,
      saturation = 1,
      transmissionGamma = 1,
      vibrancy = 0;

  /// Restores a model written by [toJson] (see
  /// [GlassColorParameters.fromJson] for the parameter map).
  ///
  /// The parameter map exposes the model's internal constants. Its schema is
  /// experimental and may change between releases.
  @experimental
  factory LiquidGlassColorModel.fromJson(Object? value) => switch (value) {
    'ios27Light' => const LiquidGlassColorModel.ios27(
      brightness: Brightness.light,
    ),
    'ios27Dark' => const LiquidGlassColorModel.ios27(
      brightness: Brightness.dark,
    ),
    'ios27Clear' => const LiquidGlassColorModel.ios27Clear(),
    {'ios27Light': final Map<String, Object?> light} =>
      LiquidGlassColorModel.ios27(
        brightness: Brightness.light,
        transmissionGamma: _number(light['transmissionGamma'], 1),
      ),
    {'ios27Dark': final Map<String, Object?> dark} =>
      LiquidGlassColorModel.ios27(
        brightness: Brightness.dark,
        transmissionGamma: _number(dark['transmissionGamma'], 1),
      ),
    'direct' => const LiquidGlassColorModel.direct(),
    {'direct': final Map<String, Object?> direct} =>
      LiquidGlassColorModel.direct(
        saturation: _number(direct['saturation'], 1),
        transmissionGamma: _number(direct['transmissionGamma'], 1),
        vibrancy: _number(direct['vibrancy'], 0),
      ),
    final Map<String, Object?> map => LiquidGlassColorModel(
      GlassColorParameters.fromJson(map),
    ),
    _ => throw ArgumentError.value(value, 'colorModel'),
  };

  static double _number(Object? value, double fallback) =>
      (value as num?)?.toDouble() ?? fallback;

  final GlassColorParameters? _parameters;

  // The appearance of the regular iOS 27 material, whose constants follow
  // the size of the glass; null for every other model.
  final Brightness? _regular;

  /// The model's constants, or `null` for [LiquidGlassColorModel.direct].
  ///
  /// [LiquidGlassColorModel.ios27] has the constants of a panel here; a
  /// shape draws with those of the model [at] its size.
  GlassColorParameters? get parameters => switch (_regular) {
    null => _parameters,
    Brightness.light => GlassColorParameters.ios27Light,
    Brightness.dark => GlassColorParameters.ios27Dark,
  };

  /// The model as glass whose shorter side is [shortSide] points and whose
  /// tint is [tint] wears it.
  ///
  /// The iOS 27 models follow the size and the tint:
  /// [LiquidGlassColorModel.ios27] has the face of its size (see
  /// [GlassColorParameters.ios27Regular]), and it and
  /// [LiquidGlassColorModel.ios27Clear] tint with a grey by another law
  /// than with a color. Every other model is itself at every size. Glass up
  /// to 64 points wears one model and glass from 160 points another, so
  /// shapes that share a layer mostly share a model.
  LiquidGlassColorModel at(double shortSide, {Color? tint}) {
    final grey =
        tint != null &&
        tint.a > 0 &&
        (tint.r - tint.g).abs() < 1 / 510 &&
        (tint.g - tint.b).abs() < 1 / 510;
    final brightness = _regular;
    if (brightness == null) {
      return grey && identical(_parameters, GlassColorParameters.ios27Clear)
          ? _clearGreyTinted
          : this;
    }
    if (transmissionGamma != 1 || (shortSide > 64 && shortSide < 160)) {
      return _wornAt(shortSide, grey);
    }
    final panel = shortSide >= 160;
    return _wornModels[(brightness, panel, grey)] ??= _wornAt(
      panel ? 160 : 64,
      grey,
    );
  }

  static final _wornModels =
      <(Brightness, bool, bool), LiquidGlassColorModel>{};

  static final _clearGreyTinted = LiquidGlassColorModel(
    GlassColorParameters.ios27Clear._greyTinted,
  );

  LiquidGlassColorModel _wornAt(double shortSide, bool greyTint) =>
      LiquidGlassColorModel._worn(
        GlassColorParameters.ios27Regular(
          brightness: _regular!,
          shortSide: shortSide,
          greyTint: greyTint,
        ),
        transmissionGamma,
      );

  /// Saturation applied to transmitted backdrop content.
  ///
  /// Only the direct model reads this; the iOS 27 models carry the whole
  /// transfer in their fitted parameters, so their value is always `1`.
  final double saturation;

  /// Display-referred transfer applied to transmitted content.
  ///
  /// The direct model applies it per channel and
  /// [LiquidGlassColorModel.ios27] to its fitted luminance transfer; the
  /// other fitted models are always `1`.
  final double transmissionGamma;

  /// Backdrop-aware chroma lift.
  ///
  /// Only the direct model reads this; the iOS 27 models are always `0`.
  final double vibrancy;

  /// The model as appearance preset JSON: a preset name, a preset name mapped
  /// to the model's adjustments (`{'ios27Dark': {'transmissionGamma': g}}`, or
  /// the direct model's saturation, gamma and vibrancy), or a parameter map.
  ///
  /// The schema is experimental and may change between releases.
  @experimental
  Object toJson() => switch ((_regular, _parameters)) {
    (Brightness.light, _) => _presetJson('ios27Light'),
    (Brightness.dark, _) => _presetJson('ios27Dark'),
    (null, null) => {
      'direct': {
        'saturation': saturation,
        'transmissionGamma': transmissionGamma,
        'vibrancy': vibrancy,
      },
    },
    (null, GlassColorParameters.ios27Clear) => 'ios27Clear',
    (null, final parameters?) => parameters.toJson(),
  };

  Object _presetJson(String name) => transmissionGamma == 1
      ? name
      : {
          name: {'transmissionGamma': transmissionGamma},
        };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          other is LiquidGlassColorModel &&
          other._regular == _regular &&
          other._parameters == _parameters &&
          other.saturation == saturation &&
          other.transmissionGamma == transmissionGamma &&
          other.vibrancy == vibrancy;

  @override
  int get hashCode => Object.hash(
    _regular,
    _parameters,
    saturation,
    transmissionGamma,
    vibrancy,
  );

  @override
  String toString() =>
      'LiquidGlassColorModel(${_regular ?? _parameters}, $saturation, '
      '$transmissionGamma, $vibrancy)';
}

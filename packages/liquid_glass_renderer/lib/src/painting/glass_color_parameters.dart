import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:liquid_glass_renderer/src/painting/ios27_measures.dart';
import 'package:liquid_glass_renderer/src/painting/shader_constants.dart';

/// A curve over the Liquid Glass slider position.
///
/// The endpoints sit at Clear (`0`) and Tinted (`1`). A curve of two values
/// is the line between them; one [GlassColorCurve.through] more values bends
/// at each of them.
@internal
@immutable
final class GlassColorCurve {
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
  factory GlassColorCurve.sampled(
    double Function(double sliderPosition) value,
  ) => GlassColorCurve.through([for (var i = 0; i <= 20; i++) value(i / 20)]);

  /// Value at the Clear slider position (`0`).
  final double clear;

  /// Value at the Tinted slider position (`1`).
  final double tinted;

  final List<double>? _values;

  /// The value at [sliderPosition].
  double evaluate(double sliderPosition) {
    final amount = sliderPosition.clamp(0.0, 1.0);
    final values = _values;
    if (values == null) return clear + (tinted - clear) * amount;
    final at = amount * (values.length - 1);
    final below = math.min(at.floor(), values.length - 2);
    return values[below] + (values[below + 1] - values[below]) * (at - below);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
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
@internal
@immutable
final class GlassColorBleed {
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
  double weightAt(double face) {
    final weight = (onBright ? face : 1 - face).clamp(0.0, 1.0);
    return opacity * weight * weight * weight * weight;
  }

  /// A grey face of luminance [face] over a grey backdrop of luminance
  /// [backdrop], after the bleed.
  double apply(double face, double backdrop) =>
      face + (black + (white - black) * backdrop - face) * weightAt(face);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
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

/// One bound of a tint's tone over the luminance of the face the tint
/// covers, `base + amplitude * luminance`.
@internal
@immutable
final class GlassToneRamp {
  /// A bound that is [base] over a black face and [base] plus [amplitude]
  /// over a white one.
  const GlassToneRamp({required this.base, required this.amplitude});

  /// The bound over a black face.
  final double base;

  /// How much the bound gains from a black face to a white one.
  final double amplitude;

  /// The bound over a face of [luminance], which is taken within 0 and 1.
  double evaluate(double luminance) =>
      base + amplitude * luminance.clamp(0.0, 1.0);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GlassToneRamp &&
          other.base == base &&
          other.amplitude == amplitude;

  @override
  int get hashCode => Object.hash(base, amplitude);

  @override
  String toString() => 'GlassToneRamp($base, $amplitude)';
}

/// Every numeric constant of the adaptive (backdrop-conditioned) color
/// model, driven from Dart and consumed by the final render shader as a
/// uniform block.
///
/// The untinted face of a shape is
/// `emission + transmittance * lum(Y) + chromaGain * keep(k) *
/// (backdrop - Y)` with `lum(Y) = Y + lift * Y * (1 - Y)`,
/// `k = 1 - Y * lift / (1 + lift)` and `keep(k) = k * (1 + 0.3 * (1 - k))`;
/// `emission` is premultiplied. This is the face of iOS 27 in other terms:
/// the lift is its cap on luminance, and the chroma falls with that cap as
/// iOS's does. [bleed] then veils the face. A tint then covers the face by
/// its opacity with a tone picked by the luminance `F` of the face: each
/// tint channel `c` becomes `clamp(lo + (hi - lo) * c)` where `lo` and `hi`
/// are [GlassToneRamp]s of `F`.
///
/// The iOS 27 parameter sets are [GlassColorParameters.ios27Regular], which
/// follows the size of the glass, and [GlassColorParameters.ios27Clear].
@internal
@immutable
final class GlassColorParameters {
  /// Creates a fully specified adaptive color parameter set.
  const GlassColorParameters({
    required this.emissionAlpha,
    required this.transmittance,
    required this.luminanceLift,
    required this.chromaGain,
    required this.toneLow,
    required this.toneHigh,
    this.bleed = const GlassColorBleed.none(),
    this.glintLuminance = _defaultGlintLuminance,
    this.glintFaceGain = _defaultGlintFaceGain,
    this.glintVibrancy = _defaultGlintVibrancy,
    this.contourResponse = 0,
    this.fakeGlintLuminance = _defaultGlintLuminance,
  });

  /// The parameters of `LiquidGlassColorModel.ios27Regular` in [brightness]
  /// for glass whose shorter side is [shortSide] points: a control's up to
  /// the `control` of [ios27SizeRamp], a panel's from its `panel`, every
  /// part grown linearly between the two. [greyTint] gives the parameters
  /// of glass tinted with a grey, which iOS tints by another law than with
  /// a color.
  factory GlassColorParameters.ios27Regular({
    required Brightness brightness,
    required double shortSide,
    required bool greyTint,
  }) {
    final dark = brightness == Brightness.dark;
    final (:control, :panel) = ios27SizeRamp;
    final parameters = shortSide <= control
        ? (dark ? _ios27DarkControl : _ios27LightControl)
        : shortSide >= panel
        ? (dark ? _ios27DarkPanel : _ios27LightPanel)
        : _ios27Regular(dark, shortSide);
    return greyTint ? parameters.greyTinted : parameters;
  }

  /// The strength of the face's white emission over the slider.
  final GlassColorCurve emissionAlpha;

  /// Transmittance of transmitted content over the slider.
  final GlassColorCurve transmittance;

  /// S-curve lift applied to transmitted luminance.
  final GlassColorCurve luminanceLift;

  /// Gain applied to the transmitted chroma.
  final GlassColorCurve chromaGain;

  /// The veil over the face of glass larger than a control.
  final GlassColorBleed bleed;

  /// The tone a black channel of a tint takes, over the luminance of the
  /// face.
  final GlassToneRamp toneLow;

  /// The tone a white channel of a tint takes, over the luminance of the
  /// face.
  final GlassToneRamp toneHigh;

  /// Luminance of the glint's bright target (real glass: HDR-capable).
  final double glintLuminance;

  /// How much of the lit face is added to the glint target. Clear glass
  /// brightens its own face instead of pulling toward fixed white.
  final double glintFaceGain;

  /// How much the glint amplifies face chroma.
  final double glintVibrancy;

  /// How strongly the slider's added opacity strengthens the dark contour.
  /// `1 + contourResponse * (T(0) - T(sliderPosition))` scales the contour
  /// alpha.
  final double contourResponse;

  /// Luminance of the glint target FakeGlass composites, which cannot see
  /// the face.
  final double fakeGlintLuminance;

  static const double _defaultGlintLuminance = GlassGlint.directLuminance;
  static const double _defaultGlintFaceGain = 0;
  static const double _defaultGlintVibrancy = GlassGlint.directVibrancy;

  // The shorter side, in points, from which dark glass keeps its least
  // fraction of the backdrop's luminance.
  static const double _ios27DarkCapSide = 104;

  static GlassColorParameters _ios27Regular(bool dark, double shortSide) {
    final grown = ios27PanelProgress(shortSide);
    final control = ios27SizeRamp.control;
    final black = dark ? 0.125 : 0.4;
    final white = dark ? 1.125 : 1.03;
    final saturation = dark ? 1.3 : 1.2;
    // The fill over the face: its grey and how much of the face it covers.
    double fillGrey(double amount) => dark ? 0.125 * (1 - 2 * amount).abs() : 1;
    double fill(double amount) {
      final (:upTo, :past) = splitAtMiddleTick(amount);
      return dark ? past : 0.4 * upTo + 0.6 * past;
    }

    double whiteKeeps(double amount) => dark
        ? 0.6 +
              (0.45 - 0.2 * splitAtMiddleTick(amount).upTo - 0.6) *
                  ((shortSide - control) / (_ios27DarkCapSide - control)).clamp(
                    0.0,
                    1.0,
                  )
        : ios27LightLuminanceCap;
    final base = dark ? _ios27DarkTones : _ios27LightTones;
    return base.copyWith(
      emissionAlpha: GlassColorCurve.sampled(
        (a) => black * (1 - fill(a)) + fillGrey(a) * fill(a),
      ),
      transmittance: GlassColorCurve.sampled(
        (a) => (white - black) * (1 - fill(a)) * whiteKeeps(a),
      ),
      luminanceLift: GlassColorCurve.sampled(
        (a) => (1 - whiteKeeps(a)) / whiteKeeps(a),
      ),
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

  /// The fraction of a white backdrop's luminance light glass keeps before its
  /// own white point brightens it.
  ///
  /// iOS takes 1 on a display with headroom over white, which an iPhone
  /// has, and 0.94 on one without, such as the simulator's: there the
  /// brightest greys under light glass come out up to five levels darker.
  static const double ios27LightLuminanceCap = 1;

  // What the size and the slider do not set: the tones of a tint.
  static const _ios27LightTones = GlassColorParameters(
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
  );
  static const _lightToneHigh = GlassToneRamp(
    base: .6,
    amplitude: .4,
  );

  // On dark glass it is 1.0362 c - 0.0306 over a black face and
  // 0.7946 c + 0.1735 over a white one.
  static const _ios27DarkTones = GlassColorParameters(
    emissionAlpha: GlassColorCurve.constant(0),
    transmittance: GlassColorCurve.constant(1),
    luminanceLift: GlassColorCurve.constant(0),
    chromaGain: GlassColorCurve.constant(1),
    toneLow: GlassToneRamp(
      base: -.0306,
      amplitude: .2041,
    ),
    toneHigh: GlassToneRamp(
      base: 1.0056,
      amplitude: -.0375,
    ),
    contourResponse: .95,
  );

  /// These parameters under a grey tint: a grey g of a tint is
  /// 1.1875 g - 0.25 over a black face and 0.3125 more over a white one, in
  /// both appearances and on clear glass.
  GlassColorParameters get greyTinted => copyWith(
    toneLow: const GlassToneRamp(
      base: -.25,
      amplitude: .3125,
    ),
    toneHigh: const GlassToneRamp(
      base: .9375,
      amplitude: .3125,
    ),
  );

  static final _ios27LightControl = _ios27Regular(
    false,
    ios27SizeRamp.control,
  );
  static final _ios27DarkControl = _ios27Regular(true, ios27SizeRamp.control);

  static final _ios27LightPanel = _ios27Regular(false, ios27SizeRamp.panel);
  static final _ios27DarkPanel = _ios27Regular(true, ios27SizeRamp.panel);

  /// The parameters of `LiquidGlassColorModel.ios27Clear`, the same in light
  /// and dark and at every size and slider position.
  static const ios27Clear = GlassColorParameters(
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

  /// A copy with the given fields replaced.
  GlassColorParameters copyWith({
    GlassColorCurve? emissionAlpha,
    GlassColorCurve? transmittance,
    GlassColorCurve? luminanceLift,
    GlassColorCurve? chromaGain,
    GlassColorBleed? bleed,
    GlassToneRamp? toneLow,
    GlassToneRamp? toneHigh,
  }) => GlassColorParameters(
    emissionAlpha: emissionAlpha ?? this.emissionAlpha,
    transmittance: transmittance ?? this.transmittance,
    luminanceLift: luminanceLift ?? this.luminanceLift,
    chromaGain: chromaGain ?? this.chromaGain,
    bleed: bleed ?? this.bleed,
    toneLow: toneLow ?? this.toneLow,
    toneHigh: toneHigh ?? this.toneHigh,
    glintLuminance: glintLuminance,
    glintFaceGain: glintFaceGain,
    glintVibrancy: glintVibrancy,
    contourResponse: contourResponse,
    fakeGlintLuminance: fakeGlintLuminance,
  );

  /// The untinted face under [bleed], as the class describes it, at
  /// [sliderPosition]; `emission` is premultiplied.
  ({Color emission, double transmittance, double lift, double chromaGain})
  faceTransfer({required double sliderPosition}) {
    final alpha = emissionAlpha.evaluate(sliderPosition);
    return (
      emission: Color.from(alpha: 1, red: alpha, green: alpha, blue: alpha),
      transmittance: transmittance.evaluate(sliderPosition),
      lift: luminanceLift.evaluate(sliderPosition),
      chromaGain: chromaGain.evaluate(sliderPosition),
    );
  }

  /// Factor applied to the border strength at slider [sliderPosition].
  double contourScale(double sliderPosition) =>
      1 +
      contourResponse *
          (transmittance.evaluate(0) - transmittance.evaluate(sliderPosition));

  /// Maps one opaque tint channel triple to the tone selected for a face of
  /// [luminance].
  Color tintTone(Color tint, double luminance) {
    final lo = toneLow.evaluate(luminance);
    final hi = toneHigh.evaluate(luminance);
    double channel(double c) =>
        (lo + (hi - lo) * math.max(c, 0.0)).clamp(0.0, 1.0);
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
      other is GlassColorParameters &&
          other.emissionAlpha == emissionAlpha &&
          other.transmittance == transmittance &&
          other.luminanceLift == luminanceLift &&
          other.chromaGain == chromaGain &&
          other.bleed == bleed &&
          other.toneLow == toneLow &&
          other.toneHigh == toneHigh &&
          other.glintLuminance == glintLuminance &&
          other.glintFaceGain == glintFaceGain &&
          other.glintVibrancy == glintVibrancy &&
          other.contourResponse == contourResponse &&
          other.fakeGlintLuminance == fakeGlintLuminance;

  @override
  int get hashCode => Object.hash(
    emissionAlpha,
    transmittance,
    luminanceLift,
    chromaGain,
    bleed,
    toneLow,
    toneHigh,
    glintLuminance,
    glintFaceGain,
    glintVibrancy,
    contourResponse,
    fakeGlintLuminance,
  );

  @override
  String toString() =>
      'GlassColorParameters($emissionAlpha, $transmittance, '
      '$luminanceLift, $chromaGain, $bleed, $toneLow, $toneHigh, '
      '$glintLuminance, $glintFaceGain, $glintVibrancy, $contourResponse, '
      '$fakeGlintLuminance)';
}

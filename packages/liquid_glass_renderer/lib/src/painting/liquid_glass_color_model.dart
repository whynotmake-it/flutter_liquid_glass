import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:liquid_glass_renderer/src/painting/glass_color_parameters.dart';
import 'package:liquid_glass_renderer/src/painting/ios27_measures.dart';
import 'package:liquid_glass_renderer/src/painting/shader_constants.dart';

/// Flutter's 4x5 color matrix that sets [saturation] on the luminance glass
/// shades by ([lumaWeights]), then scales each color channel by [gain],
/// adds [bias] (a fraction of full intensity) and takes [alpha] as the alpha.
@internal
List<double> saturationMatrix(
  double saturation, {
  double gain = 1,
  double bias = 0,
  double alpha = 1,
}) {
  final (lr, lg, lb) = lumaWeights;
  final s = saturation;
  final o = bias * 255;
  double at(double weight, {bool own = false}) =>
      (weight * (1 - s) + (own ? s : 0)) * gain;
  return [
    at(lr, own: true), at(lg), at(lb), 0, o, //
    at(lr), at(lg, own: true), at(lb), 0, o, //
    at(lr), at(lg), at(lb, own: true), 0, o, //
    0, 0, 0, alpha, 0,
  ];
}

/// How glass combines its tint with the backdrop it shows through.
///
/// A model is either the direct one ([LiquidGlassColorModel.direct]), which
/// applies saturation, gamma and vibrancy per channel and adds no material
/// of its own, or one fitted to iOS 27 glass:
/// [LiquidGlassColorModel.ios27Regular], whose face follows the size of the
/// shape that wears it, and [LiquidGlassColorModel.ios27Clear].
///
/// iOS gives glass a material by the shorter side of its shape. Up to 64
/// points regular glass is a control's: light glass lifts black to 40 %,
/// dark glass to 12.5 % and keeps 60 % of the backdrop's luminance. From 160
/// points it is a panel's: a veil pulls the bright parts of light glass
/// toward white and the dark parts of dark glass toward a dim grey, and dark
/// glass keeps 45 % of the luminance. Between the two every part grows
/// linearly; dark glass reaches its cap on luminance at 104 points. Each
/// shape resolves this for itself, so shapes that share a layer do not
/// change each other's look.
@immutable
sealed class LiquidGlassColorModel {
  const LiquidGlassColorModel._();

  /// Applies the tint, [saturation], [transmissionGamma] and [vibrancy]
  /// directly, per channel, with no response to the backdrop or to the size
  /// of the glass.
  const factory LiquidGlassColorModel.direct({
    double saturation,
    double transmissionGamma,
    double vibrancy,
  }) = LiquidGlassDirectColorModel._;

  /// The iOS 27 regular material (`Glass.regular`) in [brightness], which
  /// follows the size of the glass and the Liquid Glass slider.
  ///
  /// Along the slider a fill covers more of the face: white on light glass,
  /// grey on dark glass. A tint runs from a darker tone of itself over a
  /// black face to itself over a white one on light glass, and between two
  /// tones close to itself on dark glass; a grey tint follows another law
  /// than a color.
  ///
  /// The numbers are the inputs UIKit gives its glass on iOS 27, and the
  /// face they give agrees with captures of native glass over plain colors
  /// within a level out of 255. Approximation: the tones of a color are
  /// exact for fully saturated colors and up to 0.12 off the darker tone of
  /// a pale one.
  ///
  /// [transmissionGamma] bends the luminance transfer relative to Apple's
  /// face, which is `1`; above `1` the glass transmits darker.
  const factory LiquidGlassColorModel.ios27Regular({
    required Brightness brightness,
    double transmissionGamma,
  }) = LiquidGlassIos27RegularColorModel._;

  /// iOS 27 `Glass.clear`, identical in light and dark appearance and at
  /// every size and slider position.
  ///
  /// Clear glass lifts black to 12.5 %, takes white to 108 % and passes
  /// chroma through at 1.06: the inputs UIKit gives it on iOS 27. It takes
  /// the tint tones of light glass in both appearances, and its glint
  /// brightens its own face rather than pulling toward a fixed bright
  /// target.
  const factory LiquidGlassColorModel.ios27Clear() =
      LiquidGlassIos27ClearColorModel._;
}

/// The [LiquidGlassColorModel] that applies its numbers directly
/// ([LiquidGlassColorModel.direct]).
final class LiquidGlassDirectColorModel extends LiquidGlassColorModel {
  const LiquidGlassDirectColorModel._({
    this.saturation = 1,
    this.transmissionGamma = 1,
    this.vibrancy = 0,
  }) : super._();

  /// Saturation applied to transmitted backdrop content.
  final double saturation;

  /// Display-referred transfer applied per channel to transmitted content.
  final double transmissionGamma;

  /// Backdrop-aware chroma lift.
  final double vibrancy;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiquidGlassDirectColorModel &&
          other.saturation == saturation &&
          other.transmissionGamma == transmissionGamma &&
          other.vibrancy == vibrancy;

  @override
  int get hashCode => Object.hash(saturation, transmissionGamma, vibrancy);

  @override
  String toString() =>
      'LiquidGlassColorModel.direct(saturation: $saturation, '
      'transmissionGamma: $transmissionGamma, vibrancy: $vibrancy)';
}

/// The [LiquidGlassColorModel] of iOS 27 regular glass
/// ([LiquidGlassColorModel.ios27Regular]).
final class LiquidGlassIos27RegularColorModel extends LiquidGlassColorModel {
  const LiquidGlassIos27RegularColorModel._({
    required this.brightness,
    this.transmissionGamma = 1,
  }) : super._();

  /// The colour scheme of the glass.
  final Brightness brightness;

  /// The bend of the fitted luminance transfer; `1` is Apple's face.
  final double transmissionGamma;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LiquidGlassIos27RegularColorModel &&
          other.brightness == brightness &&
          other.transmissionGamma == transmissionGamma;

  @override
  int get hashCode => Object.hash(brightness, transmissionGamma);

  @override
  String toString() =>
      'LiquidGlassColorModel.ios27Regular(brightness: $brightness, '
      'transmissionGamma: $transmissionGamma)';
}

/// The [LiquidGlassColorModel] of iOS 27 clear glass
/// ([LiquidGlassColorModel.ios27Clear]).
final class LiquidGlassIos27ClearColorModel extends LiquidGlassColorModel {
  const LiquidGlassIos27ClearColorModel._() : super._();

  @override
  bool operator ==(Object other) => other is LiquidGlassIos27ClearColorModel;

  @override
  int get hashCode => (LiquidGlassIos27ClearColorModel).hashCode;

  @override
  String toString() => 'LiquidGlassColorModel.ios27Clear()';
}

/// A [LiquidGlassColorModel] as glass of one size and tint wears it
/// ([WearColorModel.wornAt]): the constants the shaders take.
@internal
@immutable
final class WornColorModel {
  /// The direct model of these numbers.
  const WornColorModel.direct({
    this.saturation = 1,
    this.transmissionGamma = 1,
    this.vibrancy = 0,
  }) : parameters = null;

  /// A backdrop-adaptive model of [parameters], which carry the whole
  /// transfer but for [transmissionGamma].
  const WornColorModel.fitted(
    GlassColorParameters this.parameters, {
    this.transmissionGamma = 1,
  }) : saturation = 1,
       vibrancy = 0;

  /// The fitted model's constants, or null for the direct model.
  final GlassColorParameters? parameters;

  /// Saturation applied to transmitted backdrop content; `1` for a fitted
  /// model.
  final double saturation;

  /// Display-referred transfer applied to transmitted content: per channel
  /// by the direct model, to the luminance transfer by a fitted one.
  final double transmissionGamma;

  /// Backdrop-aware chroma lift; `0` for a fitted model.
  final double vibrancy;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WornColorModel &&
          other.parameters == parameters &&
          other.saturation == saturation &&
          other.transmissionGamma == transmissionGamma &&
          other.vibrancy == vibrancy;

  @override
  int get hashCode =>
      Object.hash(parameters, saturation, transmissionGamma, vibrancy);

  @override
  String toString() =>
      'WornColorModel($parameters, $saturation, $transmissionGamma, '
      '$vibrancy)';
}

/// Wears a color model at a size.
@internal
extension WearColorModel on LiquidGlassColorModel {
  /// The model as glass whose shorter side is [shortSide] points and whose
  /// tint is [tint] wears it.
  ///
  /// The regular iOS 27 model has the face of its size
  /// ([GlassColorParameters.ios27Regular]), and it and the clear one tint
  /// with a grey by another law than with a color. Glass up to 64 points
  /// wears one model and glass from 160 points another, so shapes that share
  /// a layer mostly share a model.
  WornColorModel wornAt(double shortSide, {Color? tint}) {
    final grey =
        tint != null &&
        tint.a > 0 &&
        (tint.r - tint.g).abs() < 1 / 510 &&
        (tint.g - tint.b).abs() < 1 / 510;
    switch (this) {
      case LiquidGlassDirectColorModel(
        :final saturation,
        :final transmissionGamma,
        :final vibrancy,
      ):
        return saturation == 1 && transmissionGamma == 1 && vibrancy == 0
            ? _plainDirect
            : WornColorModel.direct(
                saturation: saturation,
                transmissionGamma: transmissionGamma,
                vibrancy: vibrancy,
              );
      case LiquidGlassIos27ClearColorModel():
        return grey ? _clearGreyTinted : _clear;
      case LiquidGlassIos27RegularColorModel(
        :final brightness,
        :final transmissionGamma,
      ):
        WornColorModel at(double side) => WornColorModel.fitted(
          GlassColorParameters.ios27Regular(
            brightness: brightness,
            shortSide: side,
            greyTint: grey,
          ),
          transmissionGamma: transmissionGamma,
        );
        final (:control, :panel) = ios27SizeRamp;
        if (transmissionGamma != 1 ||
            (shortSide > control && shortSide < panel)) {
          return at(shortSide);
        }
        final isPanel = shortSide >= panel;
        return _wornModels[(brightness, isPanel, grey)] ??= at(
          isPanel ? panel : control,
        );
    }
  }

  static const _plainDirect = WornColorModel.direct();

  static const _clear = WornColorModel.fitted(GlassColorParameters.ios27Clear);

  static final _clearGreyTinted = WornColorModel.fitted(
    GlassColorParameters.ios27Clear.greyTinted,
  );

  static final _wornModels = <(Brightness, bool, bool), WornColorModel>{};
}

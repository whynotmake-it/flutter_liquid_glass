import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_color_model.dart';

/// Lightweight color and materialization controls for one glass shape.
///
/// Optical geometry and surface lighting belong to the containing
/// `LiquidGlassLayer`. These values may vary between shapes without requiring
/// another backdrop capture.
class LiquidGlassAppearance with Equatable {
  /// Creates a per-shape glass appearance.
  const LiquidGlassAppearance({
    this.tint = const Color.fromARGB(0, 255, 255, 255),
    this.saturation = 1,
    this.transmissionGamma = 1,
    this.vibrancy = 0,
    this.visibility = 1,
    this.colorModel = const LiquidGlassColorModel.direct(),
  });

  /// Restores an appearance produced by [toJson].
  factory LiquidGlassAppearance.fromJson(Map<String, Object?> json) {
    double number(String key, double fallback) =>
        (json[key] as num?)?.toDouble() ?? fallback;
    final tint = json['tint'];
    final colorModel = LiquidGlassColorModel.fromJson(json['colorModel']);
    return LiquidGlassAppearance(
      tint: tint is num ? Color(tint.toInt()) : const Color(0x00FFFFFF),
      saturation: number('saturation', 1),
      transmissionGamma: number('transmissionGamma', 1),
      vibrancy: number('vibrancy', 0),
      visibility: number('visibility', 1),
      colorModel: colorModel,
    );
  }

  /// The fitted light iOS 27 regular-material appearance.
  const LiquidGlassAppearance.ios27RegularLight({
    this.tint = const Color(0x00007AFF),
    this.visibility = 1,
  }) : saturation = 1.65,
       transmissionGamma = 1.3,
       vibrancy = 0.15,
       colorModel = const LiquidGlassColorModel.ios27(
         brightness: Brightness.light,
       );

  /// The fitted dark iOS 27 regular-material appearance.
  const LiquidGlassAppearance.ios27RegularDark({
    this.tint = const Color(0x00007AFF),
    this.visibility = 1,
  }) : saturation = 2.6,
       transmissionGamma = 0.58,
       vibrancy = 0.1,
       colorModel = const LiquidGlassColorModel.ios27(
         brightness: Brightness.dark,
       );

  /// Creates the fitted iOS 27 regular material for [brightness].
  factory LiquidGlassAppearance.ios27Regular({
    required Brightness brightness,
    Color tint = const Color(0x00007AFF),
    double visibility = 1,
  }) => brightness == Brightness.dark
      ? LiquidGlassAppearance.ios27RegularDark(
          tint: tint,
          visibility: visibility,
        )
      : LiquidGlassAppearance.ios27RegularLight(
          tint: tint,
          visibility: visibility,
        );

  /// The fitted light iOS 27 toolbar appearance.
  const LiquidGlassAppearance.ios27ToolbarLight({
    this.tint = const Color(0x00007AFF),
    this.visibility = 1,
  }) : saturation = 0.9,
       transmissionGamma = 0.9,
       vibrancy = 0.15,
       colorModel = const LiquidGlassColorModel.ios27(
         brightness: Brightness.light,
       );

  /// The fitted dark iOS 27 toolbar appearance.
  const LiquidGlassAppearance.ios27ToolbarDark({
    this.tint = const Color(0x00007AFF),
    this.visibility = 1,
  }) : saturation = 2.6,
       transmissionGamma = 0.58,
       vibrancy = 0.1,
       colorModel = const LiquidGlassColorModel.ios27(
         brightness: Brightness.dark,
       );

  /// Creates the fitted iOS 27 toolbar appearance for [brightness].
  factory LiquidGlassAppearance.ios27Toolbar({
    required Brightness brightness,
    Color tint = const Color(0x00007AFF),
    double visibility = 1,
  }) => brightness == Brightness.dark
      ? LiquidGlassAppearance.ios27ToolbarDark(
          tint: tint,
          visibility: visibility,
        )
      : LiquidGlassAppearance.ios27ToolbarLight(
          tint: tint,
          visibility: visibility,
        );

  /// Material tint; alpha controls how strongly it mixes with the backdrop.
  final Color tint;

  /// Saturation applied to transmitted backdrop content.
  final double saturation;

  /// Display-referred transfer applied to transmitted content.
  final double transmissionGamma;

  /// Backdrop-aware chroma lift.
  final double vibrancy;

  /// Shape materialization progress, conventionally from zero to one.
  final double visibility;

  /// The transfer model used to combine [tint] with the backdrop.
  ///
  /// The iOS 27 models derive the accompanying tonal response automatically;
  /// use [LiquidGlassColorModel.direct] with the other fields for unrestricted
  /// manual control.
  final LiquidGlassColorModel colorModel;

  /// Returns a copy with the supplied appearance controls replaced.
  LiquidGlassAppearance copyWith({
    Color? tint,
    double? saturation,
    double? transmissionGamma,
    double? vibrancy,
    double? visibility,
    LiquidGlassColorModel? colorModel,
  }) => LiquidGlassAppearance(
    tint: tint ?? this.tint,
    saturation: saturation ?? this.saturation,
    transmissionGamma: transmissionGamma ?? this.transmissionGamma,
    vibrancy: vibrancy ?? this.vibrancy,
    visibility: visibility ?? this.visibility,
    colorModel: colorModel ?? this.colorModel,
  );

  /// Serializes this lightweight appearance for presets and tooling.
  Map<String, Object> toJson() => {
    'tint': tint.toARGB32(),
    'saturation': saturation,
    'transmissionGamma': transmissionGamma,
    'vibrancy': vibrancy,
    'visibility': visibility,
    'colorModel': colorModel.toJson(),
  };

  @override
  List<Object?> get props => [
    tint,
    saturation,
    transmissionGamma,
    vibrancy,
    visibility,
    colorModel,
  ];
}

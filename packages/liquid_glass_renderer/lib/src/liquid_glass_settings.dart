import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_render_scope.dart';

/// Material parameters for the liquid-glass compositor.
///
/// The public surface follows the observable Apple material axes: one optical
/// profile, one transmission/tint axis, one highlight lobe, and one dielectric
/// contour. The renderer derives the paired edge highlights and the dark
/// silhouette from the same SDF, so these controls remain stable across the
/// toolbar, capsule, tab, and loupe scenes.
class LiquidGlassSettings with Equatable {
  const LiquidGlassSettings({
    this.visibility = 1.0,
    this.tint = const Color.fromARGB(0, 255, 255, 255),
    this.thickness = 20.0,
    this.edgeRefraction = 106.13,
    this.refractionSpread = 0.0,
    this.frost = 5.0,
    this.chromaticAberration = 0.01,
    this.saturation = 1.5,
    this.transmissionGamma = 1.0,
    this.vibrancy = 0.0,
    this.highlight = 1.0,
    this.contourStrength = 0.0,
    this.contourWidth = 0.0,
  });

  /// Scoped fit for the iOS 27 light toolbar capsule reference.
  const LiquidGlassSettings.ios27ToolbarLight({
    this.visibility = 1.0,
    this.frost = 7.0,
  }) : tint = const Color.from(
         alpha: 0.53,
         red: 253 / 255,
         green: 252 / 255,
         blue: 253 / 255,
       ),
       thickness = 12.0,
       edgeRefraction = 27.42,
       refractionSpread = 0.0,
       chromaticAberration = 0.005,
       saturation = 0.9,
       transmissionGamma = 0.9,
       vibrancy = 0.15,
       highlight = 0.5,
       contourStrength = 0.1,
       contourWidth = 1.0;

  /// Figma's percentage-based constructor mapped onto the unified axes.
  LiquidGlassSettings.figma({
    required double refraction,
    required double depth,
    required double dispersion,
    required double frost,
    double visibility = 1.0,
    Color tint = const Color.fromARGB(0, 255, 255, 255),
  }) : this(
         visibility: visibility,
         edgeRefraction: (refraction / 100) * 106.13,
         thickness: depth,
         refractionSpread: 0.0,
         chromaticAberration: 4 * (dispersion / 100),
         frost: frost,
         saturation: 1.5,
         tint: tint,
       );

  static LiquidGlassSettings of(BuildContext context) {
    return LiquidGlassRenderScope.of(context).settings;
  }

  /// Transition multiplier used by the compositing layer.
  ///
  /// This is an API transition utility, not a material-fit axis; it has no
  /// scene-specific looks claim.
  final double visibility;

  /// Unified material tint. Alpha is the material's opacity/transmission axis.
  ///
  /// Evidence scope: toolbar, small capsule, and tab-bar holdout.
  final Color tint;

  /// Optical profile depth in logical pixels.
  ///
  /// Evidence scope: toolbar plus small and large capsule fits.
  final double thickness;

  /// Peak edge displacement in logical pixels at the optical rim. The
  /// renderer solves the internal optical index from this value.
  ///
  /// Evidence scope: toolbar plus small and large capsule fits.
  final double edgeRefraction;

  /// Face reach of the SDF optical profile. `0` keeps the optical slope at the
  /// physical edge thickness; `1` carries the eased slope across the full
  /// face. This is a profile/refractive-field control, not a backdrop zoom.
  ///
  /// Evidence scope: toolbar, small capsule, and tab-bar holdout; it must not
  /// be used as a loupe magnification control.
  final double refractionSpread;

  /// Backdrop frost/softening radius.
  ///
  /// Evidence scope: toolbar and small capsule, with size normalization
  /// derived internally for smaller controls.
  final double frost;

  /// Wavelength separation for the edge displacement.
  ///
  /// Evidence scope: toolbar plus at least one capsule or holdout before this
  /// axis is treated as a stable public control.
  final double chromaticAberration;

  /// Saturation applied to transmitted backdrop content.
  ///
  /// Evidence scope: toolbar plus capsule or holdout.
  final double saturation;

  /// Display-referred transfer applied to transmitted content.
  ///
  /// Evidence scope: toolbar plus capsule or holdout.
  final double transmissionGamma;

  /// Backdrop-aware chroma lift.
  ///
  /// Evidence scope: toolbar plus capsule or holdout.
  final double vibrancy;

  /// Strength of the paired directional highlight lobe.
  ///
  /// Evidence scope: black/white toolbar plus capsule.
  final double highlight;

  /// Strength of the dark dielectric contour derived from the SDF.
  ///
  /// Evidence scope: white-background toolbar plus capsule.
  final double contourStrength;

  /// Width of the dielectric contour in logical pixels.
  ///
  /// Evidence scope: white-background toolbar plus capsule.
  final double contourWidth;

  Color get effectiveTint => tint.withValues(alpha: tint.a * visibility);
  double get effectiveThickness => thickness * visibility;
  double get effectiveEdgeRefraction => edgeRefraction * visibility;
  double get effectiveRefractionSpread => refractionSpread * visibility;
  double get effectiveFrost => frost * visibility;
  double get effectiveChromaticAberration => chromaticAberration * visibility;
  double get effectiveSaturation => 1 + (saturation - 1) * visibility;
  double get effectiveTransmissionGamma =>
      1 + (transmissionGamma - 1) * visibility;
  double get effectiveVibrancy => vibrancy * visibility;
  double get effectiveHighlight => highlight * visibility;
  double get effectiveContourStrength => contourStrength * visibility;
  double get effectiveContourWidth => contourWidth * visibility;

  /// Internal optical index derived from the public peak displacement. The
  /// public value remains observable and comparable across sizes.
  double get effectiveOpticalIndex {
    final depth = effectiveThickness;
    if (depth <= 0 || effectiveEdgeRefraction <= 0) return 1.0;
    final ratio = effectiveEdgeRefraction / (8.0 * depth);
    return math.sqrt(1.0 + ratio * ratio);
  }

  /// Shared displacement codec scale for the geometry and final passes. The
  /// public edge value is the analytic peak of the profile; using it directly
  /// avoids wasting RGBA8 codes on unreachable displacement range.
  double get effectiveDisplacementScale =>
      math.max(1e-3, 1.05 * effectiveEdgeRefraction);

  LiquidGlassSettings copyWith({
    double? visibility,
    Color? tint,
    double? thickness,
    double? edgeRefraction,
    double? refractionSpread,
    double? frost,
    double? chromaticAberration,
    double? saturation,
    double? transmissionGamma,
    double? vibrancy,
    double? highlight,
    double? contourStrength,
    double? contourWidth,
  }) => LiquidGlassSettings(
    visibility: visibility ?? this.visibility,
    tint: tint ?? this.tint,
    thickness: thickness ?? this.thickness,
    edgeRefraction: edgeRefraction ?? this.edgeRefraction,
    refractionSpread: refractionSpread ?? this.refractionSpread,
    frost: frost ?? this.frost,
    chromaticAberration: chromaticAberration ?? this.chromaticAberration,
    saturation: saturation ?? this.saturation,
    transmissionGamma: transmissionGamma ?? this.transmissionGamma,
    vibrancy: vibrancy ?? this.vibrancy,
    highlight: highlight ?? this.highlight,
    contourStrength: contourStrength ?? this.contourStrength,
    contourWidth: contourWidth ?? this.contourWidth,
  );

  /// Serializes the public material vector for example presets and tooling.
  Map<String, Object> toJson() => {
    'visibility': visibility,
    'tint': tint.value,
    'thickness': thickness,
    'edgeRefraction': edgeRefraction,
    'refractionSpread': refractionSpread,
    'frost': frost,
    'chromaticAberration': chromaticAberration,
    'saturation': saturation,
    'transmissionGamma': transmissionGamma,
    'vibrancy': vibrancy,
    'highlight': highlight,
    'contourStrength': contourStrength,
    'contourWidth': contourWidth,
  };

  /// Restores a material vector produced by [toJson].
  factory LiquidGlassSettings.fromJson(Map<String, Object?> json) {
    double number(String key, double fallback) =>
        (json[key] as num?)?.toDouble() ?? fallback;
    final tintValue = json['tint'];
    final tint = tintValue is num
        ? Color(tintValue.toInt())
        : const Color.fromARGB(0, 255, 255, 255);
    return LiquidGlassSettings(
      visibility: number('visibility', 1),
      tint: tint,
      thickness: number('thickness', 20),
      edgeRefraction: number('edgeRefraction', 106.13),
      refractionSpread: number('refractionSpread', 0),
      frost: number('frost', 5),
      chromaticAberration: number('chromaticAberration', .01),
      saturation: number('saturation', 1.5),
      transmissionGamma: number('transmissionGamma', 1),
      vibrancy: number('vibrancy', 0),
      highlight: number('highlight', 1),
      contourStrength: number('contourStrength', 0),
      contourWidth: number('contourWidth', 0),
    );
  }

  @override
  List<Object?> get props => [
    visibility,
    tint,
    thickness,
    edgeRefraction,
    refractionSpread,
    frost,
    chromaticAberration,
    saturation,
    transmissionGamma,
    vibrancy,
    highlight,
    contourStrength,
    contourWidth,
  ];
}

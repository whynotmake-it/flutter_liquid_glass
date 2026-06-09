import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_render_scope.dart';

/// Represents the settings for a liquid glass effect.
class LiquidGlassSettings with EquatableMixin {
  /// Creates a new [LiquidGlassSettings] with the given settings.
  const LiquidGlassSettings({
    this.visibility = 1.0,
    this.glassColor = const Color.fromARGB(0, 255, 255, 255),
    this.thickness = 20,
    this.blur = 5,
    this.chromaticAberration = .01,
    this.lightAngle = 0.5 * pi,
    this.lightIntensity = 1,
    this.ambientStrength = 0,
    this.highlightColor = const Color.fromARGB(255, 255, 255, 255),
    this.edgeColor = const Color.fromARGB(0, 255, 255, 255),
    this.specularWrap = 0.35,
    this.bleedStrength = 0.5,
    this.refractiveIndex = 1.2,
    this.saturation = 1.5,
  });

  /// Creates a new [LiquidGlassSettings] with the given settings where each
  /// setting works like it does in Figma, where it is a percentage from
  /// 0 to 100.
  LiquidGlassSettings.figma({
    required double refraction,
    required double depth,
    required double dispersion,
    required double frost,
    double visibility = 1.0,
    double lightIntensity = 50,
    double lightAngle = 0.5 * pi,
    Color glassColor = const Color.fromARGB(0, 255, 255, 255),
  }) : this(
         visibility: visibility,
         refractiveIndex: 1 + (refraction / 100) * 0.2,
         thickness: depth,
         chromaticAberration: 4 * (dispersion / 100),
         lightIntensity: lightIntensity / 100,
         blur: frost,
         lightAngle: lightAngle,
         ambientStrength: 0.1,
         saturation: 1.5,
         glassColor: glassColor,
       );

  /// Retrieves the nearest [LiquidGlassSettings] from the widget tree.
  ///
  /// This will look for the nearest ancestor [LiquidGlassLayer] or
  /// [LiquidGlassRenderScope] widget in the widget tree.
  static LiquidGlassSettings of(BuildContext context) {
    return LiquidGlassRenderScope.of(context).settings;
  }

  /// A factor that can be used to scale all thickness-related properties.
  ///
  /// Defaults to 1.0.
  final double visibility;

  /// The color tint of the glass effect.
  ///
  /// Opacity defines the intensity of the tint.
  final Color glassColor;

  /// The effective glass color taking visibility into account.
  Color get effectiveGlassColor =>
      glassColor.withValues(alpha: glassColor.a * visibility);

  /// The thickness of the glass surface.
  ///
  /// Thicker surfaces refract the light more intensely.
  final double thickness;

  /// The effective thickness taking visibility into account.
  double get effectiveThickness => thickness * visibility;

  /// The blur of the glass effect.
  ///
  /// Higher values create a more frosted appearance.
  ///
  /// Defaults to 0.
  final double blur;

  /// The effective blur taking visibility into account.
  double get effectiveBlur => blur * visibility;

  /// The chromatic aberration of the glass effect (WIP).
  ///
  /// This is a little ugly still.
  ///
  /// Higher values create more pronounced color fringes.
  final double chromaticAberration;

  /// The effective chromatic aberration taking visibility into account.
  double get effectiveChromaticAberration => chromaticAberration * visibility;

  /// The angle of the light source in radians.
  ///
  /// This determines where the highlights on shapes will come from.
  final double lightAngle;

  /// An optional multiplier on top of the light intensity.
  ///
  /// The primary control for how strong the light is, is the alpha of
  /// [highlightColor]. This multiplier lets you overdrive the light *past* full
  /// intensity (values > 1) or dim it globally, on top of that alpha.
  ///
  /// Defaults to `1.0`, in which case the highlight color's alpha alone
  /// determines the light intensity.
  final double lightIntensity;

  /// The effective light intensity.
  ///
  /// This combines the [highlightColor]'s alpha (the base intensity) with the
  /// [lightIntensity] overdrive multiplier and [visibility]. It is the single
  /// value that drives all lighting, both the glass body and the specular rim.
  double get effectiveLightIntensity =>
      effectiveHighlightColor.a * lightIntensity;

  /// The strength of the ambient light.
  ///
  /// Higher values create more pronounced ambient light.
  final double ambientStrength;

  /// The effective ambient strength taking visibility into account.
  double get effectiveAmbientStrength => ambientStrength * visibility;

  /// The color of the specular highlight where the light hits the edge.
  ///
  /// Its alpha is the primary control for the overall light intensity (of both
  /// the glass body and the specular rim): `0` means no light, fully opaque
  /// means full intensity. Use [lightIntensity] to overdrive past that.
  ///
  /// Defaults to opaque white.
  final Color highlightColor;

  /// The effective highlight color taking visibility into account.
  Color get effectiveHighlightColor =>
      highlightColor.withValues(alpha: highlightColor.a * visibility);

  /// The color the specular rim fades to where the directional light is weak.
  ///
  /// Set this to a slightly dark, semi-transparent color to give the glass edge
  /// more presence. Defaults to fully transparent, in which case the specular
  /// rim fades out where it is not lit.
  final Color edgeColor;

  /// The effective edge color taking visibility into account.
  Color get effectiveEdgeColor =>
      edgeColor.withValues(alpha: edgeColor.a * visibility);

  /// How far the specular highlight wraps around the edge before it fades to
  /// [edgeColor], from `0` (tight directional highlight) to `1` (broad wrap).
  ///
  /// Higher values make the transition between [highlightColor] and [edgeColor]
  /// softer and broader around the rim.
  ///
  /// Defaults to `0.35`.
  final double specularWrap;

  /// How visible the subtle light bleed is, from `0` (off) to `1` (full).
  ///
  /// The bleed is a soft glow of the [highlightColor] that spreads inward from
  /// the lit edges into the body of the glass, applied equally to both
  /// highlight directions. It is always more subtle than the crisp rim
  /// highlight.
  ///
  /// Defaults to `0.5`.
  final double bleedStrength;

  /// The effective bleed strength taking visibility into account.
  double get effectiveBleedStrength => bleedStrength * visibility;

  /// The strength of the refraction.
  ///
  /// Higher values create more pronounced refraction.
  /// Defaults to 1.51
  final double refractiveIndex;

  /// The saturation adjustment for pixels that shine through the glass.
  ///
  /// 1.0 means no change, values < 1.0 desaturate the background,
  /// values > 1.0 increase saturation.
  /// Defaults to 1.0
  final double saturation;

  /// The effective saturation taking visibility into account.
  double get effectiveSaturation => 1 + (saturation - 1) * visibility;

  /// Creates a new [LiquidGlassSettings] with the given settings.
  LiquidGlassSettings copyWith({
    double? visibility,
    Color? glassColor,
    double? thickness,
    double? blur,
    double? chromaticAberration,
    double? blend,
    double? lightAngle,
    double? lightIntensity,
    double? ambientStrength,
    Color? highlightColor,
    Color? edgeColor,
    double? specularWrap,
    double? bleedStrength,
    double? refractiveIndex,
    double? saturation,
  }) => LiquidGlassSettings(
    visibility: visibility ?? this.visibility,
    glassColor: glassColor ?? this.glassColor,
    thickness: thickness ?? this.thickness,
    blur: blur ?? this.blur,
    chromaticAberration: chromaticAberration ?? this.chromaticAberration,
    lightAngle: lightAngle ?? this.lightAngle,
    lightIntensity: lightIntensity ?? this.lightIntensity,
    ambientStrength: ambientStrength ?? this.ambientStrength,
    highlightColor: highlightColor ?? this.highlightColor,
    edgeColor: edgeColor ?? this.edgeColor,
    specularWrap: specularWrap ?? this.specularWrap,
    bleedStrength: bleedStrength ?? this.bleedStrength,
    refractiveIndex: refractiveIndex ?? this.refractiveIndex,
    saturation: saturation ?? this.saturation,
  );

  @override
  List<Object?> get props => [
    visibility,
    glassColor,
    thickness,
    blur,
    chromaticAberration,
    lightAngle,
    lightIntensity,
    ambientStrength,
    highlightColor,
    edgeColor,
    specularWrap,
    bleedStrength,
    refractiveIndex,
    saturation,
  ];
}

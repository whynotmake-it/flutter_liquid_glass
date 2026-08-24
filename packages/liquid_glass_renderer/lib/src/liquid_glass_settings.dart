import 'dart:math';

import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_render_scope.dart';

/// Represents the settings for a liquid glass effect.
class LiquidGlassSettings with Equatable {
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
    this.edgeWidth = 0,
    this.outerContourColor,
    this.outerContourWidth,
    this.edgeInset = 0.5,
    this.specularWrap = 0.35,
    this.bleedStrength = 0.5,
    this.transmissionGamma = 1.0,
    this.vibrancy = 0.0,
    this.faceShadingStrength = 0.0,
    this.faceShadingDepth = 20.0,
    this.innerShadowStrength = 0.0,
    this.innerShadowDepth = 12.0,
    this.innerShadowDirectionality = 0.0,
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
  /// Defaults to 5.
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

  /// The color of the thin outline at the outer edge of the specular rim.
  ///
  /// Set this to a slightly dark, semi-transparent color to give the glass edge
  /// more presence. Defaults to fully transparent.
  final Color edgeColor;

  /// The effective edge color taking visibility into account.
  Color get effectiveEdgeColor =>
      edgeColor.withValues(alpha: edgeColor.a * visibility);

  /// The width of the [edgeColor] outline.
  ///
  /// The highlight is moved inward by this amount. Defaults to `0`.
  final double edgeWidth;

  /// The effective edge width taking visibility into account.
  double get effectiveEdgeWidth => edgeWidth * visibility;

  /// Optional material contour painted on the silhouette outside the GPU rim.
  ///
  /// When omitted, the legacy [edgeColor] is used for compatibility. Set an
  /// explicit color to tune Apple's dark dielectric outline independently of
  /// the directional specular rim.
  final Color? outerContourColor;

  /// Optional width of the independent outer material contour.
  ///
  /// When omitted, [edgeWidth] is used. This contour is a single canvas stroke
  /// and does not add another backdrop capture or shader pass.
  final double? outerContourWidth;

  /// Effective independent outer contour color.
  Color get effectiveOuterContourColor =>
      (outerContourColor ?? edgeColor).withValues(
        alpha: (outerContourColor ?? edgeColor).a * visibility,
      );

  /// Effective contour color consumed by the final material shader. A null
  /// override keeps the legacy edge path unchanged.
  Color get effectiveOuterMaterialContourColor =>
      outerContourColor?.withValues(alpha: outerContourColor!.a * visibility) ??
      const Color.fromARGB(0, 0, 0, 0);

  /// Effective independent outer contour width.
  double get effectiveOuterContourWidth =>
      (outerContourWidth ?? edgeWidth) * visibility;

  /// Effective width for the independent shader contour. Zero means disabled.
  double get effectiveOuterMaterialContourWidth =>
      (outerContourWidth ?? 0.0) * visibility;

  /// How far the specular highlight is inset into the edge width.
  ///
  /// `0` means the highlight starts at the outer edge. `0.5` means it starts
  /// halfway through [edgeWidth]. `1` means it starts after the full edge
  /// width.
  ///
  /// Defaults to `0.5`.
  final double edgeInset;

  /// How far the specular highlight wraps around the edge, from `0` (tight
  /// directional highlight) to `1` (broad wrap).
  ///
  /// Higher values make the highlight softer and broader around the rim.
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

  /// Display-referred transfer applied to light transmitted through the glass.
  ///
  /// `1.0` preserves the sampled backdrop. Values below `1.0` lift midtones
  /// without moving black or white, matching glass compositors that combine
  /// the backdrop and material in a nonlinear display color space.
  final double transmissionGamma;

  /// The effective transmission transfer taking visibility into account.
  double get effectiveTransmissionGamma =>
      1 + (transmissionGamma - 1) * visibility;

  /// Backdrop-aware luminance lift proportional to transmitted chroma.
  ///
  /// This models the vibrancy pass used by translucent system materials: a
  /// neutral backdrop is unchanged, while colorful content contributes a
  /// subtle diffuse lift through the glass.
  final double vibrancy;

  /// The effective vibrancy taking visibility into account.
  double get effectiveVibrancy => vibrancy * visibility;

  /// Strength of the broad directional occlusion lobe beneath the lit rim.
  ///
  /// This shades the otherwise-flat face as light passes beneath the raised
  /// rim. A value of `0` disables the effect.
  final double faceShadingStrength;

  /// Effective face shading strength taking visibility into account.
  double get effectiveFaceShadingStrength => faceShadingStrength * visibility;

  /// Distance in logical pixels over which face shading fades into the glass.
  final double faceShadingDepth;

  /// Effective face shading depth taking visibility into account.
  double get effectiveFaceShadingDepth => faceShadingDepth * visibility;

  /// Strength of the ambient occlusion beneath the raised inner bevel.
  ///
  /// This is independent of light direction and gives bright materials their
  /// characteristic inset, three-dimensional edge. A value of `0` disables
  /// the effect.
  final double innerShadowStrength;

  /// Effective inner-shadow strength taking visibility into account.
  double get effectiveInnerShadowStrength => innerShadowStrength * visibility;

  /// Distance in logical pixels over which the inner bevel shadow fades.
  final double innerShadowDepth;

  /// Effective inner-shadow depth taking visibility into account.
  double get effectiveInnerShadowDepth => innerShadowDepth * visibility;

  /// Redistributes the inner shadow toward the side facing away from the
  /// configured light direction, without changing its symmetric baseline.
  ///
  /// `0` keeps the ambient inner shadow symmetric. `1` gives the shadow its
  /// full directional range. The default is `0` so existing materials keep
  /// their previous appearance.
  final double innerShadowDirectionality;

  /// Effective inner-shadow directionality taking visibility into account.
  double get effectiveInnerShadowDirectionality =>
      innerShadowDirectionality * visibility;

  /// The strength of the refraction.
  ///
  /// Higher values create more pronounced refraction.
  /// Defaults to 1.2.
  final double refractiveIndex;

  /// The saturation adjustment for pixels that shine through the glass.
  ///
  /// 1.0 means no change, values < 1.0 desaturate the background,
  /// values > 1.0 increase saturation.
  /// Defaults to 1.5.
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
    double? lightAngle,
    double? lightIntensity,
    double? ambientStrength,
    Color? highlightColor,
    Color? edgeColor,
    double? edgeWidth,
    Color? outerContourColor,
    double? outerContourWidth,
    double? edgeInset,
    double? specularWrap,
    double? bleedStrength,
    double? transmissionGamma,
    double? vibrancy,
    double? faceShadingStrength,
    double? faceShadingDepth,
    double? innerShadowStrength,
    double? innerShadowDepth,
    double? innerShadowDirectionality,
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
    edgeWidth: edgeWidth ?? this.edgeWidth,
    outerContourColor: outerContourColor ?? this.outerContourColor,
    outerContourWidth: outerContourWidth ?? this.outerContourWidth,
    edgeInset: edgeInset ?? this.edgeInset,
    specularWrap: specularWrap ?? this.specularWrap,
    bleedStrength: bleedStrength ?? this.bleedStrength,
    transmissionGamma: transmissionGamma ?? this.transmissionGamma,
    vibrancy: vibrancy ?? this.vibrancy,
    faceShadingStrength: faceShadingStrength ?? this.faceShadingStrength,
    faceShadingDepth: faceShadingDepth ?? this.faceShadingDepth,
    innerShadowStrength: innerShadowStrength ?? this.innerShadowStrength,
    innerShadowDepth: innerShadowDepth ?? this.innerShadowDepth,
    innerShadowDirectionality:
        innerShadowDirectionality ?? this.innerShadowDirectionality,
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
    edgeWidth,
    outerContourColor,
    outerContourWidth,
    edgeInset,
    specularWrap,
    bleedStrength,
    transmissionGamma,
    vibrancy,
    faceShadingStrength,
    faceShadingDepth,
    innerShadowStrength,
    innerShadowDepth,
    innerShadowDirectionality,
    refractiveIndex,
    saturation,
  ];
}

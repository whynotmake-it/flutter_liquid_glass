import 'dart:math';
import 'dart:ui';

import 'package:equatable/equatable.dart';

/// Represents the settings for a liquid glass effect.
class LiquidGlassSettings with EquatableMixin {
  /// Creates a new [LiquidGlassSettings] with the given settings.
  const LiquidGlassSettings({
    this.glassColor = const Color.fromARGB(0, 255, 255, 255),
    this.thickness = 20,
    this.chromaticAberration = .01,
    this.blend = 20,
    this.lightAngle = 0.5 * pi,
    this.lightIntensity = 1,
    this.ambientStrength = .01,
    this.refractiveIndex = 1.51,
  });

  /// The color tint of the glass effect.
  ///
  /// Opacity defines the intensity of the tint.
  final Color glassColor;

  /// The thickness of the glass surface.
  ///
  /// Thicker surfaces refract the light more intensely.
  final double thickness;

  /// The chromatic aberration of the glass effect (WIP).
  ///
  /// This is a little ugly still.
  ///
  /// Higher values create more pronounced color fringes.
  final double chromaticAberration;

  /// How strongly the shapes in this layer will blend together.
  final double blend;

  /// The angle of the light source in radians.
  ///
  /// This determines where the highlights on shapes will come from.
  final double lightAngle;

  /// The intensity of the light source.
  ///
  /// Higher values create more pronounced highlights.
  final double lightIntensity;

  /// The strength of the ambient light.
  ///
  /// Higher values create more pronounced ambient light.
  final double ambientStrength;

  /// The strength of the refraction.
  ///
  /// Higher values create more pronounced refraction.
  /// Defaults to 1.51
  final double refractiveIndex;

  /// Creates a new [LiquidGlassSettings] with the given settings.
  LiquidGlassSettings copyWith({
    Color? glassColor,
    double? thickness,
    double? chromaticAberration,
    double? blend,
    double? lightAngle,
    double? lightIntensity,
    double? ambientStrength,
    double? refractiveIndex,
  }) =>
      LiquidGlassSettings(
        glassColor: glassColor ?? this.glassColor,
        thickness: thickness ?? this.thickness,
        chromaticAberration: chromaticAberration ?? this.chromaticAberration,
        blend: blend ?? this.blend,
        lightAngle: lightAngle ?? this.lightAngle,
        lightIntensity: lightIntensity ?? this.lightIntensity,
        ambientStrength: ambientStrength ?? this.ambientStrength,
        refractiveIndex: refractiveIndex ?? this.refractiveIndex,
      );

  @override
  List<Object?> get props => [
        glassColor,
        thickness,
        chromaticAberration,
        blend,
        lightAngle,
        lightIntensity,
        ambientStrength,
        refractiveIndex,
      ];
}

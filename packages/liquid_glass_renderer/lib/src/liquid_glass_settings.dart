import 'dart:math';
import 'dart:ui';

import 'package:equatable/equatable.dart';

class LiquidGlassSettings with EquatableMixin {
  const LiquidGlassSettings({
    this.glassColor = const Color.fromARGB(0, 255, 255, 255),
    this.thickness = 20,
    this.chromaticAberration = .01,
    this.blend = 20,
    this.lightAngle = 0.5 * pi,
    this.lightIntensity = 1,
    this.ambientStrength = .01,
    this.outlineIntensity = .1,
  });

  final Color glassColor;
  final double thickness;
  final double chromaticAberration;
  final double blend;
  final double lightAngle;
  final double lightIntensity;
  final double ambientStrength;
  final double outlineIntensity;

  @override
  List<Object?> get props => [
        glassColor,
        thickness,
        chromaticAberration,
        blend,
        lightAngle,
        lightIntensity,
        ambientStrength,
        outlineIntensity,
      ];
}

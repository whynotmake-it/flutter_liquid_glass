import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

final testScenarioConstraints = BoxConstraints.tight(const Size(500, 500));

const settingsWithoutLighting = LiquidGlassSettings(
  ambientStrength: 0,
  chromaticAberration: 0,
  lightIntensity: 0,
);

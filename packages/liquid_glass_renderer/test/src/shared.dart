import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

const expectFlutterGpuFallback = bool.fromEnvironment(
  'EXPECT_FLUTTER_GPU_FALLBACK',
);

bool get skipProperGlassTests => expectFlutterGpuFallback;

/// Alchemist still calls `testWidgets` when a golden is tagged `golden`, and
/// Flutter 3.44 asserts that the variant is non-empty. Platform goldens are
/// macOS-only, so skip registration on other hosts instead of loading an
/// empty variant.
bool get skipGoldenTests => skipProperGlassTests || !Platform.isMacOS;

final testScenarioConstraints = BoxConstraints.tight(const Size(500, 500));

const settingsWithoutLighting = LiquidGlassSettings(
  chromaticAberration: 0,
  lightIntensity: 0,
  blur: 0,
);

Widget buildWithGridPaper(Widget child) {
  return ColoredBox(
    color: Colors.white,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          const Positioned.fill(
            child: GridPaper(
              color: Colors.black,
            ),
          ),
          Center(
            child: child,
          ),
        ],
      ),
    ),
  );
}

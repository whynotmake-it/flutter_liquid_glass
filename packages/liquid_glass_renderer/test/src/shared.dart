import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

const expectFlutterGpuFallback = bool.fromEnvironment(
  'EXPECT_FLUTTER_GPU_FALLBACK',
);

bool get skipProperGlassTests =>
    expectFlutterGpuFallback || !ui.ImageFilter.isShaderFilterSupported;

/// Alchemist still calls `testWidgets` when a golden is tagged `golden`, and
/// Flutter 3.44 asserts that the variant is non-empty. Platform goldens are
/// macOS-only, so skip registration on other hosts instead of loading an
/// empty variant.
bool get skipGoldenTests => skipProperGlassTests || !Platform.isMacOS;

/// Compares [actual] with the pixel reference at [path], on macOS only.
///
/// References are rendered by `flutter test --update-goldens` on the macOS
/// image the CI golden job uses; flutter_tester rasterizes differently on
/// other hosts, so they skip the comparison and keep the test's other checks.
Future<void> expectMacOSGolden(Object? actual, String path) async {
  if (!Platform.isMacOS) return;
  await expectLater(actual, matchesGoldenFile(path));
}

final testScenarioConstraints = BoxConstraints.tight(const Size(500, 500));

const settingsWithoutLighting = LiquidGlassSettings(
  highlight: 0,
  contourStrength: 0,
  bevelShadowStrength: 0,
  frost: 0,
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

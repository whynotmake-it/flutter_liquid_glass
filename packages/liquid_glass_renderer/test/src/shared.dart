import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_render_scope.dart';

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

/// Waits for the asynchronous Flutter GPU renderer to replace the initial
/// fake-glass scope. `pumpAndSettle` can return before the shader future
/// completes because the future does not schedule a frame until it resolves;
/// tests that inspect render-layer state must explicitly wait for that state.
Future<void> pumpUntilGlassReady(WidgetTester tester) async {
  for (var frame = 0; frame < 60; frame++) {
    final scopes = tester.widgetList<LiquidGlassRenderScope>(
      find.byType(LiquidGlassRenderScope),
    );
    if (scopes.any((scope) => !scope.useFake)) return;
    await tester.pump(const Duration(milliseconds: 16));
  }
  fail('Flutter GPU LiquidGlassLayer did not become ready within 60 frames');
}

final testScenarioConstraints = BoxConstraints.tight(const Size(500, 500));

const settingsWithoutLighting = LiquidGlassSettings(
  chromaticAberration: 0,
  highlight: 0,
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

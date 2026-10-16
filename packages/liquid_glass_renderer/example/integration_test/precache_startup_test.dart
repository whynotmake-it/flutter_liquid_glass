// Verify actual GPU readiness, not just completion of the public future.
// ignore_for_file: invalid_use_of_internal_member

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..deferFirstFrame();

  testWidgets('precache does not require the first frame', (tester) async {
    var rasterized = false;
    unawaited(
      binding.waitUntilFirstFrameRasterized.then((_) => rasterized = true),
    );
    try {
      await tester.runAsync(
        () => LiquidGlass.precache().timeout(const Duration(seconds: 10)),
      );
      expect(rasterized, isFalse);
      expect(tester.takeException(), isNull);
      final renderer = FlutterGpuGeometryRenderer.tryCreateCached(
        ShaderKeys.gpuGeometryShaderBundle,
      );
      expect(
        renderer,
        isNotNull,
        reason: 'GPU preparation must actually finish',
      );
      renderer?.dispose();
    } finally {
      binding.allowFirstFrame();
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

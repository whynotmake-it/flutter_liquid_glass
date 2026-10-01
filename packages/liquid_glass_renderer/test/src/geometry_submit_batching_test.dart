import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';

import 'shared.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  runGeometrySubmitBatchingTests();
}

/// Three layers rebuilding every frame; the middle one mixes appearances, so
/// it records a matte and a material pass. This multi-pass frame crashed
/// Vulkan and Metal when its passes shared one command buffer.
Widget _scene(double t) {
  Widget layer(double width, {bool tinted = false}) => LiquidGlassLayer(
    settings: const LiquidGlassSettings(contourStrength: 0.3),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        LiquidGlass(
          shape: const LiquidRoundedSuperellipse(borderRadius: 22),
          child: SizedBox(width: width, height: 44),
        ),
        const SizedBox(width: 8),
        LiquidGlass(
          shape: const LiquidOval(),
          appearance: tinted
              ? const LiquidGlassAppearance(tint: Color(0x552060FF))
              : null,
          child: const SizedBox(width: 44, height: 44),
        ),
      ],
    ),
  );

  return Directionality(
    textDirection: TextDirection.ltr,
    child: RepaintBoundary(
      child: ColoredBox(
        color: Colors.white,
        child: Stack(
          children: [
            const Positioned.fill(child: GridPaper(color: Colors.black)),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  layer(120 + t),
                  const SizedBox(height: 16),
                  layer(90 + t * 2, tinted: true),
                  const SizedBox(height: 16),
                  layer(150 - t),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Also runs on devices from `example/integration_test`.
void runGeometrySubmitBatchingTests() {
  testWidgets(
    'passes recorded in a frame are submitted while its scene is built',
    (tester) async {
      tester.view
        ..physicalSize = const Size(900, 900)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_scene(0));
      final postFrameFlushes =
          FlutterGpuGeometryRenderer.debugPostFrameFlushCount;
      for (var frame = 1; frame <= 10; frame++) {
        final passes = FlutterGpuGeometryRenderer.debugDeferredPassCount;
        final submits = FlutterGpuGeometryRenderer.debugBatchedSubmitCount;
        await tester.pumpWidget(_scene(frame * 0.5));
        final framePasses =
            FlutterGpuGeometryRenderer.debugDeferredPassCount - passes;
        final frameSubmits =
            FlutterGpuGeometryRenderer.debugBatchedSubmitCount - submits;
        if (!kDebugMode) continue;
        expect(framePasses, 4, reason: 'three mattes and one material map');
        expect(frameSubmits, 4, reason: 'one command buffer per pass');
      }
      if (kDebugMode) {
        expect(
          FlutterGpuGeometryRenderer.debugPostFrameFlushCount,
          postFrameFlushes,
          reason: 'the scene build must flush before the scene is rendered',
        );
      }
    },
    skip: skipProperGlassTests,
  );
}

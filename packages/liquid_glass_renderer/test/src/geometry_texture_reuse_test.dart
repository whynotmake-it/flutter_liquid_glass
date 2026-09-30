import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

import 'shared.dart';

const _reuseAfter = FlutterGpuGeometryRenderer.reuseAfterFrames;

Widget _scene(double width, {Key? key}) {
  return Directionality(
    key: key,
    textDirection: TextDirection.ltr,
    child: Center(
      child: LiquidGlassLayer(
        settings: const LiquidGlassSettings(
          contourWidth: 1,
          contourStrength: 0.3,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LiquidGlass(
              shape: const LiquidRoundedSuperellipse(borderRadius: 22),
              child: SizedBox(width: width, height: 44),
            ),
            const SizedBox(width: 12),
            const LiquidGlass(
              shape: LiquidOval(),
              appearance: LiquidGlassAppearance(tint: Color(0x552060FF)),
              child: SizedBox(width: 44, height: 44),
            ),
          ],
        ),
      ),
    ),
  );
}

RenderLiquidGlassLayer _layer(WidgetTester tester) =>
    tester.allRenderObjects.whereType<RenderLiquidGlassLayer>().last;

Future<Uint8List> _bytes(WidgetTester tester, ui.Image image) async {
  final bytes = await tester.runAsync(image.toByteData);
  return bytes!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  runGeometryTextureReuseTests();
}

/// Also runs on devices from `example/integration_test/geometry_batch_test.dart`.
void runGeometryTextureReuseTests() {
  setUp(() {
    FlutterGpuGeometryRenderer.debugReusedTextureCount = 0;
  });

  testWidgets(
    'replaced mattes are reused only after the in-flight horizon',
    (tester) async {
      tester.view
        ..physicalSize = const Size(1200, 600)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_scene(130));
      final renderer = _layer(tester).gpuGeometryRenderer!;
      // Every frame rebuilds the matte and material map at the same
      // bucketed sizes.
      for (var frame = 1; frame <= _reuseAfter; frame++) {
        await tester.pumpWidget(_scene(130 + frame * 0.05));
        expect(
          FlutterGpuGeometryRenderer.debugReusedTextureCount,
          0,
          reason: 'frame $frame is inside the horizon',
        );
      }
      for (var frame = 0; frame < 20; frame++) {
        await tester.pumpWidget(_scene(130.5 + frame * 0.05));
      }
      expect(FlutterGpuGeometryRenderer.debugReusedTextureCount, 20 * 2);
      expect(
        renderer.debugRetiredTextureCount,
        lessThanOrEqualTo(2 * (_reuseAfter + 2)),
      );
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'a matte written into a reused texture is byte-identical to a fresh one',
    (tester) async {
      tester.view
        ..physicalSize = const Size(1200, 600)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      for (var frame = 0; frame < 3 * _reuseAfter; frame++) {
        await tester.pumpWidget(_scene(130 + frame * 0.05));
      }
      final reusedBefore = FlutterGpuGeometryRenderer.debugReusedTextureCount;
      await tester.pumpWidget(_scene(131.5));
      expect(
        FlutterGpuGeometryRenderer.debugReusedTextureCount - reusedBefore,
        2,
        reason: 'the compared matte and material map must be reused textures',
      );
      final reused = await _bytes(tester, _layer(tester).debugGeometryImage!);
      final reusedMaterial = await _bytes(
        tester,
        _layer(tester).debugMaterialImage!,
      );

      // A new layer owns a new renderer, so its first matte is allocated.
      await tester.pumpWidget(_scene(131.5, key: UniqueKey()));
      final fresh = await _bytes(tester, _layer(tester).debugGeometryImage!);
      final freshMaterial = await _bytes(
        tester,
        _layer(tester).debugMaterialImage!,
      );

      expect(reused.length, fresh.length);
      expect(reused, fresh);
      expect(reusedMaterial, freshMaterial);
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'retired textures are released once geometry stops changing',
    (tester) async {
      tester.view
        ..physicalSize = const Size(1200, 600)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      for (var frame = 0; frame < 2 * _reuseAfter; frame++) {
        await tester.pumpWidget(_scene(130 + frame * 0.25));
      }
      final renderer = _layer(tester).gpuGeometryRenderer!;
      expect(renderer.debugRetiredTextureCount, greaterThan(0));
      for (var frame = 0; frame < 40; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        tester.binding.scheduleFrame();
      }
      expect(renderer.debugRetiredTextureCount, 0);
    },
    skip: skipProperGlassTests,
  );
}

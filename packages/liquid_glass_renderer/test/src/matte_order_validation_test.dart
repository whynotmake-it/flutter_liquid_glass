import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';

import 'shared.dart';
import 'submitted_scene_binding.dart';

// Run with --dart-define=LIQUID_GLASS_VALIDATE_MATTE_ORDER=true.
void main() {
  final binding = SubmittedSceneBinding()
    ..captureWidth = 400
    ..captureHeight = 200;
  const enabled = FlutterGpuGeometryRenderer.validateMatteOrder;

  Widget scene(double width) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: Colors.white)),
        Center(
          child: LiquidGlassLayer(
            settings: settingsWithoutLighting,
            child: LiquidGlass(
              shape: const LiquidRoundedSuperellipse(borderRadius: 20),
              child: SizedBox(width: width, height: 80),
            ),
          ),
        ),
      ],
    ),
  );

  Future<int> magentaInNextFrame(WidgetTester tester, double width) async {
    binding.captureNextScene = true;
    await tester.pumpWidget(scene(width));
    final image = (await tester.runAsync(() => binding.captured!))!;
    final bytes = (await tester.runAsync(image.toByteData))!;
    image.dispose();
    final pixels = bytes.buffer.asUint32List();
    // RGBA 255, 0, 255, 255 in memory order.
    final magenta = ByteData(4)..setUint32(0, 0xFF00FFFF);
    final value = magenta.getUint32(0, Endian.host);
    return pixels.where((pixel) => pixel == value).length;
  }

  void useView(WidgetTester tester) {
    tester.view
      ..physicalSize = const Size(400, 200)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets(
    'every frame of a resize sweep samples the matte it rendered',
    (tester) async {
      useView(tester);
      for (var frame = 0; frame < 40; frame++) {
        final width = 120 + 6.0 * (frame % 20);
        expect(
          await magentaInNextFrame(tester, width),
          0,
          reason: 'frame $frame sampled a matte rewritten out of order',
        );
      }
    },
    skip: !enabled || skipProperGlassTests,
  );

  testWidgets(
    'a serial mismatch paints magenta',
    (tester) async {
      useView(tester);
      await magentaInNextFrame(tester, 120);
      FlutterGpuGeometryRenderer.debugMatteSerialSkew = 1;
      addTearDown(() => FlutterGpuGeometryRenderer.debugMatteSerialSkew = 0);
      expect(await magentaInNextFrame(tester, 126), greaterThan(1000));
    },
    skip: !enabled || skipProperGlassTests,
  );
}

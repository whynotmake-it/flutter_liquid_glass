import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

import 'shared.dart';

void main() {
  // Each case sits just past a 64-texel bucket edge at DPR 3, so the
  // scissor skips most of the padding row and column.
  final cases = <String, Widget>{
    'superellipse': const LiquidGlass(
      shape: LiquidRoundedSuperellipse(borderRadius: 22),
      child: SizedBox(width: 130, height: 44),
    ),
    'oval': const LiquidGlass(
      shape: LiquidOval(),
      child: SizedBox(width: 90, height: 66),
    ),
    'rounded rectangle': const LiquidGlass(
      shape: LiquidRoundedRectangle(borderRadius: 12),
      child: SizedBox(width: 70, height: 70),
    ),
    'rotated and anisotropically scaled': Transform(
      alignment: Alignment.center,
      transform: Matrix4.rotationZ(math.pi / 7)..scaleByDouble(1.35, 0.7, 1, 1),
      child: const LiquidGlass(
        shape: LiquidRoundedSuperellipse(borderRadius: 30),
        child: SizedBox(width: 120, height: 60),
      ),
    ),
  };

  const contoured = LiquidGlassSettings(
    contourWidth: 1.5,
    contourStrength: 0.4,
    contourOffset: 1,
  );

  for (final MapEntry(key: name, value: glass) in cases.entries) {
    for (final settings in [const LiquidGlassSettings(), contoured]) {
      final label = settings == contoured ? '$name with contour' : name;
      testWidgets(
        'scissored single-shape matte matches the full pass: $label',
        (tester) async {
          tester.view
            ..physicalSize = const Size(1200, 1200)
            ..devicePixelRatio = 3;
          addTearDown(tester.view.reset);
          addTearDown(
            () =>
                FlutterGpuGeometryRenderer.debugDisableGeometryScissor = false,
          );

          Future<(Uint8List, int, int)> matte({required bool scissor}) async {
            FlutterGpuGeometryRenderer.debugDisableGeometryScissor = !scissor;
            await tester.pumpWidget(
              Directionality(
                key: UniqueKey(),
                textDirection: TextDirection.ltr,
                child: Center(
                  child: LiquidGlassLayer(settings: settings, child: glass),
                ),
              ),
            );
            await tester.pump();
            final layer = tester.allRenderObjects
                .whereType<RenderLiquidGlassLayer>()
                .last;
            final image = layer.debugGeometryImage!;
            final bytes = await tester.runAsync(image.toByteData);
            return (bytes!.buffer.asUint8List(), image.width, image.height);
          }

          final scissoredBefore =
              FlutterGpuGeometryRenderer.debugScissoredRenderCount;
          final (scissored, width, height) = await matte(scissor: true);
          expect(
            FlutterGpuGeometryRenderer.debugScissoredRenderCount,
            greaterThan(scissoredBefore),
            reason: 'the case must exercise the scissored pass',
          );
          final (full, fullWidth, fullHeight) = await matte(scissor: false);
          expect((width, height), (fullWidth, fullHeight));
          var differing = 0;
          for (var i = 0; i < full.length; i++) {
            if (full[i] != scissored[i]) differing++;
          }
          expect(differing, 0, reason: 'matte bytes must be identical');
        },
        skip: skipProperGlassTests,
      );
    }
  }
}

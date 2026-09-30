import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/consolidated_fake_glass_layer.dart';

import 'shared.dart';

const _center = Offset(60, 60);
const _radius = 40.0;

void main() {
  testWidgets(
    'FakeGlass anti-aliases its filtered backdrop along the silhouette',
    (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size.square(120);
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RepaintBoundary(
            key: key,
            child: ColoredBox(
              color: const Color(0xFF2A9D8F),
              child: LiquidGlassLayer(
                fake: true,
                settings: const LiquidGlassSettings.ios27ToolbarLight(
                  frost: 0,
                ).copyWith(highlight: 0, contourStrength: 0),
                defaultAppearance:
                    const LiquidGlassAppearance.ios27ToolbarLight(),
                child: Stack(
                  children: [
                    Positioned(
                      left: _center.dx - _radius,
                      top: _center.dy - _radius,
                      child: const LiquidGlass(
                        shape: LiquidOval(),
                        child: SizedBox.square(dimension: _radius * 2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        tester.allRenderObjects
            .whereType<RenderConsolidatedFakeGlassLayer>()
            .last
            .debugUsesBackdropEdgePass,
        isTrue,
      );
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final bytes = (await tester.runAsync(image.toByteData))!;
      final width = image.width;
      image.dispose();
      double green(int x, int y) =>
          bytes.getUint8((y * width + x) * 4 + 1).toDouble();

      final backdrop = green(2, 2);
      final face = green(_center.dx.round(), _center.dy.round());
      expect((face - backdrop).abs(), greaterThan(40));

      // Compare every pixel within two pixels of the silhouette against its
      // one-pixel box coverage between backdrop and face.
      var squaredError = 0.0;
      var count = 0;
      for (var y = 0; y < 120; y++) {
        for (var x = 0; x < 120; x++) {
          final distance =
              (Offset(x + 0.5, y + 0.5) - _center).distance - _radius;
          if (distance.abs() > 2) continue;
          final coverage = (0.5 - distance).clamp(0.0, 1.0);
          final expected = backdrop + (face - backdrop) * coverage;
          squaredError += math.pow(green(x, y) - expected, 2);
          count++;
        }
      }
      final rms = math.sqrt(squaredError / count);
      // A stencil-clipped backdrop snaps each pixel to backdrop or face.
      expect(rms, lessThan(0.06 * (face - backdrop).abs()));
    },
    skip: skipProperGlassTests,
  );
}

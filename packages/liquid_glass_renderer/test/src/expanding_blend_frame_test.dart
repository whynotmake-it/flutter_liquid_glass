import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';

import 'shared.dart';
import 'submitted_scene_binding.dart';

void main() {
  final binding = SubmittedSceneBinding()
    ..captureWidth = 400
    ..captureHeight = 320;
  for (final fake in [true, false]) {
    for (final materials in [false, true]) {
      testWidgets('expanding pill preserves submitted button '
          'fake=$fake materials=$materials', (tester) async {
        tester.view
          ..physicalSize = const Size(400, 320)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var height = 60.0;
        late StateSetter update;
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: Stack(
                children: [
                  const Positioned.fill(child: ColoredBox(color: Colors.white)),
                  const Positioned.fill(child: GridPaper(color: Colors.black)),
                  LiquidGlassLayer(
                    fake: fake,
                    settings: settingsWithoutLighting,
                    child: StatefulBuilder(
                      builder: (context, setState) {
                        update = setState;
                        return LiquidGlassBlendGroup(
                          child: Stack(
                            children: [
                              Positioned(
                                left: 30,
                                bottom: 30,
                                child: LiquidGlass.grouped(
                                  appearance: materials
                                      ? const LiquidGlassAppearance(
                                          tint: Color(0x40FF0000),
                                          saturation: 1.2,
                                        )
                                      : const LiquidGlassAppearance(),
                                  shape: const LiquidRoundedRectangle(
                                    borderRadius: 30,
                                  ),
                                  child: SizedBox(width: 200, height: height),
                                ),
                              ),
                              Positioned(
                                right: 50,
                                bottom: 30,
                                child: LiquidGlass.grouped(
                                  appearance: materials
                                      ? const LiquidGlassAppearance(
                                          tint: Color(0x400000FF),
                                          saturation: 0.8,
                                        )
                                      : const LiquidGlassAppearance(),
                                  shape: const LiquidOval(),
                                  child: const SizedBox.square(dimension: 60),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        if (!fake) {
          for (var frame = 0; frame < 60; frame++) {
            await tester.pump(const Duration(milliseconds: 16));
            if (tester.allRenderObjects
                .whereType<LiquidGlassRenderObject>()
                .isNotEmpty) {
              break;
            }
          }
          expect(
            tester.allRenderObjects.whereType<LiquidGlassRenderObject>(),
            isNotEmpty,
          );
        }
        binding
          ..captureNextScene = true
          ..scheduleFrame();
        await tester.pump();
        final reference = await tester.runAsync(() => binding.captured!);
        final expected = await tester.runAsync(reference!.toByteData);
        if (!fake && !materials) {
          await expectLater(
            reference,
            matchesGoldenFile('goldens/expanding_blend_submitted.png'),
          );
        }
        reference.dispose();
        final builder = ui.SceneBuilder()
          ..addRetained(binding.renderViews.single.debugLayer!.engineLayer!);
        final pending = builder.build();
        final renderer = tester.allRenderObjects
            .whereType<LiquidGlassRenderObject>()
            .firstOrNull;
        final oldCount = renderer?.gpuGeometryRenderer?.debugRenderCount;
        // Change the origin within a bucket, then grow and shrink. Keep the
        // old scene beyond any plausible fixed-size texture ring.
        for (final nextHeight in [
          76.0,
          84.0,
          92.0,
          100.0,
          108.0,
          116.0,
          140.0,
          60.0,
        ]) {
          update(() => height = nextHeight);
          await tester.pump(const Duration(milliseconds: 16));
        }
        if (!fake) {
          expect(
            renderer!.gpuGeometryRenderer!.debugRenderCount,
            greaterThan(oldCount!),
          );
        }
        final image = await tester.runAsync(() => pending.toImage(400, 320));
        final actual = await tester.runAsync(image!.toByteData);
        image.dispose();
        pending.dispose();
        var changed = 0;
        for (var y = 220; y < 310; y++) {
          for (var x = 280; x < 370; x++) {
            final offset = (y * 400 + x) * 4;
            if (actual!.getUint32(offset) != expected!.getUint32(offset)) {
              changed++;
            }
          }
        }
        expect(
          changed,
          0,
          reason:
              'Expanding the left pill must not mutate the stationary '
              'button in an already submitted frame.',
        );
      }, skip: !fake && skipProperGlassTests);
    }
  }
}

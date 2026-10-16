import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

import 'shared.dart';
import 'submitted_scene_binding.dart';

// The same workload can run against the unmodified baseline. It checks the old
// submission counts there, while keeping all pixel/reference checks identical.
const _baseline = bool.fromEnvironment('EXPECT_FULL_APPEARANCE_REBUILD');

void main() {
  runAppearanceOutputSplitTests(SubmittedSceneBinding());
}

/// Shared host/device workload; the device binding must capture submitted scenes.
void runAppearanceOutputSplitTests(TestWidgetsFlutterBinding binding) {
  final sceneCapture = (binding as SubmittedSceneCapture)
    ..captureWidth = 240
    ..captureHeight = 180;

  for (final retained in [false, true]) {
    testWidgets('appearance outputs split (retained=$retained)', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(240, 180)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var appearances = const [
        LiquidGlassAppearance(tint: Color(0x303080FF)),
        LiquidGlassAppearance(tint: Color(0xC0FF8030)),
        LiquidGlassAppearance(tint: Color(0x7040CC70)),
      ];
      var translation = 0.0;
      var relativeMotion = 0.0;
      var reverse = false;
      final update = ValueNotifier<int>(0);
      addTearDown(update.dispose);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            children: [
              const Positioned.fill(child: ColoredBox(color: Colors.white)),
              const Positioned.fill(child: GridPaper(color: Colors.black)),
              LiquidGlassLayer(
                settings: const LiquidGlassSettings(frost: 3),
                child: ValueListenableBuilder<int>(
                  valueListenable: update,
                  builder: (_, __, ___) => RepaintBoundary(
                    child: Transform.translate(
                      offset: Offset(translation, 0),
                      child: LiquidGlassBlendGroup(
                        blend: 24,
                        child: Stack(
                          children: [
                            for (final i in (reverse ? [2, 1, 0] : [0, 1, 2]))
                              Positioned(
                                key: ValueKey(i),
                                left: [40.0, 100.0, 70.0 + relativeMotion][i],
                                top: [35.0, 35.0, 75.0][i],
                                child: LiquidGlass.grouped(
                                  appearance: appearances[i],
                                  shape: const LiquidOval(),
                                  child: const SizedBox.square(dimension: 80),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final layer = tester.allRenderObjects
          .whereType<RenderLiquidGlassLayer>()
          .last;
      final renderer = layer.gpuGeometryRenderer!;

      List<int> revisions() => [
        for (final geometry
            in tester.allRenderObjects.whereType<RenderLiquidGlassGeometry>())
          if (geometry.geometry != null) geometry.geometry!.matteRevision,
      ];

      Future<Uint8List> read(ui.Image image, int width, int height) async {
        final data = (await tester.runAsync(image.toByteData))!;
        final bytes = data.buffer.asUint8List(data.offsetInBytes);
        return Uint8List.fromList([
          for (var y = 0; y < height; y++)
            ...bytes.sublist(
              y * image.width * 4,
              (y * image.width + width) * 4,
            ),
        ]);
      }

      Future<Uint8List> capture() async {
        sceneCapture.captureNextScene = true;
        binding.scheduleFrame();
        await tester.pump();
        final image = (await tester.runAsync(() => sceneCapture.captured!))!;
        final bytes = await read(image, image.width, image.height);
        image.dispose();
        return bytes;
      }

      Future<Uint8List> matteBytes() => read(
        layer.debugGeometryImage!,
        layer.debugGeometryMatteBounds.width.round(),
        layer.debugGeometryMatteBounds.height.round(),
      );

      Future<Uint8List?> materialBytes() async {
        final image = layer.debugMaterialImage;
        if (image == null) return null;
        final width = (layer.debugGeometryMatteBounds.width / 8).ceil();
        final height = (layer.debugGeometryMatteBounds.height / 8).ceil();
        return read(
          image,
          layer.debugUsesTintOnlyAppearance
              ? width
              : width < 16
              ? 16
              : width,
          height + (layer.debugUsesTintOnlyAppearance ? 0 : 2),
        );
      }

      // Stable, portable readback fingerprints in the raw test log.
      String digest(Uint8List bytes) {
        var hash = 0x811c9dc5;
        for (final byte in bytes) {
          hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
        }
        return '${bytes.length}:${hash.toRadixString(16)}';
      }

      Future<void> check(
        String name,
        void Function() change, {
        bool geometryChanged = false,
        bool uniform = false,
        bool appearanceChanged = true,
        bool translated = false,
      }) async {
        final oldMatte = renderer.debugMatteTexture;
        final oldImage = layer.debugGeometryImage;
        final oldRevisions = revisions();
        final before = await matteBytes();
        final passes = FlutterGpuGeometryRenderer.debugDeferredPassCount;
        final paints = layer.debugPaintCount;
        change();
        update.value++;
        if (!retained) layer.markNeedsPaint();
        final scene = await capture();
        final count =
            FlutterGpuGeometryRenderer.debugDeferredPassCount - passes;
        final expectedMatte =
            geometryChanged || (_baseline && appearanceChanged);
        final expectedMaterial =
            !uniform && (geometryChanged || appearanceChanged);
        expect(
          count,
          (expectedMatte ? 1 : 0) + (expectedMaterial ? 1 : 0),
          reason: name,
        );
        if (retained && !geometryChanged) {
          expect(layer.debugPaintCount, paints, reason: '$name retained path');
        }
        if (!geometryChanged) {
          expect(revisions(), oldRevisions, reason: '$name CPU matte revision');
          if (!_baseline) {
            expect(renderer.debugMatteTexture, same(oldMatte), reason: name);
            expect(layer.debugGeometryImage, same(oldImage), reason: name);
          }
          expect(await matteBytes(), before, reason: '$name unchanged matte');
        } else {
          expect(
            renderer.debugMatteTexture,
            isNot(same(oldMatte)),
            reason: name,
          );
        }
        final matte = await matteBytes();
        final material = await materialBytes();
        // Force the exact same inputs through the old full-encode path.
        layer
          // ignore: invalid_use_of_protected_member
          ..needsGeometryUpdate = true
          ..markNeedsPaint();
        final reference = await capture();
        expect(await matteBytes(), matte, reason: '$name full matte reference');
        expect(
          await materialBytes(),
          material,
          reason: '$name material reference',
        );
        expect(scene, reference, reason: '$name submitted filter snapshot');
        // ignore: avoid_print
        print(
          '$name retained=$retained passes=$count translated=$translated '
          'matte=${digest(matte)} '
          'material=${material == null ? "none" : digest(material)} '
          'scene=${digest(scene)}',
        );
      }

      await check('unequal-alpha tint / three-way junction', () {
        appearances = [
          const LiquidGlassAppearance(tint: Color(0x906030FF)),
          ...appearances.skip(1),
        ];
      });
      await check('tint to general', () {
        appearances = [
          const LiquidGlassAppearance(tint: Color(0x906030FF), saturation: 0.4),
          ...appearances.skip(1),
        ];
      });
      await check('general appearance', () {
        appearances = [
          const LiquidGlassAppearance(tint: Color(0x906030FF), saturation: 1.6),
          ...appearances.skip(1),
        ];
      });
      await check('general to tint', () {
        appearances = [
          const LiquidGlassAppearance(tint: Color(0x906030FF)),
          ...appearances.skip(1),
        ];
      });
      await check('mixed to uniform', () {
        appearances = List.filled(3, const LiquidGlassAppearance());
      }, uniform: true);
      await check('uniform to mixed', () {
        appearances = [
          const LiquidGlassAppearance(tint: Color(0xA0FF3050)),
          ...appearances.skip(1),
        ];
      });
      await check('zero crossing removes contributor', () {
        appearances = [
          const LiquidGlassAppearance(visibility: 0),
          ...appearances.skip(1),
        ];
      }, geometryChanged: true);
      await check('restore contributor', () {
        appearances = [
          const LiquidGlassAppearance(tint: Color(0xA0FF3050)),
          ...appearances.skip(1),
        ];
      }, geometryChanged: true);
      await check(
        'relative motion',
        () {
          relativeMotion = 4;
        },
        geometryChanged: true,
        appearanceChanged: false,
      );
      await check(
        'group order',
        () {
          reverse = true;
        },
        geometryChanged: true,
        appearanceChanged: false,
      );
      await check(
        'uniform translation',
        () {
          translation = 8;
        },
        appearanceChanged: false,
        translated: true,
      );
      await check('appearance after translation', () {
        appearances = [
          const LiquidGlassAppearance(tint: Color(0x60FF8030), vibrancy: 0.3),
          ...appearances.skip(1),
        ];
      });

      for (final general in [false, true]) {
        for (final simultaneous in [false, true]) {
          // Reset to an integral raster phase before each independent case.
          translation = 0;
          appearances = const [
            LiquidGlassAppearance(tint: Color(0x303080FF)),
            LiquidGlassAppearance(tint: Color(0xC0FF8030)),
            LiquidGlassAppearance(tint: Color(0x7040CC70)),
          ];
          update.value++;
          layer
            // ignore: invalid_use_of_protected_member
            ..needsGeometryUpdate = true
            ..markNeedsPaint();
          await capture();
          final bounds = layer.debugGeometryMatteBounds;
          final texture = renderer.debugMatteTexture;
          final matte = await matteBytes();
          final cpuRevisions = revisions();
          final paints = layer.debugPaintCount;
          const delta = Offset(0.25, 0); // DPR 1: a quarter physical pixel.

          translation = delta.dx;
          if (!simultaneous) {
            final passes = FlutterGpuGeometryRenderer.debugDeferredPassCount;
            update.value++;
            if (!retained) layer.markNeedsPaint();
            await capture();
            expect(FlutterGpuGeometryRenderer.debugDeferredPassCount, passes);
            // The retained path can carry this motion in its effect layer
            // until the appearance refresh commits the translated inputs.
            if (!retained) {
              expect(layer.debugGeometryMatteBounds, bounds.shift(delta));
            }
          }
          appearances = [
            LiquidGlassAppearance(
              tint: const Color(0x906030FF),
              saturation: general ? 0.4 : 1,
            ),
            ...appearances.skip(1),
          ];
          final passes = FlutterGpuGeometryRenderer.debugDeferredPassCount;
          update.value++;
          if (!retained) layer.markNeedsPaint();
          final scene = await capture();
          expect(
            FlutterGpuGeometryRenderer.debugDeferredPassCount - passes,
            _baseline ? 2 : 1,
          );
          expect(revisions(), cpuRevisions);
          if (retained) expect(layer.debugPaintCount, paints);
          if (!_baseline) {
            expect(renderer.debugMatteTexture, same(texture));
            expect(await matteBytes(), matte);
            expect(
              layer.debugGeometryMatteBounds,
              bounds.shift(delta),
              reason:
                  'material-only encoding must retain the matte raster phase',
            );
          }

          layer
            // ignore: invalid_use_of_protected_member
            ..needsGeometryUpdate = true
            ..markNeedsPaint();
          final reference = await capture();
          var totalError = 0;
          var largeErrors = 0;
          var maxError = 0;
          for (var i = 0; i < scene.length; i++) {
            if (i % 4 == 3) continue; // Compare RGB, not opaque alpha.
            final error = (scene[i] - reference[i]).abs();
            totalError += error;
            if (error > 16) largeErrors++;
            if (error > maxError) maxError = error;
          }
          final samples = scene.length * 3 ~/ 4;
          final meanError = totalError / samples;
          final largeFraction = largeErrors / samples;
          // Unlike integral translations, a full build samples a newly snapped
          // analytic matte. Allow mean error <= 1/255, with >16/255 differences
          // in at most 1% of RGB samples. Report the maximum, too.
          // ignore: avoid_print
          print(
            'fractional retained=$retained general=$general '
            'simultaneous=$simultaneous mean=$meanError '
            'largeFraction=$largeFraction max=$maxError '
            'scene=${digest(scene)} reference=${digest(reference)}',
          );
          expect(meanError, lessThanOrEqualTo(1));
          expect(largeFraction, lessThanOrEqualTo(0.01));
        }
      }
    }, skip: skipProperGlassTests);
  }
}

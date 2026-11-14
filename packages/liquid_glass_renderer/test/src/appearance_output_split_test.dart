import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/render_liquid_glass_geometry.dart';
import 'package:material_ui/material_ui.dart';

import 'gpu_test_helpers.dart';
import 'shared.dart';
import 'submitted_scene_binding.dart';

void main() {
  runAppearanceOutputSplitTests(SubmittedSceneBinding());
}

/// Shared host/device workload; the device binding must capture submitted scenes.
void runAppearanceOutputSplitTests(TestWidgetsFlutterBinding binding) {
  final sceneCapture = (binding as SubmittedSceneCapture)
    ..captureWidth = 240
    ..captureHeight = 180;
  for (final retained in [false, true]) {
    testWidgets('a look change draws the atlas again (retained=$retained)', (
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

      // What the final shader reads of the geometry buffer.
      Future<Uint8List> matteBytes() async {
        final image = layer.debugGeometryImage!;
        final atlas = (await tester.runAsync(() => AtlasTexels.read(image)))!;
        final bounds = layer.debugGeometryMatteBounds;
        return Float32List.fromList([
          for (var y = 0; y < bounds.height.round(); y++)
            for (var x = 0; x < bounds.width.round(); x++)
              ...switch (atlas.pixel(x, y)) {
                (final a, final b, final c, final d) => [a, b, c, d],
              },
        ]).buffer.asUint8List();
      }

      // What the final shader reads of the looks beside the atlas.
      Future<Uint8List?> lookBytes() async {
        if (!layer.debugUsesShapeAppearances) return null;
        final atlas = (await tester.runAsync(
          () => AtlasTexels.read(
            layer.debugGeometryImage!,
            layer.debugGeometryPlace,
          ),
        ))!;
        final bounds = layer.debugGeometryMatteBounds;
        final values = <double>[];
        for (final image in layer.debugLookImages) {
          final look = (await tester.runAsync(() => AtlasTexels.read(image)))!;
          for (var y = 0; y < bounds.height.round(); y++) {
            for (var x = 0; x < bounds.width.round(); x++) {
              final (r, g, b, a) = atlas.lookAt(look, x, y);
              values.addAll([r, g, b, a]);
            }
          }
        }
        return Float32List.fromList(values).buffer.asUint8List();
      }

      Future<void> check(
        String name,
        void Function() change, {
        bool geometryChanged = false,
        bool uniform = false,
        bool appearanceChanged = true,
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
        // The atlas pass writes the looks beside the geometry.
        final redrawn = geometryChanged || (!uniform && appearanceChanged);
        expect(count, redrawn ? 1 : 0, reason: name);
        if (retained && !geometryChanged) {
          expect(layer.debugPaintCount, paints, reason: '$name retained path');
        }
        if (!geometryChanged) {
          expect(revisions(), oldRevisions, reason: '$name CPU matte revision');
        }
        if (redrawn) {
          expect(
            renderer.debugMatteTexture,
            isNot(same(oldMatte)),
            reason: name,
          );
        } else {
          expect(renderer.debugMatteTexture, same(oldMatte), reason: name);
          expect(layer.debugGeometryImage, same(oldImage), reason: name);
          expect(await matteBytes(), before, reason: '$name unchanged matte');
        }
        final matte = await matteBytes();
        final looks = await lookBytes();
        // Force the exact same inputs through a full encode.
        layer
          // ignore: invalid_use_of_protected_member
          ..needsGeometryUpdate = true
          ..markNeedsPaint();
        final reference = await capture();
        // An atlas kept for glass that now looks alike still holds the ring
        // tiles its looks needed, where a full encode reads deep constants.
        if (redrawn) {
          expect(
            await matteBytes(),
            matte,
            reason: '$name full matte reference',
          );
          expect(await lookBytes(), looks, reason: '$name look reference');
        }
        expect(scene, reference, reason: '$name submitted filter snapshot');
      }

      await check('unequal-alpha tint / three-way junction', () {
        appearances = [
          const LiquidGlassAppearance(tint: Color(0x906030FF)),
          ...appearances.skip(1),
        ];
      });
      await check('tint to general', () {
        appearances = [
          const LiquidGlassAppearance(
            tint: Color(0x906030FF),
            colorModel: LiquidGlassColorModel.direct(saturation: 0.4),
          ),
          ...appearances.skip(1),
        ];
      });
      await check('general appearance', () {
        appearances = [
          const LiquidGlassAppearance(
            tint: Color(0x906030FF),
            colorModel: LiquidGlassColorModel.direct(saturation: 1.6),
          ),
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
      await check(
        'zero crossing removes contributor',
        () {
          appearances = [
            const LiquidGlassAppearance(visibility: 0),
            ...appearances.skip(1),
          ];
        },
        geometryChanged: true,
        uniform: true,
      );
      expect(layer.debugUsesShapeAppearances, isFalse);
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
      );
      await check('appearance after translation', () {
        appearances = [
          const LiquidGlassAppearance(
            tint: Color(0x60FF8030),
            colorModel: LiquidGlassColorModel.direct(vibrancy: 0.3),
          ),
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
              colorModel: LiquidGlassColorModel.direct(
                saturation: general ? 0.4 : 1,
              ),
            ),
            ...appearances.skip(1),
          ];
          final passes = FlutterGpuGeometryRenderer.debugDeferredPassCount;
          update.value++;
          if (!retained) layer.markNeedsPaint();
          final scene = await capture();
          expect(
            FlutterGpuGeometryRenderer.debugDeferredPassCount - passes,
            1,
          );
          expect(revisions(), cpuRevisions);
          if (retained) expect(layer.debugPaintCount, paints);

          layer
            // ignore: invalid_use_of_protected_member
            ..needsGeometryUpdate = true
            ..markNeedsPaint();
          final reference = await capture();
          expect(
            scene,
            reference,
            reason:
                'a look change after a fractional move draws the atlas a '
                'full build draws',
          );
        }
      }
    }, skip: skipProperGlassTests);
  }
}

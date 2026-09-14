import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/multi_shader_builder.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_render_scope.dart';
import 'package:liquid_glass_renderer/src/rendering/consolidated_fake_glass_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';

import 'shared.dart';
import 'submitted_scene_binding.dart';

void main() => runOpacityEndpointCacheTests(SubmittedSceneBinding());

void runOpacityEndpointCacheTests(SubmittedSceneCapture binding) {
  for (final fake in [true, false]) {
    testWidgets(
      'bounded endpoint caches ${fake ? "fake" : "real"}',
      (
        tester,
      ) async {
        final oldSize = (binding.captureWidth, binding.captureHeight);
        binding
          ..captureWidth = 240
          ..captureHeight = 200;
        tester.view
          ..physicalSize = const Size(240, 200)
          ..devicePixelRatio = 1;
        addTearDown(() {
          tester.view.reset();
          binding
            ..captureNextScene = false
            ..captured = null
            ..captureWidth = oldSize.$1
            ..captureHeight = oldSize.$2;
        });
        final fades = List.generate(
          3,
          (_) => AnimationController(
            vsync: tester,
            value: 1,
            duration: const Duration(seconds: 1),
          ),
        );
        addTearDown(() {
          for (final fade in fades) {
            fade.dispose();
          }
        });
        await tester.runAsync(
          () => MultiShaderBuilder.precacheShaders([
            ShaderKeys.fakeGlassSurface,
            ShaderKeys.liquidGlassRender,
            ShaderKeys.liquidGlassMaterialRender,
            ShaderKeys.liquidGlassTintRender,
          ]),
        );

        Future<void> mount({bool omitFirst = false}) async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpWidget(_scene(fake, fades, omitFirst: omitFirst));
          if (!fake) {
            await pumpUntilGlassReady(tester);
            for (var frame = 0; frame < 60; frame++) {
              final scopes = tester.widgetList<LiquidGlassRenderScope>(
                find.byType(LiquidGlassRenderScope),
              );
              if (scopes.length == 1 &&
                  !scopes.single.consolidatesFakeBackdrop) {
                break;
              }
              await tester.pump(const Duration(milliseconds: 16));
            }
            final scope = tester.widget<LiquidGlassRenderScope>(
              find.byType(LiquidGlassRenderScope),
            );
            expect(scope.useFake, isFalse);
            expect(scope.consolidatesFakeBackdrop, isFalse);
            expect(
              tester.allRenderObjects
                  .whereType<RenderLiquidGlassLayer>()
                  .toSet()
                  .single
                  .gpuGeometryRenderer,
              isNotNull,
            );
          }
          await tester.pumpAndSettle();
        }

        Future<Uint8List> capture() async {
          binding
            ..captured = null
            ..captureNextScene = true
            ..scheduleFrame();
          await tester.pump();
          expect(binding.captureNextScene, isFalse);
          expect(binding.captured, isNotNull);
          final image = (await tester.runAsync(() => binding.captured!))!;
          try {
            final bytes = (await tester.runAsync(image.toByteData))!;
            return Uint8List.fromList(
              bytes.buffer.asUint8List(
                bytes.offsetInBytes,
                bytes.lengthInBytes,
              ),
            );
          } finally {
            image.dispose();
            binding.captured = null;
          }
        }

        await mount(omitFirst: true);
        final rightOnly = await capture();
        await mount();
        final original = await capture();
        expect(original, isNot(orderedEquals(rightOnly)));
        final realOwner = fake
            ? null
            : tester.allRenderObjects
                  .whereType<RenderLiquidGlassLayer>()
                  .toSet()
                  .single;
        final fakeOwner = fake
            ? tester.allRenderObjects
                  .whereType<RenderConsolidatedFakeGlassLayer>()
                  .toSet()
                  .single
            : null;
        int cacheCount() =>
            fakeOwner?.debugIndependentPassCount ??
            realOwner!.debugIndependentPassCount;
        int workCount() =>
            fakeOwner?.debugIndependentPassRecordCount ??
            FlutterGpuGeometryRenderer.debugTotalRenderCount;
        int paintCount() =>
            fakeOwner?.debugPaintCount ?? realOwner!.debugPaintCount;
        final ownerPaints = <int>[];
        Future<Uint8List> frame(List<double> values) async {
          for (var i = 0; i < 3; i++) {
            fades[i].value = values[i];
          }
          final pixels = await capture();
          ownerPaints.add(paintCount());
          expect(cacheCount(), lessThanOrEqualTo(4), reason: 'G + one union');
          return pixels;
        }

        expect(cacheCount(), 0, reason: 'Opaque has no temporary passes');
        final cold = workCount();
        final half = await frame([0.5, 0.5, 0.5]);
        expect(workCount() - cold, 3);
        final warm = workCount();
        final paints = paintCount();
        // .001 rounds to zero but is not a settled endpoint. .999 is tested
        // while other groups remain fractional, bypassing the opaque shortcut.
        for (final value in [0.001, 0.5, 0.999, 0.5]) {
          await frame([value, 0.5, 0.5]);
          expect(cacheCount(), 3);
          expect(
            workCount(),
            warm,
            reason: 'Unfinished isolated cache was lost',
          );
        }
        _expectPixels(await capture(), half);
        expect(
          paintCount(),
          paints,
          reason: 'Boundary-isolated fractional fade',
        );

        // Exact native endpoints can still be unfinished animations. No elapsed
        // time is pumped: forward/reverse changes status without advancing value.
        for (final endpoint in [0.0, 1.0]) {
          if (endpoint == 0) {
            unawaited(fades.first.forward(from: 0));
          } else {
            unawaited(fades.first.reverse(from: 1));
          }
          await capture();
          expect(cacheCount(), 3);
          expect(workCount(), warm);
          await frame([0.5, 0.5, 0.5]);
          expect(workCount(), warm);
        }

        // Rounded opaque sources keep their ordered isolated passes while any
        // other source is fractional. Changing alpha must build no new union.
        for (final values in [
          [0.999, 0.999, 0.5],
          [0.5, 0.999, 0.999],
          [0.999, 0.5, 0.999],
          [0.999, 0.999, 0.5],
        ]) {
          final before = workCount();
          await frame(values);
          expect(cacheCount(), 3);
          expect(workCount() - before, 0);
          await capture();
          expect(workCount() - before, 0);
        }
        final beforeReverse = workCount();
        await frame([0.5, 0.5, 0.5]);
        expect(workCount(), beforeReverse);
        expect(cacheCount(), 3, reason: 'Only ordered isolated passes remain');

        // Settled zero evicts only its dormant isolated pass. A fresh fade may
        // recover its weak GPU filter or rebuild that pass once.
        // Native 0->positive boundary repaint is NOT
        // counted as geometry work; owner counts are captured independently.
        await frame([0, 0.5, 0.5]);
        expect(cacheCount(), 2);
        final beforeNewFade = workCount();
        await frame([0.5, 0.5, 0.5]);
        expect(workCount() - beforeNewFade, fake ? 1 : lessThanOrEqualTo(1));
        final zero = await frame([0, 1, 1]);
        expect(
          cacheCount(),
          1,
          reason: 'Only the current survivor union remains',
        );
        _expectPixels(zero, rightOnly);
        _expectPixels(await capture(), rightOnly);
        await frame([0, 0, 0]);
        expect(
          cacheCount(),
          0,
          reason: 'Settled hidden groups release everything',
        );
        final beforeRestore = workCount();
        _expectPixels(await frame([1, 1, 1]), original);
        expect(cacheCount(), 0);
        expect(
          workCount(),
          beforeRestore,
          reason: 'Original needs no subset SDF',
        );
        // Preserve every opaque source run through an unfinished all-native-
        // alpha255 frame, so reversing the fade does not rebuild geometry.
        final beforeCommonReturn = workCount();
        await frame([0.5, 1, 1]);
        expect(
          workCount() - beforeCommonReturn,
          fake ? 3 : lessThanOrEqualTo(3),
        );
        final commonWarm = workCount();
        await frame([0.999, 1, 1]);
        expect(cacheCount(), 3);
        await frame([0.5, 1, 1]);
        expect(workCount(), commonWarm);
        // Rounded zero selects a survivor union without ending the fade.
        // Returning to fractional source runs must not evict that same union.
        await frame([0.001, 1, 1]);
        final zeroWarm = workCount();
        expect(zeroWarm - commonWarm, fake ? 1 : lessThanOrEqualTo(1));
        for (final alpha in [0.5, 0.001, 0.5, 0.001]) {
          await frame([alpha, 1, 1]);
          expect(workCount(), zeroWarm);
          expect(cacheCount(), 4);
        }
        await frame([1, 1, 1]);
        expect(cacheCount(), 0);
        // Report native owner paints separately if an assertion above fails.
        expect(ownerPaints.every((count) => count >= paints), isTrue);
      },
      skip: !fake && skipProperGlassTests,
    );
  }
}

void _expectPixels(Uint8List actual, Uint8List expected) {
  expect(actual.length, expected.length);
  var mismatches = 0;
  var maxError = 0;
  for (var i = 0; i < actual.length; i++) {
    final error = (actual[i] - expected[i]).abs();
    if (error > 3) mismatches++;
    if (error > maxError) maxError = error;
  }
  expect(mismatches, 0, reason: 'RGBA channels >3; max error $maxError');
}

Widget _scene(
  bool fake,
  List<AnimationController> fades, {
  bool omitFirst = false,
}) => MediaQuery(
  data: const MediaQueryData(size: Size(240, 200)),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xFFE0D8C8)),
          const Positioned(
            left: 0,
            top: 82,
            right: 0,
            height: 15,
            child: ColoredBox(color: Color(0xFF425880)),
          ),
          LiquidGlassLayer(
            fake: fake,
            settings: const LiquidGlassSettings(
              frost: 8,
              highlight: 0,
              chromaticAberration: 0,
            ),
            child: Stack(
              children: [
                for (var i = omitFirst ? 1 : 0; i < 3; i++)
                  Positioned(
                    left: 12.0 + i * 76,
                    top: 56,
                    // Keep native opacity's 0/nonzero repaint-boundary
                    // transitions below the material owner. Contained source
                    // holders still have to park/rejoin selected branches.
                    child: RepaintBoundary(
                      child: FadeTransition(
                        opacity: fades[i],
                        child: LiquidGlass.grouped(
                          shape: const LiquidRoundedRectangle(borderRadius: 12),
                          child: SizedBox(
                            width: 64,
                            height: 88,
                            child: Center(
                              child: ColoredBox(
                                color: [
                                  Colors.red,
                                  Colors.green,
                                  Colors.blue,
                                ][i],
                                child: const SizedBox.square(dimension: 16),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  ),
);

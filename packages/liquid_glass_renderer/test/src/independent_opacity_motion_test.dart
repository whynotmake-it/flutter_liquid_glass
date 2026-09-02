import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/multi_shader_builder.dart';
import 'package:liquid_glass_renderer/src/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_render_scope.dart';
import 'package:liquid_glass_renderer/src/rendering/consolidated_fake_glass_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';

import 'shared.dart';
import 'submitted_scene_binding.dart';

void main() => runIndependentOpacityMotionTests(SubmittedSceneBinding());

// Model an animation passing through an endpoint without settling there.
// Exact completed endpoints have separate cache-release coverage.
class _ActiveMotionOpacity extends ProxyAnimation {
  _ActiveMotionOpacity(super.animation);

  @override
  AnimationStatus get status => AnimationStatus.forward;
}

void runIndependentOpacityMotionTests(SubmittedSceneCapture binding) {
  if (const bool.fromEnvironment('PROBE_SINGULAR_SUBSET') ||
      const bool.fromEnvironment('PROBE_ALL_SINGULAR')) {
    _singularOpacityTests(binding);
    return;
  }
  const stress = bool.fromEnvironment('PROBE_GPU_STRESS');
  test('fractional noise allowance stays sparse and bounded', () {
    final expected = Uint8List(240 * 200 * 4);
    final actual = Uint8List(expected.length);
    const noise = (channels: 64, max: 9);
    actual.fillRange(0, 64, 9);
    expect(_errors(actual, expected, 'sparse', noise), isEmpty);
    actual[64] = 4;
    expect(_errors(actual, expected, 'too many', noise), isNotEmpty);
    actual[64] = 0;
    actual[0] = 10;
    expect(_errors(actual, expected, 'too large', noise), isNotEmpty);
    actual.fillRange(0, actual.length, 4);
    expect(_errors(actual, expected, 'whole-frame drift', noise), isNotEmpty);
  });
  const opaqueOnly = bool.fromEnvironment('PROBE_MOTION_OPAQUE');
  const activeAlpha = opaqueOnly ? 1.0 : 0.5;
  for (final (fake, destination, dormantRebase) in const [
    (true, Offset(31, -85), false),
    (false, Offset(31, -85), false),
    if (!bool.fromEnvironment('PROBE_DORMANT_APPEARANCE') &&
        !bool.fromEnvironment('PROBE_FILTER_OUTPUT_ALPHA')) ...[
      (false, Offset(31.25, -85.5), false),
      (false, Offset(31.25, -85.5), true),
    ],
  ]) {
    testWidgets(
      'independent ${fake ? "fake" : "real"} opacity first moved scene '
      '$destination dormant=$dormantRebase',
      (tester) async {
        final oldWidth = binding.captureWidth;
        final oldHeight = binding.captureHeight;
        addTearDown(() {
          binding
            ..captureNextScene = false
            ..captured = null
            ..captureWidth = oldWidth
            ..captureHeight = oldHeight;
        });
        binding
          ..captureNextScene = false
          ..captured = null
          ..captureWidth = 240
          ..captureHeight = 200;
        tester.view
          ..physicalSize =
              stress || const bool.fromEnvironment('PROBE_LARGE_VIEWPORT')
              ? const Size(1080, 2100)
              : const Size(240, 200)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        Future<void> Function()? verifyStress;
        Future<void> Function()? queuePressure;
        if (stress) {
          final rasterTimes = <int>[];
          final completionTimes = <int>[];
          final recorder = ui.PictureRecorder();
          const _Background(workload: true).paint(
            Canvas(recorder),
            const Size(1080, 2100),
          );
          final pressurePicture = recorder.endRecording();
          addTearDown(pressurePicture.dispose);
          queuePressure = () async {
            final watch = Stopwatch()..start();
            final image = await pressurePicture.toImage(1080, 2100);
            // Image creation alone may finish before GPU execution. Readback
            // supplies completion evidence (plus a known test-only copy cost).
            try {
              await image.toByteData();
              watch.stop();
              completionTimes.add(watch.elapsedMicroseconds);
            } finally {
              image.dispose();
            }
          };
          void timings(List<ui.FrameTiming> frames) => rasterTimes.addAll(
            frames.map((frame) => frame.rasterDuration.inMicroseconds),
          );
          SchedulerBinding.instance.addTimingsCallback(timings);
          addTearDown(
            () => SchedulerBinding.instance.removeTimingsCallback(timings),
          );
          verifyStress = () async {
            // Native timing batches arrive asynchronously after submission.
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(seconds: 1)),
            );
            final overBudget = rasterTimes.where((time) => time > 16667).length;
            final slowCompletions = completionTimes
                .where((time) => time > 16667)
                .length;
            final meanCompletion = completionTimes.isEmpty
                ? 0
                : completionTimes.reduce((a, b) => a + b) /
                      completionTimes.length;
            debugPrint(
              'OPACITY_STRESS frames=${rasterTimes.length} '
              'over16ms=$overBudget '
              'snapshots=${completionTimes.length} '
              'snapshotOver16ms=$slowCompletions '
              'snapshotMeanUs=$meanCompletion',
            );
            // Snapshot completion includes GPU work and callback scheduling;
            // it is not a hardware GPU timer or an ordinary frame-time claim.
            if (!const bool.fromEnvironment('PROBE_QUEUED_OVERDRAW')) {
              expect(slowCompletions, greaterThanOrEqualTo(5));
            }
            if (const bool.fromEnvironment('PROBE_CONTINUOUS_OVERDRAW')) {
              expect(
                overBudget,
                greaterThanOrEqualTo(5),
                reason:
                    'Continuous stress must exceed the actual frame budget.',
              );
            }
          };
        }
        final left = AnimationController(vsync: tester, value: 1);
        final activeLeft = _ActiveMotionOpacity(left);
        addTearDown(() => activeLeft.parent = null);
        final right = AnimationController(vsync: tester, value: 1);
        final translation = ValueNotifier(Offset.zero);
        final clipWidth = ValueNotifier<double>(204);
        final secondAppearance = ValueNotifier(_mixedAppearance());
        addTearDown(secondAppearance.dispose);
        addTearDown(left.dispose);
        addTearDown(right.dispose);
        addTearDown(translation.dispose);
        addTearDown(clipWidth.dispose);
        await tester.runAsync(
          () => MultiShaderBuilder.precacheShaders([
            ShaderKeys.fakeGlassSurface,
            ShaderKeys.liquidGlassRender,
            ShaderKeys.liquidGlassMaterialRender,
            ShaderKeys.liquidGlassTintRender,
          ]),
        );

        Future<void> mount({
          required Offset position,
          double alpha = 1,
          bool includeLeft = true,
          bool moving = false,
          bool keepAnimationActive = false,
          double viewportWidth = 204,
        }) async {
          await tester.pumpWidget(const SizedBox.shrink());
          left.value = alpha;
          right.value = 1;
          translation.value = position;
          clipWidth.value = viewportWidth;
          await tester.pumpWidget(
            _scene(
              fake: fake,
              left: keepAnimationActive ? activeLeft : left,
              right: right,
              includeLeft: includeLeft,
              position: position,
              translation: moving ? translation : null,
              clipWidth: clipWidth,
              secondAppearance: secondAppearance,
            ),
          );
          if (!fake) {
            await pumpUntilGlassReady(tester);
            for (var i = 0; i < 60; i++) {
              final scopes = tester.widgetList<LiquidGlassRenderScope>(
                find.byType(LiquidGlassRenderScope),
              );
              if (scopes.length == 1 &&
                  !scopes.single.consolidatesFakeBackdrop) {
                break;
              }
              await tester.pump(const Duration(milliseconds: 16));
            }
            final scopes = tester.widgetList<LiquidGlassRenderScope>(
              find.byType(LiquidGlassRenderScope),
            );
            expect(scopes, hasLength(1));
            expect(scopes.single.useFake, isFalse);
            expect(scopes.single.consolidatesFakeBackdrop, isFalse);
            final owners = tester.allRenderObjects
                .whereType<RenderLiquidGlassLayer>()
                .toSet();
            expect(owners, hasLength(1));
            expect(owners.single.gpuGeometryRenderer, isNotNull);
          }
          // Only mounting/reference construction may settle. Every mutation in
          // the retained subject below gets exactly one submitted-scene pump.
          await tester.pumpAndSettle();
        }

        Future<Uint8List> capture() async {
          // Keep one independent full-display workload ahead of this scene.
          // No extra pump may settle the geometry/opacity mutation under test.
          final pressure = queuePressure?.call();
          try {
            binding
              ..captured = null
              ..captureNextScene = true
              ..scheduleFrame();
            await tester.pump();
            expect(binding.captureNextScene, isFalse);
            expect(binding.captured, isNotNull);
            final image = (await tester.runAsync(() => binding.captured!))!;
            try {
              expect(image.width, 240);
              expect(image.height, 200);
              final data = (await tester.runAsync(image.toByteData))!;
              final bytes = Uint8List.fromList(
                data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
              );
              expect(bytes.length, 240 * 200 * 4);
              return bytes;
            } finally {
              image.dispose();
              binding.captured = null;
            }
          } finally {
            if (pressure != null) {
              await tester.runAsync(() => pressure);
            }
          }
        }

        List<ui.ImageFilter> anchorFilters() {
          final filters = <ui.ImageFilter>[];
          void collect(Layer layer) {
            if (layer is BackdropFilterLayer && layer.filter != null) {
              filters.add(layer.filter!);
            }
            if (layer is ContainerLayer) {
              for (
                var child = layer.firstChild;
                child != null;
                child = child.nextSibling
              ) {
                collect(child);
              }
            }
          }

          collect(tester.binding.renderViews.single.debugLayer!);
          return filters;
        }

        if (const bool.fromEnvironment('PROBE_QUEUED_OVERDRAW')) {
          await mount(
            position: Offset.zero,
            alpha: .5,
            moving: true,
            keepAnimationActive: true,
          );
          final first = await capture();
          translation.value = destination;
          final second = await capture();
          expect(first, isNot(orderedEquals(second)));
          final work = FlutterGpuGeometryRenderer.debugTotalRenderCount;
          final pending = <Future<ui.Image>>[];
          for (var frame = 0; frame < 12; frame++) {
            translation.value = frame.isEven ? Offset.zero : destination;
            binding
              ..captured = null
              ..captureNextScene = true
              ..scheduleFrame();
            await tester.pump();
            pending.add(binding.captured!);
          }
          final failures = <String>[];
          for (var frame = 0; frame < pending.length; frame++) {
            final image = (await tester.runAsync(() => pending[frame]))!;
            try {
              final data = (await tester.runAsync(image.toByteData))!;
              failures.addAll(
                _errors(
                  data.buffer.asUint8List(
                    data.offsetInBytes,
                    data.lengthInBytes,
                  ),
                  frame.isEven ? first : second,
                  'queued overload frame $frame',
                ),
              );
            } finally {
              image.dispose();
            }
          }
          binding.captured = null;
          if (!fake) {
            expect(FlutterGpuGeometryRenderer.debugTotalRenderCount, work);
          }
          debugPrint('QUEUED_PIXEL_ERRORS ${failures.length}');
          await verifyStress?.call();
          expect(failures, isEmpty, reason: failures.join('\n'));
          return;
        }
        if (!fake && const bool.fromEnvironment('PROBE_DORMANT_APPEARANCE')) {
          const mode = String.fromEnvironment('PROBE_MATERIAL_MODE');
          expect(mode, isIn(['tint', 'full']));
          await mount(position: Offset.zero, alpha: .5);
          final oldHalf = await capture();
          final owner = tester.allRenderObjects
              .whereType<RenderLiquidGlassLayer>()
              .toSet()
              .single;
          final sources = tester.allRenderObjects
              .whereType<RenderLiquidGlass>()
              .toSet();
          final anchors = anchorFilters();
          expect(anchors, isNotEmpty);
          expect(
            owner.debugIndependentMaterialKinds,
            contains((2, true, mode == 'tint')),
          );
          left.value = 1;
          final oldOpaque = await capture();
          // An opaque/fractional history comparison alone can pass when both
          // histories lose their material. Check an interior pixel against
          // the opaque surface composited over the known checkerboard too.
          const translated =
              String.fromEnvironment('PROBE_CAPTURE_FRAME') == 'translated';
          const sampleX = 45 + (translated ? 13 : 0);
          const sampleY = 120 - (translated ? 17 : 0);
          final background = (sampleX ~/ 24 + sampleY ~/ 20).isEven
              ? const [36, 104, 172]
              : const [237, 203, 169];
          const sample = (sampleY * 240 + sampleX) * 4;
          for (var channel = 0; channel < 3; channel++) {
            final expected =
                (oldOpaque[sample + channel] * 128 +
                    background[channel] * 127) /
                255;
            expect(
              oldHalf[sample + channel],
              closeTo(expected, 3),
              reason:
                  'interior material must fade in the same coordinate frame',
            );
          }
          expect(owner.debugIndependentPassCount, 0);
          final hits = GpuAllocationDiagnostics.filterRecoveryHits;
          secondAppearance.value = _mixedAppearance(changed: true);
          final changedOpaque = await capture();
          final opaqueCount = FlutterGpuGeometryRenderer.debugTotalRenderCount;
          left.value = .5;
          final changedHalf = await capture();
          expect(GpuAllocationDiagnostics.filterRecoveryHits, hits);
          expect(
            FlutterGpuGeometryRenderer.debugTotalRenderCount,
            opaqueCount + 2,
          );
          expect(
            owner.debugIndependentMaterialKinds,
            contains((2, true, false)),
          );
          expect(
            tester.allRenderObjects.whereType<RenderLiquidGlass>().toSet(),
            unorderedEquals(sources),
          );
          final warmed = FlutterGpuGeometryRenderer.debugTotalRenderCount;
          final stable = await capture();
          expect(FlutterGpuGeometryRenderer.debugTotalRenderCount, warmed);
          expect(GpuAllocationDiagnostics.filterRecoveryHits, hits);
          expect(owner.debugMaterialImage, isNotNull);
          await mount(position: Offset.zero);
          final freshOpaque = await capture();
          left.value = .5;
          final freshHalf = await capture();
          expect(_errors(oldOpaque, freshOpaque), isNotEmpty);
          expect(_errors(oldHalf, freshHalf), isNotEmpty);
          final failures = <String>[
            ..._errors(changedOpaque, freshOpaque, 'changed opaque'),
            ..._errors(changedHalf, freshHalf, 'changed half'),
            ..._errors(stable, changedHalf, 'changed stable'),
          ];
          expect(
            anchors,
            isNotEmpty,
          ); // Keep old native filters alive throughout.
          expect(failures, isEmpty, reason: failures.join('\n'));
          await verifyStress?.call();
          return;
        }

        final fractionalPosition =
            destination.dx != destination.dx.roundToDouble() ||
            destination.dy != destination.dy.roundToDouble();
        if (!fake &&
            (fractionalPosition ||
                const bool.fromEnvironment('PROBE_MATCHED_HISTORY')) &&
            !opaqueOnly &&
            !const bool.fromEnvironment('PROBE_FRESH_MATTE_EQUIVALENCE')) {
          // Fresh SDF rasterization and fractional resampling are separate
          // contracts. Match the encoded phase and motion history here.
          final failures = <String>[];
          Future<List<Uint8List>> history({required bool recover}) async {
            await mount(
              position: Offset.zero,
              moving: true,
              keepAnimationActive: !recover,
            );
            await capture();
            left.value = .5;
            final images = <Uint8List>[await capture()];
            const materialMode = String.fromEnvironment('PROBE_MATERIAL_MODE');
            if (materialMode.isNotEmpty) {
              final owner = tester.allRenderObjects
                  .whereType<RenderLiquidGlassLayer>()
                  .toSet()
                  .single;
              expect(owner.debugUsesShapeAppearances, isTrue);
              expect(owner.debugMaterialImage, isNotNull);
              expect(
                owner.debugIndependentMaterialKinds,
                contains((2, true, materialMode == 'tint')),
              );
            }
            final anchors = anchorFilters();
            expect(anchors, isNotEmpty);
            final count = FlutterGpuGeometryRenderer.debugTotalRenderCount;
            final hits = GpuAllocationDiagnostics.filterRecoveryHits;
            Future<void> next() async {
              images.add(await capture());
              expect(
                _errors(
                  await capture(),
                  images.last,
                  'no delayed capture correction',
                ),
                isEmpty,
              );
              expect(FlutterGpuGeometryRenderer.debugTotalRenderCount, count);
            }

            translation.value = destination;
            await next();
            // Both values render native alpha255. Only exact 1 settles the
            // animation and releases its temporary passes for weak recovery.
            left.value = recover ? 1 : .999;
            await next();
            if (dormantRebase) {
              clipWidth.value = 140;
              await next();
            }
            left.value = .5;
            await next();
            expect(
              GpuAllocationDiagnostics.filterRecoveryHits - hits,
              recover ? 2 : 0,
            );
            clipWidth.value = 140;
            await next();
            clipWidth.value = 204;
            await next();
            translation.value = Offset.zero;
            await next();
            if (const bool.fromEnvironment('PROBE_ROUND_TRIP_IDENTITY')) {
              failures.addAll(
                _errors(images.last, images.first, 'history move back'),
              );
            }
            left.value = 0;
            await next();
            left.value = 1;
            await next();
            expect(
              anchors,
              isNotEmpty,
            ); // Test-only roots, not production policy.
            return images;
          }

          final reference = await history(recover: false);
          const controlRepeat = bool.fromEnvironment(
            'PROBE_RECOVERY_CONTROL_REPEAT',
          );
          final recovered = await history(
            recover: !controlRepeat,
          );
          expect(recovered, hasLength(reference.length));
          for (var i = 0; i < reference.length; i++) {
            // Identical Pixel controls varied in up to 36/192000 channels,
            // max 9. Bound sparse low-bit noise, never a broad scene change.
            failures.addAll(
              _errors(
                recovered[i],
                reference[i],
                'history frame $i',
                controlRepeat || !fractionalPosition
                    ? (channels: 0, max: 3)
                    : (channels: 64, max: 9),
              ),
            );
          }
          expect(failures, isEmpty, reason: failures.join('\n'));
          await verifyStress?.call();
          return;
        }

        // The negative Y displacement crosses the fixed clip's TOP edge; X
        // simultaneously crosses its RIGHT edge. References have no notifier.
        await mount(position: destination, alpha: activeAlpha);
        final destinationHalf = await capture();
        Uint8List? destinationNearOpaque;
        if (!opaqueOnly && const bool.fromEnvironment('PROBE_NEAR_OPAQUE')) {
          await mount(position: destination, alpha: .99931);
          destinationNearOpaque = await capture();
        }
        await mount(
          position: destination,
          alpha: activeAlpha,
          viewportWidth: 140,
        );
        final destinationNarrow = await capture();
        expect(_errors(destinationNarrow, destinationHalf), isNotEmpty);
        await mount(position: destination, viewportWidth: 140);
        final destinationNarrowFull = await capture();
        await mount(position: destination);
        final destinationFull = await capture();
        await mount(position: destination, includeLeft: false);
        final destinationRightOnly = await capture();
        if (!opaqueOnly) {
          expect(_errors(destinationHalf, destinationFull), isNotEmpty);
        }
        expect(_errors(destinationFull, destinationRightOnly), isNotEmpty);

        await mount(position: Offset.zero, moving: true);
        final initialFull = await capture();
        expect(_errors(initialFull, destinationFull), isNotEmpty);
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
        final renderer = realOwner?.gpuGeometryRenderer;
        final beforeWarmup = FlutterGpuGeometryRenderer.debugTotalRenderCount;
        left.value = activeAlpha;
        final initialHalf = await capture();
        if (!opaqueOnly) expect(_errors(initialHalf, initialFull), isNotEmpty);
        expect(_errors(initialHalf, destinationHalf), isNotEmpty);
        final warmed = FlutterGpuGeometryRenderer.debugTotalRenderCount;
        final initialPlacement = realOwner?.debugOpacityPlacement;
        expect(
          warmed - beforeWarmup,
          fake || opaqueOnly ? 0 : 2,
          reason: 'Only fade entry may construct the two isolated subsets.',
        );
        final localCount = renderer?.debugRenderCount;
        final paints = fakeOwner?.debugPaintCount ?? realOwner!.debugPaintCount;
        final recordings = fakeOwner?.debugIndependentPassRecordCount;

        void expectCached(String stage) {
          expect(
            FlutterGpuGeometryRenderer.debugTotalRenderCount,
            warmed,
            reason: '$stage must not submit new SDF work.',
          );
          expect(renderer?.debugRenderCount, localCount, reason: stage);
          expect(
            fakeOwner?.debugPaintCount ?? realOwner!.debugPaintCount,
            paints,
            reason: '$stage must remain owner-retained.',
          );
          expect(
            fakeOwner?.debugIndependentPassRecordCount,
            recordings,
            reason: '$stage must reuse fake display lists.',
          );
          if (realOwner != null) {
            expect(identical(realOwner.gpuGeometryRenderer, renderer), isTrue);
          }
        }

        translation.value = destination;
        final moved =
            await capture(); // FIRST submitted frame, no catch-up pump.
        expectCached('first moved half frame');
        final stable = await capture();
        expectCached('following stable half frame');
        final failures = <String>[
          ..._errors(moved, destinationHalf, 'first moved half'),
          ..._errors(stable, destinationHalf, 'following half'),
          ..._errors(stable, moved, 'no second-frame correction'),
        ];
        if (opaqueOnly) {
          expect(failures, isEmpty, reason: failures.join('\n'));
          await verifyStress?.call();
          return;
        }

        // Change fractional alpha while retaining the same warmed subsets.
        if (destinationNearOpaque != null) {
          left.value = .99931;
          final firstNearOpaque = await capture();
          final stableNearOpaque = await capture();
          failures
            ..addAll(
              _errors(firstNearOpaque, destinationNearOpaque, 'near-one first'),
            )
            ..addAll(
              _errors(
                stableNearOpaque,
                destinationNearOpaque,
                'near-one stable',
              ),
            )
            ..addAll(
              _errors(stableNearOpaque, firstNearOpaque, 'near-one correction'),
            );
          expectCached('near-one native alpha255');
          left.value = .5;
          failures.addAll(
            _errors(await capture(), destinationHalf, 'near-one reverse'),
          );
          expectCached('near-one reversal');
        }
        left.value = .25;
        await capture();
        expectCached('quarter alpha');
        left.value = .5;
        failures.addAll(
          _errors(await capture(), destinationHalf, 'half again'),
        );
        expectCached('half alpha restored');
        // Test-only roots make recovery deterministic: production retains only
        // weak references and may legitimately miss after garbage collection.
        final filterAnchors = <ui.ImageFilter>[];
        if (!fake) {
          filterAnchors.addAll(anchorFilters());
          expect(filterAnchors, isNotEmpty);
        }
        // Hide before restoring full: the survivor is already warm. Restoring
        // full intentionally releases temporary frames, so a later fade would
        // legitimately require new one-time construction.
        left.value = 0;
        final firstZero = await capture();
        failures.addAll(
          _errors(firstZero, destinationRightOnly, 'left zero'),
        );
        expectCached('left zero');
        final stableZero = await capture();
        failures
          ..addAll(
            _errors(stableZero, destinationRightOnly, 'stable left zero'),
          )
          ..addAll(_errors(stableZero, firstZero, 'zero frame correction'));
        expectCached('stable left zero');
        left.value = 1;
        failures.addAll(
          _errors(await capture(), destinationFull, 'full restored'),
        );
        expectCached('full restored');
        if (!fake) {
          if (dormantRebase) {
            clipWidth.value = 140;
            failures.addAll(
              _errors(
                await capture(),
                destinationNarrowFull,
                'dormant clip rebase',
              ),
            );
            expect(FlutterGpuGeometryRenderer.debugTotalRenderCount, warmed);
          }
          final hits = GpuAllocationDiagnostics.filterRecoveryHits;
          left.value = .5;
          failures.addAll(
            _errors(
              await capture(),
              dormantRebase ? destinationNarrow : destinationHalf,
              'recovered half',
            ),
          );
          expect(GpuAllocationDiagnostics.filterRecoveryHits - hits, 2);
          expect(FlutterGpuGeometryRenderer.debugTotalRenderCount, warmed);
          clipWidth.value = 140;
          failures.addAll(
            _errors(
              await capture(),
              destinationNarrow,
              'recovered clip change',
            ),
          );
          expect(FlutterGpuGeometryRenderer.debugTotalRenderCount, warmed);
          clipWidth.value = 204;
          failures.addAll(
            _errors(
              await capture(),
              destinationHalf,
              'recovered clip restored',
            ),
          );
          translation.value = Offset.zero;
          final movedBack = await capture();
          if (const bool.fromEnvironment('PROBE_CHECK_BOUNDS')) {
            expect(
              realOwner!.debugOpacityPlacement,
              unorderedEquals(initialPlacement!),
              reason:
                  'Move-back must restore effective capture bounds/mapping.',
            );
          }
          failures.addAll(
            _errors(movedBack, initialHalf, 'recovered first move'),
          );
          final afterMove = FlutterGpuGeometryRenderer.debugTotalRenderCount;
          expect(afterMove, warmed, reason: 'Recovered motion must reuse SDF.');
          failures.addAll(
            _errors(await capture(), initialHalf, 'recovered stable'),
          );
          expect(FlutterGpuGeometryRenderer.debugTotalRenderCount, afterMove);
          expect(filterAnchors, isNotEmpty);
        }
        expect(failures, isEmpty, reason: failures.join('\n'));
        await verifyStress?.call();
      },
      skip: !fake && skipProperGlassTests,
    );
  }
}

void _singularOpacityTests(SubmittedSceneCapture binding) {
  const allSingular = bool.fromEnvironment('PROBE_ALL_SINGULAR');
  const stress = bool.fromEnvironment('PROBE_GPU_STRESS');
  testWidgets('zero-scale glass fades and restores; all=$allSingular', (
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
    final left = AnimationController(vsync: tester, value: 1);
    final right = AnimationController(vsync: tester, value: 1);
    final scale = ValueNotifier<double>(1);
    final clip = ValueNotifier<double>(204);
    final completionTimes = <int>[];
    Future<void> Function()? queuePressure;
    if (stress) {
      final recorder = ui.PictureRecorder();
      const _Background(workload: true).paint(
        Canvas(recorder),
        const Size(1080, 2100),
      );
      final picture = recorder.endRecording();
      addTearDown(picture.dispose);
      queuePressure = () async {
        final watch = Stopwatch()..start();
        final image = await picture.toImage(1080, 2100);
        try {
          await image.toByteData();
          completionTimes.add(watch.elapsedMicroseconds);
        } finally {
          image.dispose();
        }
      };
    }
    addTearDown(left.dispose);
    addTearDown(right.dispose);
    addTearDown(scale.dispose);
    addTearDown(clip.dispose);
    await tester.runAsync(
      () => MultiShaderBuilder.precacheShaders([
        ShaderKeys.fakeGlassSurface,
        ShaderKeys.liquidGlassRender,
        ShaderKeys.liquidGlassMaterialRender,
        ShaderKeys.liquidGlassTintRender,
      ]),
    );
    Future<void> mount({required bool includeLeft}) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        _scene(
          fake: false,
          left: left,
          right: right,
          includeLeft: includeLeft,
          includeRight: includeLeft || !allSingular,
          position: Offset.zero,
          translation: null,
          clipWidth: clip,
          leftScale: scale,
          rightScale: allSingular ? scale : null,
        ),
      );
      await pumpUntilGlassReady(tester);
      await tester.pumpAndSettle();
    }

    Future<Uint8List> capture() async {
      final pressure = queuePressure?.call();
      try {
        binding
          ..captured = null
          ..captureNextScene = true
          ..scheduleFrame();
        await tester.pump();
        expect(tester.takeException(), isNull);
        final image = (await tester.runAsync(() => binding.captured!))!;
        try {
          final data = (await tester.runAsync(image.toByteData))!;
          return Uint8List.fromList(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          );
        } finally {
          image.dispose();
          binding.captured = null;
        }
      } finally {
        if (pressure != null) await tester.runAsync(() => pressure);
      }
    }

    await mount(includeLeft: false);
    final sibling = await capture();
    left.value = .5;
    await mount(includeLeft: true);
    final visibleHalf = await capture();
    left.value = 1;
    scale.value = 0;
    final beforeEmpty = FlutterGpuGeometryRenderer.debugTotalRenderCount;
    await mount(includeLeft: true);
    expect(_errors(await capture(), sibling, 'initial singular'), isEmpty);
    final count = FlutterGpuGeometryRenderer.debugTotalRenderCount;
    if (allSingular) expect(count, beforeEmpty);
    for (final alpha in [.5, 0.0, 1.0]) {
      left.value = alpha;
      expect(
        _errors(await capture(), sibling, 'singular alpha $alpha'),
        isEmpty,
      );
      expect(FlutterGpuGeometryRenderer.debugTotalRenderCount, count);
    }
    left.value = .5;
    scale.value = 1;
    final failures = <String>[
      ..._errors(await capture(), visibleHalf, 'scale restored'),
    ];
    final owner = tester.allRenderObjects
        .whereType<RenderLiquidGlassLayer>()
        .toSet()
        .single;
    final restoreCount = FlutterGpuGeometryRenderer.debugTotalRenderCount;
    debugPrint(
      'SINGULAR_RESTORE sdf=$restoreCount '
      'passes=${owner.debugIndependentPassCount}',
    );
    failures.addAll(_errors(await capture(), visibleHalf, 'scale stable'));
    expect(FlutterGpuGeometryRenderer.debugTotalRenderCount, restoreCount);
    scale.value = 0;
    failures.addAll(_errors(await capture(), sibling, 'scale removed again'));
    final collapseCount = FlutterGpuGeometryRenderer.debugTotalRenderCount;
    if (allSingular) {
      expect(collapseCount, restoreCount);
      expect(owner.debugMaterialFilterAttached, isFalse);
      expect(owner.debugIndependentPassCount, 0);
    }
    failures.addAll(_errors(await capture(), sibling, 'collapsed stable'));
    expect(FlutterGpuGeometryRenderer.debugTotalRenderCount, collapseCount);
    scale.value = 1;
    failures.addAll(_errors(await capture(), visibleHalf, 'restored again'));
    final secondRestoreCount = FlutterGpuGeometryRenderer.debugTotalRenderCount;
    failures.addAll(_errors(await capture(), visibleHalf, 'second stable'));
    expect(
      FlutterGpuGeometryRenderer.debugTotalRenderCount,
      secondRestoreCount,
    );
    expect(failures, isEmpty, reason: failures.join('\n'));
    if (stress) {
      final overBudget = completionTimes.where((time) => time > 16667).length;
      final mean =
          completionTimes.reduce((a, b) => a + b) / completionTimes.length;
      debugPrint(
        'SINGULAR_STRESS snapshots=${completionTimes.length} '
        'over16ms=$overBudget meanCompletionUs=$mean',
      );
      expect(overBudget, greaterThanOrEqualTo(5));
    }
  }, skip: skipProperGlassTests);
}

Widget _scene({
  required bool fake,
  required Animation<double> left,
  required Animation<double> right,
  required bool includeLeft,
  required Offset position,
  required ValueNotifier<Offset>? translation,
  required ValueNotifier<double> clipWidth,
  ValueNotifier<double>? leftScale,
  ValueNotifier<double>? rightScale,
  bool includeRight = true,
  bool contained = const bool.fromEnvironment('PROBE_CONTAINED'),
  ValueNotifier<LiquidGlassAppearance>? secondAppearance,
}) {
  final shapes = Stack(
    clipBehavior: Clip.none,
    children: [
      if (includeLeft)
        Positioned(
          left: 10,
          top: 70,
          child: FadeTransition(
            opacity: left,
            child: leftScale == null
                ? _fadingShapes(
                    contained: contained,
                    secondAppearance: secondAppearance,
                  )
                : ValueListenableBuilder<double>(
                    valueListenable: leftScale,
                    child: _fadingShapes(
                      contained: contained,
                      secondAppearance: secondAppearance,
                    ),
                    builder: (_, scale, child) =>
                        Transform.scale(scale: scale, child: child),
                  ),
          ),
        ),
      if (includeRight)
        Positioned(
          left: 108,
          top: 70,
          child: FadeTransition(
            opacity: right,
            child: rightScale == null
                ? _shape(const Color(0xFF16D968), contained: contained)
                : ValueListenableBuilder<double>(
                    valueListenable: rightScale,
                    child: _shape(
                      const Color(0xFF16D968),
                      contained: contained,
                    ),
                    builder: (_, scale, child) =>
                        Transform.scale(scale: scale, child: child),
                  ),
          ),
        ),
    ],
  );
  return MediaQuery(
    data: const MediaQueryData(size: Size(240, 200)),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(
            // ignore: avoid_redundant_argument_values
            willChange: const bool.fromEnvironment('PROBE_CONTINUOUS_OVERDRAW'),
            painter: _Background(
              // ignore: avoid_redundant_argument_values
              workload: const bool.fromEnvironment('PROBE_CONTINUOUS_OVERDRAW'),
              motion: const bool.fromEnvironment('PROBE_CONTINUOUS_OVERDRAW')
                  ? translation
                  : null,
            ),
          ),
          _captureFrameProbe(
            child: LiquidGlassLayer(
              fake: fake,
              settings: const LiquidGlassSettings(
                // ignore: avoid_redundant_argument_values
                edgeRefraction: bool.fromEnvironment('PROBE_NO_REFRACTION')
                    ? 0
                    : 106.13,
                frost: bool.fromEnvironment('PROBE_NO_FROST') ? 0 : 8,
                highlight: 0,
                chromaticAberration: 0,
              ),
              child: Stack(
                children: [
                  Positioned(
                    left: 18,
                    top: 28,
                    width: 204,
                    height: 144,
                    child: ClipRect(
                      clipper: _ViewportClip(clipWidth),
                      // Motion repaints below the owner boundary.
                      // FadeTransitions and children retain identity.
                      child: RepaintBoundary(
                        child: translation == null
                            ? Transform.translate(
                                offset: position,
                                child: shapes,
                              )
                            : ValueListenableBuilder<Offset>(
                                valueListenable: translation,
                                child: shapes,
                                builder: (_, offset, child) =>
                                    Transform.translate(
                                      offset: offset,
                                      child: child,
                                    ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _captureFrameProbe({required Widget child}) {
  if (const String.fromEnvironment('PROBE_CAPTURE_FRAME') == 'translated') {
    return Transform.translate(offset: const Offset(13, -17), child: child);
  }
  if (const String.fromEnvironment('PROBE_CAPTURE_FRAME') == 'clipped') {
    return ClipRect(clipper: const _CaptureFrameClip(), child: child);
  }
  return child;
}

class _CaptureFrameClip extends CustomClipper<Rect> {
  const _CaptureFrameClip();

  @override
  Rect getClip(Size size) => const Rect.fromLTWH(16, 64, 208, 120);

  @override
  bool shouldReclip(_CaptureFrameClip oldClipper) => false;
}

LiquidGlassAppearance _mixedAppearance({bool changed = false}) {
  const mode = String.fromEnvironment('PROBE_MATERIAL_MODE');
  return LiquidGlassAppearance(
    tint: changed ? const Color(0xA02050F0) : const Color(0x80E08020),
    saturation: mode == 'full' ? (changed ? 1.5 : .5) : (changed ? .5 : 1),
  );
}

Widget _fadingShapes({
  required bool contained,
  ValueNotifier<LiquidGlassAppearance>? secondAppearance,
}) {
  const mode = String.fromEnvironment('PROBE_MATERIAL_MODE');
  if (mode.isEmpty) {
    return _shape(const Color(0xFFFF3048), contained: contained);
  }
  Widget second(LiquidGlassAppearance appearance) => _shape(
    const Color(0xFFFAC51E),
    contained: contained,
    size: const Size(60, 60),
    appearance: appearance,
  );
  return SizedBox(
    width: 84,
    height: 88,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 0,
          top: 0,
          child: _shape(
            const Color(0xFFFF3048),
            contained: contained,
            size: const Size(60, 60),
          ),
        ),
        Positioned(
          left: 24,
          top: 28,
          child: secondAppearance == null
              ? second(_mixedAppearance())
              : ValueListenableBuilder<LiquidGlassAppearance>(
                  valueListenable: secondAppearance,
                  builder: (_, appearance, _) => second(appearance),
                ),
        ),
      ],
    ),
  );
}

Widget _shape(
  Color marker, {
  required bool contained,
  Size size = const Size(84, 88),
  LiquidGlassAppearance appearance = const LiquidGlassAppearance(
    tint: Color(0x602080D0),
  ),
}) => LiquidGlass.grouped(
  // ignore: avoid_redundant_argument_values
  // ignore: avoid_redundant_argument_values
  shadows: const bool.fromEnvironment('PROBE_SHADOWS')
      ? const [
          BoxShadow(
            color: Color(0x99000000),
            blurRadius: 12,
            spreadRadius: 3,
            offset: Offset(-12, 16),
          ),
        ]
      : const [],
  shape: const LiquidRoundedRectangle(borderRadius: 18),
  appearance: appearance,
  child: SizedBox(
    width: size.width,
    height: size.height,
    child: Center(
      child: ColoredBox(
        color: const bool.fromEnvironment('PROBE_NO_FOREGROUND')
            ? Colors.transparent
            : marker,
        child: const SizedBox.square(dimension: 10),
      ),
    ),
  ),
);

List<String> _errors(
  Uint8List actual,
  Uint8List expected, [
  String label = 'pixels',
  ({int channels, int max}) noise = (channels: 0, max: 3),
]) {
  var count = 0;
  var maxError = 0;
  var worst = 0;
  for (var i = 0; i < expected.length; i++) {
    final error = (actual[i] - expected[i]).abs();
    if (error > 3) count++;
    if (error > maxError) {
      maxError = error;
      worst = i;
    }
  }
  return count <= noise.channels && maxError <= noise.max
      ? const []
      : [
          // ignore: no_adjacent_strings_in_list
          '$label: $count RGBA channels exceed 3; max=$maxError at '
              '(${worst ~/ 4 % 240},${worst ~/ 4 ~/ 240}) '
              'channel=${worst % 4}.',
        ];
}

class _ViewportClip extends CustomClipper<Rect> {
  _ViewportClip(this.width) : super(reclip: width);
  final ValueNotifier<double> width;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, width.value, size.height);

  @override
  bool shouldReclip(_ViewportClip oldClipper) =>
      !identical(width, oldClipper.width);
}

class _Background extends CustomPainter {
  const _Background({this.workload = false, this.motion})
    : super(repaint: motion);
  final bool workload;
  final ValueNotifier<Offset>? motion;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = false;
    for (var y = 0; y < size.height; y += 20) {
      for (var x = 0; x < size.width; x += 24) {
        paint.color = (x ~/ 24 + y ~/ 20).isEven
            ? const Color(0xFF2468AC)
            : const Color(0xFFEDCBA9);
        canvas.drawRect(
          Rect.fromLTWH(x.toDouble(), y.toDouble(), 24, 20),
          paint,
        );
      }
    }
    if (workload) {
      // Full display overdraw, with no extra offscreen targets or SDF work.
      // Keep checkerboard contrast for the existing pixel comparisons.
      for (var i = 0; i < 256; i++) {
        paint
          ..color = Colors.white
          ..shader = ui.Gradient.linear(
            Offset((i % 11).toDouble(), 0),
            Offset(size.width, size.height),
            const [Color(0x01244888), Color(0x01984824)],
          );
        canvas.drawRect(Offset.zero & size, paint);
      }
      // Change the full-background display list without changing the 240x200
      // comparison region. A retained static backdrop is not continuous load.
      if (motion != null && size.width > 240 && size.height > 200) {
        canvas.drawRect(
          Rect.fromLTWH(size.width - 1, size.height - 1, 1, 1),
          Paint()
            ..color = motion!.value == Offset.zero
                ? Colors.black
                : Colors.white,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_Background oldDelegate) =>
      oldDelegate.workload != workload || oldDelegate.motion != motion;
}

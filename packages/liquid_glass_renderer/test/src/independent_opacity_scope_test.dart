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

void main() {
  runIndependentOpacityScopeTests(SubmittedSceneBinding());
}

void runIndependentOpacityScopeTests(SubmittedSceneCapture binding) {
  const contained = bool.fromEnvironment('PROBE_CONTAINED');
  const endpointsOnly = bool.fromEnvironment('PROBE_ENDPOINTS_ONLY');
  const liveContained = bool.fromEnvironment('PROBE_LIVE_CONTAINED');
  const idleMaterial = bool.fromEnvironment('PROBE_IDLE_MATERIAL');
  for (final fake in [true, false]) {
    for (final overlap in [false, true]) {
      testWidgets(
        'independent ${fake ? "fake" : "real"} opacity endpoints '
        'overlap=$overlap contained=$contained idle=$idleMaterial',
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
            ..physicalSize = const Size(240, 200)
            ..devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final left = AnimationController(
            vsync: tester,
            value: 1,
            duration: const Duration(seconds: 1),
          );
          final right = AnimationController(vsync: tester, value: 1);
          addTearDown(left.dispose);
          addTearDown(right.dispose);
          final marker = liveContained ? _LiveMarker() : null;
          if (marker != null) addTearDown(marker.dispose);
          await tester.runAsync(
            () => MultiShaderBuilder.precacheShaders([
              ShaderKeys.fakeGlassSurface,
              ShaderKeys.liquidGlassRender,
              ShaderKeys.liquidGlassMaterialRender,
              ShaderKeys.liquidGlassTintRender,
            ]),
          );

          Future<void> mount({
            required bool includeLeft,
            required bool includeRight,
          }) async {
            await tester.pumpWidget(const SizedBox.shrink());
            left.value = 1;
            right.value = 1;
            await tester.pumpWidget(
              _scene(
                fake: fake,
                overlap: overlap,
                left: left,
                right: right,
                includeLeft: includeLeft,
                includeRight: includeRight,
                marker: marker,
              ),
            );
            if (!fake) {
              await pumpUntilGlassReady(tester);
              // useFake can already be false while asynchronous GPU setup
              // still uses the consolidated fallback. Wait for that too.
              for (var frame = 0; frame < 60; frame++) {
                final ready = tester.widgetList<LiquidGlassRenderScope>(
                  find.byType(LiquidGlassRenderScope),
                );
                if (ready.length == 1 &&
                    !ready.single.consolidatesFakeBackdrop) {
                  break;
                }
                await tester.pump(const Duration(milliseconds: 16));
              }
              final scopes = tester.widgetList<LiquidGlassRenderScope>(
                find.byType(LiquidGlassRenderScope),
              );
              expect(scopes, hasLength(1));
              expect(scopes.single.consolidatesFakeBackdrop, isFalse);
              final owners = tester.allRenderObjects
                  .whereType<RenderLiquidGlassLayer>()
                  .toSet();
              expect(owners, hasLength(1));
              expect(owners.single.gpuGeometryRenderer, isNotNull);
            }
            // Only initial scene preparation settles. Alpha changes below
            // receive exactly one capture pump and never rebuild this widget.
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
              expect(image.width, 240);
              expect(image.height, 200);
              final bytes = (await tester.runAsync(image.toByteData))!;
              final result = Uint8List.fromList(
                bytes.buffer.asUint8List(
                  bytes.offsetInBytes,
                  bytes.lengthInBytes,
                ),
              );
              expect(result.length, 240 * 200 * 4);
              return result;
            } finally {
              image.dispose();
              binding.captured = null;
            }
          }

          // References physically omit the other contributor. Setting its
          // alpha to zero here would let the same hoisting bug mask itself.
          await mount(includeLeft: false, includeRight: true);
          final rightOnly = await capture();
          await mount(includeLeft: true, includeRight: false);
          final leftOnly = await capture();
          await mount(includeLeft: true, includeRight: true);
          final original = await capture();
          expect(original, isNot(orderedEquals(rightOnly)));
          expect(original, isNot(orderedEquals(leftOnly)));

          final owner = fake
              ? null
              : tester.allRenderObjects
                    .whereType<RenderLiquidGlassLayer>()
                    .toSet()
                    .single;
          final renderer = owner?.gpuGeometryRenderer;
          final fakeOwner = fake
              ? tester.allRenderObjects
                    .whereType<RenderConsolidatedFakeGlassLayer>()
                    .toSet()
                    .single
              : null;
          final initialCount = renderer?.debugRenderCount;
          final initialTotal = FlutterGpuGeometryRenderer.debugTotalRenderCount;
          final counts = <int?>[];

          const independent = bool.fromEnvironment(
            'INDEPENDENT_GLASS_OPACITY',
            defaultValue: true,
          );
          if (independent && !endpointsOnly) {
            left.value = 0.75;
            await capture();
            final recordings = fakeOwner?.debugIndependentPassRecordCount;
            final paints = fakeOwner?.debugPaintCount ?? owner!.debugPaintCount;
            if (recordings != null) expect(recordings, greaterThan(0));
            final warmedTotal =
                FlutterGpuGeometryRenderer.debugTotalRenderCount;
            // Two isolated subsets are constructed on the first real fade.
            // They must be reused for every subsequent fractional frame.
            expect(warmedTotal - initialTotal, fake || idleMaterial ? 0 : 2);
            // .999 rounds to native alpha255 but is still an unfinished fade.
            // Returning from it must not reconstruct the warmed subsets.
            for (final alpha in [0.5, 0.999, 0.25, 0.5]) {
              left.value = alpha;
              final faded = await capture();
              expect(
                _pixelFailures(await capture(), faded, 'retained stable frame'),
                isEmpty,
              );
              if (!overlap) {
                // Right glass occupies x134..218, y52..140. Its unchanged
                // core must not inherit its neighbor's independent alpha.
                for (var y = 60; y < 130; y++) {
                  for (var x = 145; x < 205; x++) {
                    for (var channel = 0; channel < 4; channel++) {
                      final index = (y * 240 + x) * 4 + channel;
                      expect(
                        (faded[index] - original[index]).abs(),
                        lessThanOrEqualTo(3),
                        reason: 'Unchanged neighbor at ($x,$y).',
                      );
                    }
                  }
                }
              }
              expect(fakeOwner?.debugIndependentPassRecordCount, recordings);
              expect(
                fakeOwner?.debugPaintCount ?? owner!.debugPaintCount,
                paints,
              );
              expect(
                FlutterGpuGeometryRenderer.debugTotalRenderCount,
                warmedTotal,
                reason: 'Fractional frames must reuse all subset SDF caches.',
              );
            }
            // A reversal can also start at exactly1 while still animating.
            // Only a settled endpoint should release the temporary caches.
            unawaited(left.reverse(from: 1));
            expect(left.status, AnimationStatus.reverse);
            await capture();
            left
              ..stop()
              ..value = .5;
            await capture();
            expect(
              FlutterGpuGeometryRenderer.debugTotalRenderCount,
              warmedTotal,
            );
            expect(fakeOwner?.debugIndependentPassRecordCount, recordings);
            expect(
              fakeOwner?.debugPaintCount ?? owner!.debugPaintCount,
              paints,
            );
            left.value = 1;
            expect(
              _pixelFailures(await capture(), original, 'fade restored'),
              isEmpty,
            );
            expect(
              FlutterGpuGeometryRenderer.debugTotalRenderCount,
              warmedTotal,
              reason: 'Restoration must reuse the original opaque matte.',
            );
          }

          left.value = 0;
          final hiddenLeft = await capture();
          counts.add(renderer?.debugRenderCount);
          left.value = 1;
          final restoredLeft = await capture();
          counts.add(renderer?.debugRenderCount);
          right.value = 0;
          final hiddenRight = await capture();
          counts.add(renderer?.debugRenderCount);
          right.value = 1;
          final restoredRight = await capture();
          counts.add(renderer?.debugRenderCount);

          // Collect both independent endpoint results before asserting, so a
          // broken common-scope implementation reports both directions.
          final failures = <String>[
            ..._pixelFailures(hiddenLeft, rightOnly, 'left zero / right only'),
            ..._pixelFailures(restoredLeft, original, 'left restored'),
            ..._pixelFailures(hiddenRight, leftOnly, 'right zero / left only'),
            ..._pixelFailures(restoredRight, original, 'right restored'),
          ];
          if (renderer != null) {
            // Temporary subsets are released at opacity 1. Each later zero
            // transition constructs its one survivor; restoration does not.
            final expectedDeltas = independent && !idleMaterial
                ? (endpointsOnly ? [1, 1, 2, 2] : [3, 3, 4, 4])
                : [0, 0, 0, 0];
            if (FlutterGpuGeometryRenderer.debugTotalRenderCount !=
                initialTotal + expectedDeltas.last) {
              failures.add(
                'Unexpected aggregate SDF work outside '
                'the explicit subset builds.',
              );
            }
            if (!identical(owner!.gpuGeometryRenderer, renderer)) {
              failures.add(
                'Alpha-only updates replaced the geometry renderer.',
              );
            }
            for (var i = 0; i < counts.length; i++) {
              final expected = initialCount! + expectedDeltas[i];
              if (counts[i] != expected) {
                failures.add(
                  'Alpha endpoint $i regenerated geometry: '
                  '${counts[i]} submissions, expected $expected.',
                );
              }
            }
          }
          if (marker != null) {
            expect(
              contained,
              isTrue,
              reason: 'Live-child probe requires PROBE_CONTAINED.',
            );
            // Capture a visible reference for the updated child before
            // exercising the hidden path. This proves actual child updates,
            // not merely restoration of the old retained picture.
            marker.value = const Color(0xFFFFEE00);
            final updatedVisible = await capture();
            expect(
              _pixelFailures(updatedVisible, original, 'changed child'),
              isNotEmpty,
            );
            marker.value = const Color(0xFFFF3048);
            expect(
              _pixelFailures(await capture(), original, 'reset child'),
              isEmpty,
            );
            left.value = 0;
            await capture();
            final hiddenBuilds =
                FlutterGpuGeometryRenderer.debugTotalRenderCount;
            int ownerPaints() =>
                fakeOwner?.debugPaintCount ?? owner!.debugPaintCount;
            final hiddenPaints = ownerPaints();
            final paintStages = <int>[hiddenPaints];
            for (final color in [
              const Color(0xFFCC00FF),
              const Color(0xFFFFEE00),
            ]) {
              final childPaints = marker.paints;
              marker.value = color;
              failures.addAll(
                _pixelFailures(
                  await capture(),
                  rightOnly,
                  'updated while hidden',
                ),
              );
              expect(
                marker.paints,
                greaterThan(childPaints),
                reason: 'Hidden repaint-boundary child must remain live.',
              );
              paintStages.add(ownerPaints());
            }
            left.value = 1;
            failures.addAll(
              _pixelFailures(
                await capture(),
                updatedVisible,
                'first restored live child',
              ),
            );
            expect(
              FlutterGpuGeometryRenderer.debugTotalRenderCount,
              hiddenBuilds,
              reason: 'Child painting and restore must reuse geometry.',
            );
            if (paintStages.any((count) => count != hiddenPaints)) {
              failures.add(
                'Contained child owner paints at hide, hidden '
                'updates: $paintStages; expected $hiddenPaints.',
              );
            }
            // RenderAnimatedOpacity changes repaint-boundary status at zero.
            // Its native 0 -> 1 transition may repaint the enclosing owner;
            // this is distinct from hidden child updates, which stay isolated.
            expect(
              ownerPaints(),
              inInclusiveRange(hiddenPaints, hiddenPaints + 1),
            );
          }
          expect(failures, isEmpty, reason: failures.join('\n'));
        },
        skip: !fake && skipProperGlassTests,
      );
    }
  }
}

Widget _scene({
  required bool fake,
  required bool overlap,
  required Animation<double> left,
  required Animation<double> right,
  required bool includeLeft,
  required bool includeRight,
  _LiveMarker? marker,
}) => MediaQuery(
  data: const MediaQueryData(size: Size(240, 200)),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const CustomPaint(painter: _Background()),
          // Both shapes explicitly join this one owner. Neither FadeTransition
          // is a common ancestor, and neither shape creates its own layer.
          LiquidGlassLayer(
            fake: fake,
            settings: const LiquidGlassSettings(
              // ignore: avoid_redundant_argument_values
              thickness: bool.fromEnvironment('PROBE_IDLE_MATERIAL') ? 0 : 20,
              frost: 8,
              highlight: 0,
              chromaticAberration: 0,
            ),
            child: Stack(
              children: [
                if (includeLeft)
                  Positioned(
                    left: overlap ? 52 : 22,
                    top: 52,
                    child: FadeTransition(
                      opacity: left,
                      child: _shape(const Color(0xFFFF3048), marker: marker),
                    ),
                  ),
                if (includeRight)
                  Positioned(
                    left: overlap ? 104 : 134,
                    top: 52,
                    child: FadeTransition(
                      opacity: right,
                      child: _shape(const Color(0xFF16D968)),
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

Widget _shape(Color color, {_LiveMarker? marker}) => LiquidGlass.grouped(
  // Compile-time switch deliberately includes the default test configuration.
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
  appearance: const LiquidGlassAppearance(tint: Color(0x602080D0)),
  child: SizedBox(
    width: 84,
    height: 88,
    child: Center(
      child: marker == null
          ? ColoredBox(
              color: color,
              child: const SizedBox.square(dimension: 10),
            )
          : RepaintBoundary(
              child: CustomPaint(
                painter: _LiveMarkerPainter(marker),
                size: const Size.square(10),
              ),
            ),
    ),
  ),
);

class _LiveMarker extends ValueNotifier<Color> {
  _LiveMarker() : super(const Color(0xFFFF3048));
  int paints = 0;
}

class _LiveMarkerPainter extends CustomPainter {
  _LiveMarkerPainter(this.marker) : super(repaint: marker);
  final _LiveMarker marker;

  @override
  void paint(Canvas canvas, Size size) {
    marker.paints++;
    canvas.drawRect(Offset.zero & size, Paint()..color = marker.value);
  }

  @override
  bool shouldRepaint(_LiveMarkerPainter oldDelegate) =>
      !identical(marker, oldDelegate.marker);
}

List<String> _pixelFailures(
  Uint8List actual,
  Uint8List expected,
  String label,
) {
  var mismatches = 0;
  var maxError = 0;
  var worstIndex = 0;
  for (var i = 0; i < expected.length; i++) {
    final error = (actual[i] - expected[i]).abs();
    if (error > 3) mismatches++;
    if (error > maxError) {
      maxError = error;
      worstIndex = i;
    }
  }
  return mismatches == 0
      ? const []
      : [
          // ignore: no_adjacent_strings_in_list
          '$label: $mismatches RGBA channels exceed 3; max=$maxError '
              'at (${worstIndex ~/ 4 % 240},${worstIndex ~/ 4 ~/ 240}) '
              'channel=${worstIndex % 4}.',
        ];
}

class _Background extends CustomPainter {
  const _Background();

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
  }

  @override
  bool shouldRepaint(_Background oldDelegate) => false;
}

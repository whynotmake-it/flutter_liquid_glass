import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/multi_shader_builder.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_render_scope.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';

import 'shared.dart';
import 'submitted_scene_binding.dart';

typedef _MaterialState = ({bool active, bool resized});

void main() => runIdleActiveOpacityLifecycleTests(SubmittedSceneBinding());

void runIdleActiveOpacityLifecycleTests(SubmittedSceneCapture binding) {
  for (final overlap in [false, true]) {
    testWidgets(
      'contained real idle/active lifecycle overlap=$overlap',
      (
        tester,
      ) async {
        final oldSize = (binding.captureWidth, binding.captureHeight);
        binding
          ..captureNextScene = false
          ..captured = null
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
        final material = ValueNotifier<_MaterialState>(
          (active: true, resized: false),
        );
        final backdrop = ValueNotifier<int>(0);
        final motion = ValueNotifier<Offset>(Offset.zero);
        final ownerMotion = ValueNotifier<Offset>(Offset.zero);
        // -1 removes the source; 1 mounts a differently keyed/color source.
        final contributor = ValueNotifier<int>(0);
        final left = AnimationController(vsync: tester, value: 1);
        final right = AnimationController(vsync: tester, value: 1);
        addTearDown(material.dispose);
        addTearDown(backdrop.dispose);
        addTearDown(motion.dispose);
        addTearDown(ownerMotion.dispose);
        addTearDown(contributor.dispose);
        addTearDown(left.dispose);
        addTearDown(right.dispose);
        await tester.runAsync(
          () => MultiShaderBuilder.precacheShaders([
            ShaderKeys.fakeGlassSurface,
            ShaderKeys.liquidGlassRender,
            ShaderKeys.liquidGlassMaterialRender,
            ShaderKeys.liquidGlassTintRender,
          ]),
        );

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
            expect((image.width, image.height), (240, 200));
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

        Future<void> mount({required bool omitLeft}) async {
          // References have fresh owners and physically absent contributors,
          // never a zero-alpha contributor using the same selection path.
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpWidget(
            _scene(
              material: material,
              backdrop: backdrop,
              motion: motion,
              ownerMotion: ownerMotion,
              contributor: contributor,
              left: left,
              right: right,
              overlap: overlap,
              omitLeft: omitLeft,
            ),
          );
          await pumpUntilGlassReady(tester);
          for (var frame = 0; frame < 60; frame++) {
            final scopes = tester.widgetList<LiquidGlassRenderScope>(
              find.byType(LiquidGlassRenderScope),
            );
            if (scopes.length == 1 && !scopes.single.consolidatesFakeBackdrop) {
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
          // No settling loop: only shader readiness is allowed to pump here.
        }

        final references = <String, Uint8List>{};
        for (final (label, active, resized, omitLeft, phase) in [
          ('original', true, false, false, 0),
          ('active right', true, false, true, 0),
          ('idle right', false, false, true, 0),
          ('idle resized', false, true, false, 0),
          ('idle backdrop', false, true, false, 1),
          ('active resized', true, true, false, 1),
          ('active resized right', true, true, true, 1),
        ]) {
          material.value = (active: active, resized: resized);
          backdrop.value = phase;
          await mount(omitLeft: omitLeft);
          references[label] = await capture();
        }
        const moved = Offset(31, -65);
        for (final (label, active, omitLeft, replacement, outside) in [
          ('idle moved right', false, true, 0, false),
          ('idle replaced moved', false, false, 1, false),
          ('active replaced moved', true, false, 1, false),
          ('cold owner moved', false, false, 0, true),
        ]) {
          material.value = (active: active, resized: true);
          backdrop.value = 1;
          contributor.value = replacement;
          motion.value = outside ? Offset.zero : moved;
          ownerMotion.value = outside ? moved : Offset.zero;
          await mount(omitLeft: omitLeft);
          references[label] = await capture();
        }
        motion.value = Offset.zero;
        ownerMotion.value = Offset.zero;
        contributor.value = 0;
        expect(
          references['original'],
          isNot(orderedEquals(references['active right']!)),
        );
        expect(
          references['idle resized'],
          isNot(orderedEquals(references['idle right']!)),
        );
        expect(
          references['idle resized'],
          isNot(orderedEquals(references['idle backdrop']!)),
        );
        expect(
          references['active resized'],
          isNot(orderedEquals(references['idle backdrop']!)),
        );

        material.value = (active: true, resized: false);
        backdrop.value = 0;
        await mount(omitLeft: false);
        var owner = tester.allRenderObjects
            .whereType<RenderLiquidGlassLayer>()
            .toSet()
            .single;
        var renderer = owner.gpuGeometryRenderer!;
        final failures = <String>[];
        int sdfCount() => FlutterGpuGeometryRenderer.debugTotalRenderCount;

        // Capture the first submitted frame AND its immediate successor. Record
        // paint deltas separately: native opacity changes its repaint-boundary
        // status at zero, which is not permission for another SDF build.
        Future<Uint8List> check(
          String label,
          VoidCallback change, {
          String? reference,
          int builds = 0,
          bool recoverable = false,
          bool retainedPaint = false,
        }) async {
          final before = sdfCount();
          final beforeRecovery = GpuAllocationDiagnostics.filterRecoveryHits;
          final paints = owner.debugPaintCount;
          change();
          final first = await capture();
          final firstPaints = owner.debugPaintCount - paints;
          final stable = await capture();
          if (reference != null) {
            _compare(first, references[reference]!, label, failures);
          }
          _compare(stable, first, '$label stable', failures);
          final actualBuilds = sdfCount() - before;
          final recovered = recoverable
              ? GpuAllocationDiagnostics.filterRecoveryHits - beforeRecovery
              : 0;
          final actualPaints = owner.debugPaintCount - paints;
          if (actualBuilds + recovered != builds) {
            failures.add(
              '$label: SDF +$actualBuilds, recovered $recovered, '
              'expected $builds total; '
              'native owner paints +$actualPaints.',
            );
          }
          if (retainedPaint && actualPaints != 0) {
            failures.add(
              '$label: retained update painted owner +$actualPaints '
              '(first +$firstPaints, stable +${actualPaints - firstPaints}).',
            );
          }
          expect(identical(owner.gpuGeometryRenderer, renderer), isTrue);
          expect(
            tester.allRenderObjects
                .whereType<RenderLiquidGlassLayer>()
                .toSet()
                .single,
            same(owner),
          );
          return first;
        }

        await check('original', () {}, reference: 'original');
        // One-time isolated material construction is explicit, not charged to
        // subsequent alpha ticks. Both independently scoped passes are warmed.
        await check('warm active subsets', () => left.value = .5, builds: 2);
        await check(
          'active fractional',
          () => left.value = .25,
          retainedPaint: true,
        );
        await check(
          'hide active source',
          () => left.value = 0,
          reference: 'active right',
        );
        await check(
          'enter idle while hidden',
          () => material.value = (active: false, resized: false),
          reference: 'idle right',
        );
        expect(owner.debugIndependentPassCount, 0);
        await check(
          'resize hidden idle source',
          () => material.value = (active: false, resized: true),
          reference: 'idle right',
        );
        await check(
          'restore resized idle source',
          () => left.value = 1,
          reference: 'idle resized',
        );
        await check('idle half', () => left.value = .5, retainedPaint: true);
        await check(
          'idle quarter',
          () => left.value = .25,
          retainedPaint: true,
        );
        await check(
          'idle restored',
          () => left.value = 1,
          reference: 'idle resized',
        );
        await check(
          'idle live backdrop',
          () => backdrop.value = 1,
          reference: 'idle backdrop',
          retainedPaint: true,
        );
        // Thickness is a geometry input. The size change deferred while idle
        // and reactivation must be encoded together in ONE fresh original SDF.
        await check(
          'reactivate resized source',
          () => material.value = (active: true, resized: true),
          reference: 'active resized',
          builds: 1,
        );
        await check('rewarm active subsets', () => left.value = .5, builds: 2);
        final faded = await check(
          'reactivated fractional',
          () => left.value = .25,
          retainedPaint: true,
        );
        final changed = await check(
          'active live backdrop',
          () => backdrop.value = 0,
          retainedPaint: true,
        );
        expect(changed, isNot(orderedEquals(faded)));
        await check(
          'active backdrop restored',
          () => backdrop.value = 1,
          retainedPaint: true,
        );
        await check(
          'hide reactivated source',
          () => left.value = 0,
          reference: 'active resized right',
        );
        await check(
          'final original branch',
          () => left.value = 1,
          reference: 'active resized',
        );
        expect(owner.debugIndependentPassCount, 0);
        // Exercise membership and motion with an old GPU matte still cached,
        // distinct from the earlier hidden resize. Both geometry nodes move
        // together under a retained Transform and cross the owner's clip.
        await check(
          'warm before idle membership',
          () => left.value = .5,
          builds: 2,
          recoverable: true,
        );
        await check(
          'hide before idle membership',
          () => left.value = 0,
          reference: 'active resized right',
        );
        await check(
          'idle before membership',
          () => material.value = (active: false, resized: true),
        );
        await check(
          'retained idle uniform motion',
          () => motion.value = moved,
          reference: 'idle moved right',
          retainedPaint: true,
        );
        await check(
          'remove hidden idle contributor',
          () => contributor.value = -1,
          reference: 'idle moved right',
        );
        await check(
          'replace hidden idle contributor',
          () => contributor.value = 1,
          reference: 'idle moved right',
        );
        await check(
          'restore replacement after motion',
          () => left.value = 1,
          reference: 'idle replaced moved',
        );
        await check(
          'reactivate moved replacement',
          () => material.value = (active: true, resized: true),
          reference: 'active replaced moved',
          builds: 1,
        );

        // A genuinely cold idle owner has never encoded a GPU matte. Keep the
        // same strict no-paint requirement: the known onTransformChanged
        // repaint is a regression to expose, not an allowed extra pump/paint.
        material.value = (active: false, resized: true);
        motion.value = Offset.zero;
        contributor.value = 0;
        final beforeCold = sdfCount();
        await mount(omitLeft: false);
        owner = tester.allRenderObjects
            .whereType<RenderLiquidGlassLayer>()
            .toSet()
            .single;
        renderer = owner.gpuGeometryRenderer!;
        expect(sdfCount(), beforeCold, reason: 'Cold idle must not encode SDF');
        expect(renderer.debugRenderCount, 0);
        await check('cold idle original', () {}, reference: 'idle backdrop');
        final coldMoved = await check(
          'cold idle owner transform',
          () => ownerMotion.value = moved,
          reference: 'cold owner moved',
          retainedPaint: true,
        );
        expect(coldMoved, isNot(orderedEquals(references['idle backdrop']!)));
        await check(
          'cold idle owner transform restored',
          () => ownerMotion.value = Offset.zero,
          reference: 'idle backdrop',
          retainedPaint: true,
        );
        expect(failures, isEmpty, reason: failures.join('\n'));
      },
      skip: skipProperGlassTests,
    );
  }
}

void _compare(
  Uint8List actual,
  Uint8List expected,
  String label,
  List<String> failures,
) {
  expect(actual.length, expected.length);
  var count = 0;
  var maxError = 0;
  for (var i = 0; i < actual.length; i++) {
    final error = (actual[i] - expected[i]).abs();
    if (error > 3) count++;
    if (error > maxError) maxError = error;
  }
  if (count != 0) {
    failures.add('$label: $count RGBA channels >3, max $maxError.');
  }
}

Widget _scene({
  required ValueNotifier<_MaterialState> material,
  required ValueNotifier<int> backdrop,
  required ValueNotifier<Offset> motion,
  required ValueNotifier<Offset> ownerMotion,
  required ValueNotifier<int> contributor,
  required Animation<double> left,
  required Animation<double> right,
  required bool overlap,
  required bool omitLeft,
}) => MediaQuery(
  data: const MediaQueryData(size: Size(240, 200)),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(child: CustomPaint(painter: _Backdrop(backdrop))),
          _translated(
            ownerMotion,
            ValueListenableBuilder<_MaterialState>(
              valueListenable: material,
              builder: (context, state, child) => LiquidGlassLayer(
                settings: LiquidGlassSettings(
                  thickness: state.active ? 20 : 0,
                  frost: 8,
                  highlight: 0,
                  chromaticAberration: 0,
                ),
                child: ClipRect(
                  // Transform marks paint by design. Keep that native repaint
                  // below the owner when testing compositor-only glass motion.
                  child: RepaintBoundary(
                    child: _translated(
                      motion,
                      ValueListenableBuilder<int>(
                        valueListenable: contributor,
                        builder: (context, generation, child) => Stack(
                          children: [
                            if (!omitLeft && generation >= 0)
                              Positioned(
                                key: ValueKey('left-$generation'),
                                left:
                                    (overlap ? 36.0 : 14.0) -
                                    (state.resized ? 6 : 0),
                                top: state.resized ? 40 : 56,
                                child: FadeTransition(
                                  opacity: left,
                                  child: _shape(
                                    generation == 0 ? Colors.red : Colors.blue,
                                    state.resized
                                        ? const Size(108, 104)
                                        : const Size(76, 88),
                                  ),
                                ),
                              ),
                            Positioned(
                              key: const ValueKey('right'),
                              left: overlap ? 104 : 150,
                              top: 56,
                              child: FadeTransition(
                                opacity: right,
                                child: _shape(Colors.green, const Size(76, 88)),
                              ),
                            ),
                          ],
                        ),
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
  ),
);

// The child is stable across motion ticks. Only the retained transform changes,
// either below the owner (uniform contributors) or above it (cold owner).
Widget _translated(ValueNotifier<Offset> offset, Widget child) =>
    ValueListenableBuilder<Offset>(
      valueListenable: offset,
      child: child,
      builder: (context, value, child) =>
          Transform.translate(offset: value, child: child),
    );

Widget _shape(Color color, Size size) => LiquidGlass.grouped(
  shape: const LiquidRoundedRectangle(borderRadius: 14),
  child: SizedBox.fromSize(
    size: size,
    child: Center(
      child: RepaintBoundary(
        child: ColoredBox(
          color: color,
          child: const SizedBox(width: 30, height: 24),
        ),
      ),
    ),
  ),
);

class _Backdrop extends CustomPainter {
  _Backdrop(this.phase) : super(repaint: phase);
  final ValueNotifier<int> phase;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(const Color(0xFFE8DDD0), BlendMode.src);
    final paint = Paint()..color = const Color(0xFF406090);
    for (var y = -20; y < 200; y += 28) {
      canvas.drawRect(
        Rect.fromLTWH(0, y + phase.value * 9.0, size.width, 12),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_Backdrop oldDelegate) => oldDelegate.phase != phase;
}

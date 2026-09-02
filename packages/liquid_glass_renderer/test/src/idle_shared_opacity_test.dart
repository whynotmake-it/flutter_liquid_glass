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

void main() => runIdleSharedOpacityTests(SubmittedSceneBinding());

void runIdleSharedOpacityTests(SubmittedSceneCapture binding) {
  for (final nested in [false, true]) {
    testWidgets(
      'idle real shared opacity matches native group nested=$nested',
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
        final common = AnimationController(vsync: tester, value: 1);
        final left = AnimationController(vsync: tester, value: 1);
        final right = AnimationController(vsync: tester, value: 1);
        final motion = ValueNotifier<Offset>(Offset.zero);
        addTearDown(common.dispose);
        addTearDown(left.dispose);
        addTearDown(right.dispose);
        addTearDown(motion.dispose);
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
        }

        // Matching live native foreground, independently built WITHOUT any
        // LiquidGlass widgets, holder replay, shader, or material selector.
        final steps = <(double, double, String)>[
          (1, 1, 'original'),
          (.5, 1, 'first half'),
          (.5, 1, 'stable half'),
          (.25, 1, 'quarter'),
          (.5, nested ? .5 : 1, 'half with inner scope'),
          (0, nested ? .5 : 1, 'zero'),
          (0, nested ? .5 : 1, 'stable zero'),
          (1, 1, 'restored'),
        ];
        await tester.pumpWidget(
          _scene(
            glass: false,
            nested: nested,
            common: common,
            left: left,
            right: right,
            motion: motion,
          ),
        );
        final references = <Uint8List>[];
        for (final (alpha, inner, _) in steps) {
          common.value = alpha;
          left.value = inner;
          references.add(await capture());
        }
        expect(
          _errors(references[0], references[1], 'nonvacuous fade'),
          isNotEmpty,
        );
        expect(
          _errors(references[1], references[5], 'nonvacuous foreground'),
          isNotEmpty,
        );
        // In the overlap the later opaque green source occludes red BEFORE the
        // common alpha. Green and background mix once, not green/red/background
        // with per-child .5 + .25 + .25 coverage. Verify the native oracle too.
        const overlapIndex = (90 * 240 + 120) * 4;
        for (var channel = 0; channel < 4; channel++) {
          final expected =
              (references[0][overlapIndex + channel] +
                  references[5][overlapIndex + channel]) /
              2;
          expect(
            (references[1][overlapIndex + channel] - expected).abs(),
            lessThanOrEqualTo(2),
          );
        }

        const offsets = [Offset(31, -65), Offset.zero];
        final movedReferences = <Uint8List>[];
        for (final offset in offsets) {
          motion.value = offset;
          movedReferences.add(await capture());
        }
        await tester.pumpWidget(const SizedBox.shrink());
        common.value = 1;
        left.value = 1;
        final beforeMount = FlutterGpuGeometryRenderer.debugTotalRenderCount;
        await tester.pumpWidget(
          _scene(
            glass: true,
            nested: nested,
            common: common,
            left: left,
            right: right,
            motion: motion,
          ),
        );
        await pumpUntilGlassReady(tester);
        for (var i = 0; i < 60; i++) {
          final scopes = tester.widgetList<LiquidGlassRenderScope>(
            find.byType(LiquidGlassRenderScope),
          );
          if (scopes.length == 1 && !scopes.single.consolidatesFakeBackdrop) {
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
        final owner = owners.single;
        final renderer = owner.gpuGeometryRenderer;
        expect(renderer, isNotNull);
        // No settling after readiness: even a repeated idle-owner invalidation
        // must be visible to these count checks rather than hidden by warm-up.
        final failures = <String>[];
        int? originalPaints;
        for (var i = 0; i < steps.length; i++) {
          final (alpha, inner, label) = steps[i];
          common.value = alpha;
          left.value = inner;
          final pixels = await capture();
          failures.addAll(_errors(pixels, references[i], label));
          originalPaints ??= owner.debugPaintCount;
          if (i >= 1 && i <= 4 && owner.debugPaintCount != originalPaints) {
            failures.add(
              '$label: owner paints ${owner.debugPaintCount}, '
              'expected $originalPaints during retained fractional updates.',
            );
          }
          if (FlutterGpuGeometryRenderer.debugTotalRenderCount != beforeMount ||
              renderer!.debugRenderCount != 0) {
            failures.add('$label: idle foreground submitted SDF work.');
          }
          expect(identical(owner.gpuGeometryRenderer, renderer), isTrue);
        }
        // Native FadeTransition changes repaint-boundary status at zero; do not
        // demand owner-paint invariance for those structural endpoint changes.
        final paintsBeforeMotion = owner.debugPaintCount;
        for (var i = 0; i < offsets.length; i++) {
          motion.value = offsets[i];
          for (var frame = 0; frame < 2; frame++) {
            failures.addAll(
              _errors(
                await capture(),
                movedReferences[i],
                'idle motion $i/$frame',
              ),
            );
            if (owner.debugPaintCount != paintsBeforeMotion) {
              failures.add('idle motion $i/$frame repainted the owner.');
            }
            expect(
              FlutterGpuGeometryRenderer.debugTotalRenderCount,
              beforeMount,
            );
          }
        }
        expect(failures, isEmpty, reason: failures.join('\n'));
      },
      skip: skipProperGlassTests,
    );
  }
}

Widget _scene({
  required bool glass,
  required bool nested,
  required Animation<double> common,
  required Animation<double> left,
  required Animation<double> right,
  required ValueNotifier<Offset> motion,
}) {
  Widget marker(Color color) {
    final child = SizedBox(
      width: 112,
      height: 100,
      child: ColoredBox(color: color),
    );
    return glass
        ? LiquidGlass.grouped(
            shape: const LiquidRoundedRectangle(borderRadius: 0),
            child: child,
          )
        : child;
  }

  final red = marker(const Color(0xFFE02040));
  final green = marker(const Color(0xFF20C060));
  final foreground = FadeTransition(
    opacity: common,
    child: Stack(
      children: [
        Positioned(
          left: 28,
          top: 42,
          child: nested ? FadeTransition(opacity: left, child: red) : red,
        ),
        Positioned(
          left: 88,
          top: 62,
          child: nested ? FadeTransition(opacity: right, child: green) : green,
        ),
      ],
    ),
  );
  return MediaQuery(
    data: const MediaQueryData(size: Size(240, 200)),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xFF284878)),
          ValueListenableBuilder<Offset>(
            valueListenable: motion,
            builder: (context, offset, child) =>
                Transform.translate(offset: offset, child: child),
            child: glass
                ? LiquidGlassLayer(
                    settings: const LiquidGlassSettings(
                      thickness: 0,
                      frost: 0,
                      highlight: 0,
                    ),
                    child: foreground,
                  )
                : foreground,
          ),
        ],
      ),
    ),
  );
}

List<String> _errors(Uint8List actual, Uint8List expected, String label) {
  var count = 0;
  var maximum = 0;
  var worst = 0;
  for (var i = 0; i < expected.length; i++) {
    final error = (actual[i] - expected[i]).abs();
    if (error > 3) count++;
    if (error > maximum) {
      maximum = error;
      worst = i;
    }
  }
  return count == 0
      ? const []
      : [
          // ignore: no_adjacent_strings_in_list
          '$label: $count channels exceed 3; max=$maximum '
              'at (${worst ~/ 4 % 240},${worst ~/ 4 ~/ 240}) '
              'channel=${worst % 4}.',
        ];
}

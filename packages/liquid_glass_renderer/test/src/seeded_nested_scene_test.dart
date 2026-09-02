import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/multi_shader_builder.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_render_scope.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';

import 'shared.dart';
import 'submitted_scene_binding.dart';

void main() {
  runSeededNestedTests(SubmittedSceneBinding());
}

/// Also registered by device tests using their SubmittedSceneCapture binding.
void runSeededNestedTests(SubmittedSceneCapture binding) {
  for (final fake in [true, false]) {
    testWidgets(
      'seeded nested ${fake ? "fake" : "real"} preserves motion and fading',
      (tester) async {
        final previousWidth = binding.captureWidth;
        final previousHeight = binding.captureHeight;
        addTearDown(() {
          binding
            ..captureNextScene = false
            ..captured = null
            ..captureWidth = previousWidth
            ..captureHeight = previousHeight;
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
        final translation = ValueNotifier<Offset>(Offset.zero);
        addTearDown(translation.dispose);
        final opacity = AnimationController(vsync: tester, value: 1);
        addTearDown(opacity.dispose);

        await tester.runAsync(
          () => MultiShaderBuilder.precacheShaders([
            ShaderKeys.fakeGlassSurface,
            ShaderKeys.liquidGlassRender,
            ShaderKeys.liquidGlassMaterialRender,
            ShaderKeys.liquidGlassTintRender,
          ]),
        );

        Future<Uint8List> capture({String? label}) async {
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
            if (!fake && label != null) {
              await tester.runAsync(() async {
                final png = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                await File('${Directory.systemTemp.path}/nested-$label.png')
                    .writeAsBytes(png!.buffer.asUint8List());
              });
            }
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

        // This reference contains no glass or opacity subtree at all.
        await tester.pumpWidget(_scene(const SizedBox.shrink()));
        final background = await capture();

        Future<void> mount() async {
          // Independent mounts compare retained movement with fresh setup.
          await tester.pumpWidget(const SizedBox.shrink());
          translation.value = Offset.zero;
          opacity.value = 1;
          await tester.pumpWidget(
            _scene(
              FadeTransition(
                opacity: opacity,
                child: _nestedForeground(fake, translation),
              ),
            ),
          );
          if (!fake) {
            await pumpUntilGlassReady(tester);
            // The shared helper waits for any real scope; nested coverage
            // needs every scope to have left its asynchronous fallback.
            for (var frame = 0; frame < 60; frame++) {
              final scopes = tester.widgetList<LiquidGlassRenderScope>(
                find.byType(LiquidGlassRenderScope),
              );
              if (scopes.length >= 2 &&
                  scopes.every((scope) => !scope.consolidatesFakeBackdrop)) {
                break;
              }
              await tester.pump(const Duration(milliseconds: 16));
            }
            final scopes = tester.widgetList<LiquidGlassRenderScope>(
              find.byType(LiquidGlassRenderScope),
            );
            expect(scopes.length, greaterThanOrEqualTo(2));
            expect(
              scopes.every((scope) => !scope.consolidatesFakeBackdrop),
              isTrue,
              reason: 'Both nested material passes must actually be real.',
            );
          }
          await tester.pumpAndSettle();
        }

        const movedOffset = Offset(17, -13);
        await mount();
        final originalStatic = await capture();
        translation.value = movedOffset;
        final originalMoved = await capture(label: 'opaque');
        _expectPixels(
          await capture(),
          originalMoved,
          'original moved scene stays stable on the following frame',
        );
        expect(
          _maxDifference(originalStatic, originalMoved),
          greaterThan(10),
          reason: 'The translation must visibly change the reference scene.',
        );
        expect(
          _maxDifference(originalStatic, background),
          greaterThan(10),
          reason: 'An empty or invisible fixture must not pass.',
        );

        await mount();
        final seededStatic = await capture();
        _expectPixels(seededStatic, originalStatic, 'opaque static');
        translation.value = movedOffset;
        // Exactly one pump after motion: capture the submitted scene itself,
        // without a boundary.toImage traversal or a catch-up frame.
        final seededMoved = await capture();
        _expectPixels(seededMoved, originalMoved, 'opaque first moved frame');
        _expectPixels(
          await capture(),
          seededMoved,
          'seeded moved scene stays stable on the following frame',
        );

        final renderers = tester.allRenderObjects
            .whereType<RenderLiquidGlassLayer>()
            .toList();
        final counts = [
          for (final renderer in renderers)
            renderer.gpuGeometryRenderer?.debugRenderCount,
        ];
        opacity.value = 0.5;
        final half = await capture(label: 'half');
        final expectedHalf = Uint8List(originalMoved.length);
        for (var i = 0; i < expectedHalf.length; i++) {
          expectedHalf[i] =
              ((originalMoved[i] * 128 + background[i] * 127) / 255).round();
        }
        // Temporary edge-level differences during a fade are acceptable;
        // opaque and hidden endpoints retain their stricter comparisons.
        _expectPixels(
          half,
          expectedHalf,
          'retained half-opacity frame',
          tolerance: 16,
        );
        opacity.value = 0;
        _expectPixels(await capture(), background, 'zero opacity');
        opacity.value = 1;
        _expectPixels(await capture(), originalMoved, 'restored opacity');
        // Exercise retained native-layer replacement repeatedly, including
        // nearly opaque frames, without repainting or rebuilding the child.
        for (final alpha in [254, 128, 0, 255, 0, 128, 254, 255]) {
          opacity.value = alpha / 255;
          final expected = Uint8List(originalMoved.length);
          for (var i = 0; i < expected.length; i++) {
            expected[i] =
                ((originalMoved[i] * alpha + background[i] * (255 - alpha)) /
                        255)
                    .round();
          }
          _expectPixels(
            await capture(),
            expected,
            'repeated retained fade alpha=$alpha',
            tolerance: alpha == 0 || alpha == 255 ? 3 : 16,
          );
        }
        expect(
          [
            for (final renderer in renderers)
              renderer.gpuGeometryRenderer?.debugRenderCount,
          ],
          counts,
          reason: 'Alpha-only animation must not rebuild nested geometry.',
        );
      },
      skip: !fake && skipProperGlassTests,
    );
  }
}

Widget _scene(Widget foreground) => MediaQuery(
  data: const MediaQueryData(size: Size(240, 200)),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const CustomPaint(painter: _Background()),
          foreground,
        ],
      ),
    ),
  ),
);

Widget _nestedForeground(bool fake, ValueNotifier<Offset> translation) =>
    LiquidGlassLayer(
      fake: fake,
      settings: const LiquidGlassSettings(
        thickness: 18,
        frost: 4,
        highlight: 0,
        chromaticAberration: 0,
      ),
      defaultAppearance: const LiquidGlassAppearance(tint: Color(0x4020A0FF)),
      child: Stack(
        children: [
          Positioned(
            left: 42,
            top: 42,
            child: ValueListenableBuilder<Offset>(
              valueListenable: translation,
              builder: (_, offset, child) =>
                  Transform.translate(offset: offset, child: child),
              child: const LiquidGlass(
                shape: LiquidRoundedRectangle(borderRadius: 24),
                child: SizedBox(
                  width: 140,
                  height: 110,
                  child: Center(
                    child: LiquidGlass(
                      shape: LiquidRoundedRectangle(borderRadius: 16),
                      appearance: LiquidGlassAppearance(
                        tint: Color(0xC0FF6048),
                      ),
                      child: ColoredBox(
                        color: Color(0xC0FF6048),
                        child: SizedBox(width: 80, height: 64),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Ordinary foreground must survive outside both material bounds,
          // with its own clip and without inheriting the effect translation.
          const Positioned(
            left: 210,
            top: 170,
            child: ClipOval(
              child: ColoredBox(
                color: Color(0xFF19E06A),
                child: SizedBox(width: 18, height: 18),
              ),
            ),
          ),
        ],
      ),
    );

void _expectPixels(
  Uint8List actual,
  Uint8List expected,
  String label, {
  int tolerance = 3,
}) {
  expect(actual.length, expected.length);
  var mismatches = 0;
  var maxError = 0;
  var worstIndex = 0;
  for (var i = 0; i < actual.length; i++) {
    final error = (actual[i] - expected[i]).abs();
    if (error > tolerance) mismatches++;
    if (error > maxError) {
      maxError = error;
      worstIndex = i;
    }
  }
  expect(
    mismatches,
    0,
    reason:
        '$label: $mismatches RGBA channels exceed $tolerance; '
        'max=$maxError at (${worstIndex ~/ 4 % 240},'
        '${worstIndex ~/ 4 ~/ 240}) channel=${worstIndex % 4}.',
  );
}

int _maxDifference(Uint8List a, Uint8List b) {
  var result = 0;
  for (var i = 0; i < a.length; i++) {
    final difference = (a[i] - b[i]).abs();
    if (difference > result) result = difference;
  }
  return result;
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
    paint.color = const Color(0xFF733B91);
    canvas.drawRect(const Rect.fromLTWH(3, 7, 11, 51), paint);
  }

  @override
  bool shouldRepaint(_Background oldDelegate) => false;
}

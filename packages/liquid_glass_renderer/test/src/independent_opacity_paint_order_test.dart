import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/multi_shader_builder.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_render_scope.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';

import 'shared.dart';
import 'submitted_scene_binding.dart';

void main() => runIndependentOpacityPaintOrderTests(SubmittedSceneBinding());

void runIndependentOpacityPaintOrderTests(SubmittedSceneCapture binding) {
  for (final fake in [true, false]) {
    for (final clipped in [false, true]) {
      testWidgets(
        'outer optical fade fake=$fake clipped=$clipped',
        (tester) async {
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
          final alpha = AnimationController(vsync: tester, value: 1);
          addTearDown(alpha.dispose);
          await tester.runAsync(
            () => MultiShaderBuilder.precacheShaders([
              ShaderKeys.fakeGlassSurface,
              ShaderKeys.liquidGlassRender,
              ShaderKeys.liquidGlassMaterialRender,
              ShaderKeys.liquidGlassTintRender,
            ]),
          );
          final Widget layer = LiquidGlassLayer(
            fake: fake,
            defaultAppearance: const LiquidGlassAppearance(),
            settings: const LiquidGlassSettings(
              frost: 8,
              edgeRefraction: 0,
              highlight: 0,
              chromaticAberration: 0,
            ),
            child: const Stack(
              children: [
                Positioned(
                  left: 60,
                  top: 40,
                  child: LiquidGlass.grouped(
                    shape: LiquidRoundedRectangle(borderRadius: 20),
                    child: SizedBox(width: 120, height: 120),
                  ),
                ),
              ],
            ),
          );
          await tester.pumpWidget(
            MediaQuery(
              data: const MediaQueryData(size: Size(240, 200)),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const CustomPaint(painter: _OpticalBackground()),
                    FadeTransition(
                      opacity: alpha,
                      child: clipped
                          ? ClipRect(clipper: const _OffsetClip(), child: layer)
                          : layer,
                    ),
                  ],
                ),
              ),
            ),
          );
          if (!fake) {
            await tester.pump();
            final scopes = tester.widgetList<LiquidGlassRenderScope>(
              find.byType(LiquidGlassRenderScope),
            );
            expect(scopes, hasLength(1));
            expect(
              scopes.every((scope) => !scope.consolidatesFakeBackdrop),
              isTrue,
            );
          }
          Future<Uint8List> capture(double opacity) async {
            alpha.value = opacity;
            binding
              ..captured = null
              ..captureNextScene = true
              ..scheduleFrame();
            await tester.pump();
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

          final full = await capture(1);
          final background = await capture(0);
          const region = Rect.fromLTRB(92, 88, 148, 120);
          final opaquePixels = _region(full, region);
          final backgroundPixels = _region(background, region);
          expect(
            opaquePixels.where((v) => v > 40 && v < 215).length,
            greaterThan(500),
            reason: 'Opaque glass must visibly blur the black/white checker.',
          );
          expect(opaquePixels, isNot(orderedEquals(backgroundPixels)));
          final failures = <String>[];
          final originalWork = FlutterGpuGeometryRenderer.debugTotalRenderCount;
          for (final opacity in [
            254 / 255,
            .99931,
            128 / 255,
            32 / 255,
            0.0,
            1.0,
            128 / 255,
          ]) {
            final value = Color.getAlphaFromOpacity(opacity);
            final expected = Uint8List.fromList([
              for (var i = 0; i < full.length; i++)
                ((full[i] * value + background[i] * (255 - value)) / 255)
                    .round(),
            ]);
            Uint8List? firstActual;
            for (final frame in ['first', 'stable']) {
              final actual = await capture(opacity);
              if (firstActual == null) {
                firstActual = actual;
              } else {
                expect(
                  actual,
                  orderedEquals(firstActual),
                  reason:
                      'The first submitted fade frame must match its '
                      'settled frame without delayed glass updates.',
                );
              }
              _compareRegion(
                actual,
                expected,
                region,
                '$opacity $frame',
                failures,
              );
              _compareRegion(
                actual,
                background,
                const Rect.fromLTRB(24, 88, 48, 120),
                '$opacity $frame outside shape',
                failures,
              );
            }
            if (!fake) {
              expect(
                FlutterGpuGeometryRenderer.debugTotalRenderCount,
                originalWork,
                reason: 'Outer fade must reuse its full geometry matte.',
              );
            }
          }
          // Report pixel errors after exercising cleanup as well, so a small
          // optical residual cannot hide a resource-lifetime regression.
          expect(failures, isEmpty, reason: failures.join('\n'));
        },
        skip: !fake && skipProperGlassTests,
      );
    }
  }
}

class _OpticalBackground extends CustomPainter {
  const _OpticalBackground();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (var y = 0; y < size.height; y += 8) {
      for (var x = 0; x < size.width; x += 8) {
        paint.color = (x ~/ 8 + y ~/ 8).isEven
            ? const Color(0xFF000000)
            : const Color(0xFFFFFFFF);
        canvas.drawRect(Rect.fromLTWH(x.toDouble(), y.toDouble(), 8, 8), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_OpticalBackground oldDelegate) => false;
}

List<int> _region(Uint8List pixels, Rect rect) => [
  for (var y = rect.top.toInt(); y < rect.bottom; y++)
    for (var x = rect.left.toInt(); x < rect.right; x++)
      for (var channel = 0; channel < 4; channel++)
        pixels[(y * 240 + x) * 4 + channel],
];

void _compareRegion(
  Uint8List actual,
  Uint8List expected,
  Rect region,
  String label,
  List<String> failures,
) {
  final a = _region(actual, region);
  final b = _region(expected, region);
  var bad = 0;
  var maximum = 0;
  for (var i = 0; i < a.length; i++) {
    final error = (a[i] - b[i]).abs();
    if (error > 3) bad++;
    if (error > maximum) maximum = error;
  }
  if (bad > 0) failures.add('$label: $bad RGBA channels >3; max $maximum.');
}

class _OffsetClip extends CustomClipper<Rect> {
  const _OffsetClip();

  @override
  Rect getClip(Size size) => const Rect.fromLTWH(16, 64, 208, 80);

  @override
  bool shouldReclip(_OffsetClip oldClipper) => false;
}

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/multi_shader_builder.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';

import 'submitted_scene_binding.dart';

void main() => runWholeLayerFakeBlurTests(SubmittedSceneBinding());

void runWholeLayerFakeBlurTests(SubmittedSceneCapture binding) {
  for (final mode in ['grouped', 'inLayer', 'standalone']) {
    for (final animated in [false, true]) {
      testWidgets('$mode whole fake layer retains blur with '
          '${animated ? "FadeTransition" : "Opacity"}', (tester) async {
        final oldSize = (binding.captureWidth, binding.captureHeight);
        binding
          ..captureWidth = 240
          ..captureHeight = 160;
        tester.view
          ..physicalSize = const Size(240, 160)
          ..devicePixelRatio = 1;
        addTearDown(() {
          tester.view.reset();
          binding
            ..captureNextScene = false
            ..captured = null
            ..captureWidth = oldSize.$1
            ..captureHeight = oldSize.$2;
        });
        await tester.runAsync(
          () => MultiShaderBuilder.precacheShaders([
            ShaderKeys.fakeGlassSurface,
          ]),
        );
        final opacity = AnimationController(vsync: tester, value: 1);
        addTearDown(opacity.dispose);
        const settings = LiquidGlassSettings(frost: 8, highlight: 0);
        const appearance = LiquidGlassAppearance();
        const shape = LiquidRoundedRectangle(borderRadius: 16);
        const content = SizedBox(
          width: 176,
          height: 112,
          child: Center(
            child: ColoredBox(
              color: Colors.red,
              child: SizedBox.square(dimension: 12),
            ),
          ),
        );
        final glass = mode == 'standalone'
            ? const FakeGlass(
                settings: settings,
                appearance: appearance,
                shape: shape,
                child: content,
              )
            : LiquidGlassLayer(
                fake: true,
                settings: settings,
                defaultAppearance: appearance,
                child: mode == 'inLayer'
                    ? const FakeGlass.inLayer(shape: shape, child: content)
                    : const LiquidGlass.grouped(shape: shape, child: content),
              );
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const CustomPaint(painter: _Stripes()),
                Center(
                  child: animated
                      ? FadeTransition(opacity: opacity, child: glass)
                      : ValueListenableBuilder<double>(
                          valueListenable: opacity,
                          child: glass,
                          builder: (_, value, child) =>
                              Opacity(opacity: value, child: child),
                        ),
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        Future<Uint8List> capture(double alpha) async {
          opacity.value = alpha;
          binding
            ..captured = null
            ..captureNextScene = true
            ..scheduleFrame();
          await tester.pump();
          expect(binding.captureNextScene, isFalse);
          final image = (await tester.runAsync(() => binding.captured!))!;
          try {
            final bytes = (await tester.runAsync(image.toByteData))!;
            if (const bool.fromEnvironment('FAKE_FADE_DUMP')) {
              await tester.runAsync(() async {
                final png = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                final path =
                    '${Directory.systemTemp.path}/fake-whole-$mode-$animated-$alpha.png';
                await File(path).writeAsBytes(png!.buffer.asUint8List());
                debugPrint('FAKE_FADE_IMAGE $path');
              });
            }
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
        final samples = <double, Uint8List>{};
        for (final alpha in [254 / 255, 0.75, 0.5, 0.25]) {
          samples[alpha] = await capture(alpha);
        }
        final clear = await capture(0);
        // Compare blur against the sharp backdrop, not against another capture
        // of the same potentially broken half-opacity state. The interior is
        // untinted/unlit and excludes the red foreground and rounded edges.
        final errors = <double, double>{};
        for (final entry in samples.entries) {
          var signal = 0.0;
          var retained = 0.0;
          for (var y = 48; y < 112; y++) {
            for (var x = 56; x < 184; x++) {
              if (x >= 108 && x < 132) continue;
              for (var c = 0; c < 3; c++) {
                final i = (y * 240 + x) * 4 + c;
                final blur = full[i] - clear[i];
                signal += blur * blur;
                retained += (entry.value[i] - clear[i]) * blur;
              }
            }
          }
          expect(
            signal,
            greaterThan(1000000),
            reason: 'The opaque reference must visibly blur the stripes.',
          );
          final expected = (entry.key * 255).round() / 255;
          final measured = retained / signal;
          errors[entry.key] = (measured - expected).abs();
          debugPrint(
            'FAKE_WHOLE_BLUR mode=$mode animated=$animated alpha=${entry.key} '
            'retained=$measured expected=$expected',
          );
        }
        for (final entry in errors.entries) {
          expect(
            entry.value,
            lessThan(0.08),
            reason:
                'Blur must fade continuously at opacity ${entry.key}, '
                'not disappear as soon as native opacity creates a surface.',
          );
        }
      });
    }
  }
}

class _Stripes extends CustomPainter {
  const _Stripes();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = false;
    for (var x = 0.0; x < size.width; x += 8) {
      paint.color = (x ~/ 8).isEven ? Colors.black : Colors.white;
      canvas.drawRect(Rect.fromLTWH(x, 0, 8, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_Stripes oldDelegate) => false;
}

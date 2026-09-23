import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'submitted_scene_binding.dart';

void main() {
  runBackdropSeedTests(SubmittedSceneBinding());
}

void runBackdropSeedTests(SubmittedSceneCapture binding) {
  binding
    ..captureWidth = 240
    ..captureHeight = 160;
  const identity = ColorFilter.matrix([
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ]);

  for (var repetition = 0; repetition < 3; repetition++) {
    testWidgets(
      'identity backdrop preserves background repetition=$repetition',
      (tester) async {
        tester.view
          ..physicalSize = const Size(240, 160)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final opacity = ValueNotifier<double>(0);
        var enableShell = false;
        addTearDown(opacity.dispose);
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Stack(
              children: [
                const Positioned.fill(
                  child: CustomPaint(painter: _Background()),
                ),
                Center(
                  child: ValueListenableBuilder<double>(
                    valueListenable: opacity,
                    builder: (_, alpha, child) => Opacity(
                      opacity: alpha,
                      child: ClipRect(
                        child: BackdropFilter(
                          enabled: enableShell,
                          filter: identity,
                          child: child,
                        ),
                      ),
                    ),
                    child: const SizedBox(width: 160, height: 100),
                  ),
                ),
              ],
            ),
          ),
        );

        Future<Uint8List> capture(double alpha) async {
          opacity.value = alpha;
          binding
            ..captured = null
            ..captureNextScene = true
            ..scheduleFrame();
          await tester.pump();
          expect(binding.captureNextScene, isFalse);
          expect(binding.captured, isNotNull);
          final image = (await tester.runAsync(() => binding.captured!))!;
          expect(image.width, 240);
          expect(image.height, 160);
          final bytes = (await tester.runAsync(image.toByteData))!;
          final result = Uint8List.fromList(bytes.buffer.asUint8List());
          image.dispose();
          return result;
        }

        final background = await capture(0);
        final full = await capture(1);
        enableShell = true;
        await capture(0);
        for (final alpha in [1.0, 254 / 255, 0.5, 0.0, 1.0]) {
          final actual = await capture(alpha);
          var mismatches = 0;
          for (var i = 0; i < actual.length; i++) {
            final a = (alpha * 255).round();
            final expected = (full[i] * a + background[i] * (255 - a)) / 255;
            if (actual[i] != expected) mismatches++;
          }
          expect(mismatches, 0, reason: 'Identity seed at alpha=$alpha');
        }
      },
    );
  }
}

class _Background extends CustomPainter {
  const _Background();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = false;
    for (var y = 0; y < size.height; y += 16) {
      for (var x = 0; x < size.width; x += 16) {
        paint.color = (x ~/ 16 + y ~/ 16).isEven
            ? const Color(0xFF2468AC)
            : const Color(0xFFEDCBA9);
        canvas.drawRect(
          Rect.fromLTWH(x.toDouble(), y.toDouble(), 16, 16),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_Background oldDelegate) => false;
}

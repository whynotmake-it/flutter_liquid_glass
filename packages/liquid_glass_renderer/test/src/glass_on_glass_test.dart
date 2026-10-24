import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import 'shared.dart';

// A glass that refracts another glass: a blurless indicator over a blurred
// bar. The indicator reads the backdrop with the bar painted, so the picture
// shows the bar's glass through the indicator's. Seeds are pinned off, so this
// is the plain backdrop path; `native_seed_parity_test.dart` renders the same
// kind of scene seeded and compares it with this path.
void main() {
  setUp(pinPlainBackdropPath);

  for (final fake in [false, true]) {
    final name = fake ? 'fake' : 'real';
    testWidgets(
      'a glass over another glass ($name)',
      (tester) async {
        tester.view
          ..physicalSize = const Size(320, 240)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: RepaintBoundary(
              key: boundary,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const CustomPaint(painter: _Backdrop()),
                  Center(
                    child: LiquidGlassLayer(
                      fake: fake,
                      settings: const LiquidGlassSettings(
                        frost: 6,
                        refractionAmount: 30,
                        highlight: 0.5,
                        contourStrength: 0,
                        bevelShadowStrength: 0,
                      ),
                      child: LiquidGlass(
                        shape: const LiquidRoundedRectangle(borderRadius: 20),
                        child: SizedBox(
                          width: 160,
                          height: 40,
                          child: Align(
                            alignment: const Alignment(0.6, 0),
                            child: LiquidGlassLayer(
                              fake: fake,
                              settings: const LiquidGlassSettings(
                                frost: 0,
                                refractionAmount: 24,
                                backdropShrink: 0.08,
                                highlight: 0.4,
                              ),
                              child: const LiquidGlass(
                                shape: LiquidRoundedRectangle(
                                  borderRadius: 14,
                                ),
                                child: SizedBox(width: 44, height: 30),
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
        await tester.pump();
        final png = await tester.runAsync(() async {
          final image = await tester
              .renderObject<RenderRepaintBoundary>(find.byKey(boundary))
              .toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          return data!.buffer.asUint8List();
        });
        await tester.runAsync(
          () => expectMacOSGolden(png, 'goldens/glass_on_glass_$name.png'),
        );
      },
      skip: !fake && skipProperGlassTests,
      tags: 'golden',
    );
  }
}

/// Stripes over a diagonal gradient: blur and refraction are visible.
class _Backdrop extends CustomPainter {
  const _Backdrop();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(size.width, size.height),
          const [Color(0xFF1E3A8A), Color(0xFFF59E0B)],
        ),
    );
    final paint = Paint()
      ..isAntiAlias = false
      ..color = const Color(0xCCFFFFFF);
    for (var x = 0.0; x < size.width; x += 12) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 4, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_Backdrop oldDelegate) => false;
}

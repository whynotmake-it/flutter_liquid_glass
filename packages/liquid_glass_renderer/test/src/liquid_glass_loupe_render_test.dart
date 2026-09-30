import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import 'shared.dart';

class _HairlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..drawRect(Offset.zero & size, Paint()..color = Colors.white)
      // Half a device pixel wide at 1x: it rasterizes as one 50% gray column
      // unless it is rendered at a higher resolution.
      ..drawRect(
        Rect.fromLTWH(100, 0, 0.5, size.height),
        Paint()..color = Colors.black,
      );
  }

  @override
  bool shouldRepaint(_HairlinePainter oldDelegate) => false;
}

void main() {
  // One glass render per test process: flutter_tester only renders the first
  // identity-backdrop subpass of a process reliably.
  testWidgets(
    'the loupe re-renders its source at the magnified resolution',
    (tester) async {
      tester.view
        ..physicalSize = const Size(200, 120)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final link = LiquidGlassLoupeLink();
      final key = GlobalKey();
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: RepaintBoundary(
              key: key,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: LiquidGlassLoupeSource(
                      link: link,
                      child: CustomPaint(painter: _HairlinePainter()),
                    ),
                  ),
                  Positioned(
                    left: 50,
                    top: 30,
                    child: LiquidGlassLoupe(
                      link: link,
                      size: const Size(100, 60),
                      magnification: 2,
                      settings: const LiquidGlassSettings(
                        refractionHeight: 8,
                        refractionAmount: 0,
                        highlight: 0,
                        frost: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final pixels = await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = boundary.toImageSync();
        final data = await image.toByteData();
        final width = image.width;
        image.dispose();
        return (data!, width);
      });
      final (data, width) = pixels!;
      int red(int x, int y) => data.getUint8((y * width + x) * 4);

      // Outside the lens the hairline stays a single half-covered column.
      expect(red(100, 10), inInclusiveRange(96, 160));
      // Under the lens, around its center row, the hairline is one device
      // pixel wide and fully covered. An upscale of the 1x backdrop would
      // give two 50% columns instead.
      final row = [for (var x = 90; x <= 110; x++) red(x, 60)];
      expect(row.where((value) => value < 32), hasLength(1));
      expect(row.where((value) => value > 32 && value < 224), isEmpty);
    },
    skip: skipProperGlassTests,
  );
}

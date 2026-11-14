// Run with `flutter test --enable-impeller --enable-flutter-gpu`: the copies
// are drawn as Impeller draws them.
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/read.dart';
import 'package:material_ui/material_ui.dart';

import 'shared.dart';

const _key = ValueKey('screen');
const _glass = Rect.fromLTWH(20, 280, 220, 60);

Widget _scene(double top, double frost) => Directionality(
  textDirection: TextDirection.ltr,
  child: RepaintBoundary(
    key: _key,
    child: Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: Color(0xFF101018))),
        Positioned(
          left: 0,
          right: 0,
          top: top,
          child: RepaintBoundary(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var row = 0; row < 30; row++)
                  const Text(
                    'Revenue 1234 WWW iii',
                    style: TextStyle(fontSize: 15, color: Color(0xFFFFFFFF)),
                  ),
              ],
            ),
          ),
        ),
        Positioned.fill(
          child: RepaintBoundary(
            child: LiquidGlassLayer(
              settings: LiquidGlassSettings.ios27RegularLight().copyWith(
                frost: frost,
              ),
              child: Stack(
                children: [
                  Positioned.fromRect(
                    rect: _glass,
                    child: const LiquidGlass(
                      shape: LiquidRoundedSuperellipse(borderRadius: 30),
                      child: SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  ),
);

// The green channel inside the glass, at the screen's pixels.
Future<List<int>> _underGlass(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_key),
  );
  final image = (await tester.runAsync(() => boundary.toImage(pixelRatio: 3)))!;
  final bytes = (await tester.runAsync(image.toByteData))!.buffer.asUint8List();
  final width = image.width;
  image.dispose();
  final inner = _glass.deflate(10);
  return [
    for (var y = (inner.top * 3).round(); y < (inner.bottom * 3).round(); y++)
      for (var x = (inner.left * 3).round(); x < (inner.right * 3).round(); x++)
        bytes[(y * width + x) * 4 + 1],
  ];
}

void main() {
  setUp(() => debugGlassCopies = true);
  tearDown(() => debugGlassCopies = null);

  // A copy at a half or a quarter of the screen's pixels: text set on its
  // pixels would leave every other step, or three in four, unchanged.
  for (final frost in [2.0, 4.5]) {
    testWidgets('text under glass frosted by $frost moves with every pixel '
        'of the screen', (tester) async {
      tester.view.physicalSize = const Size(260, 360) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final steps = <double>[];
      List<int>? last;
      for (var i = 0; i <= 12; i++) {
        await tester.pumpWidget(_scene(-100 + i / 3, frost));
        await tester.pump();
        final pixels = await _underGlass(tester);
        if (last != null) {
          var change = 0;
          for (var j = 0; j < pixels.length; j++) {
            change += (pixels[j] - last[j]).abs();
          }
          steps.add(change / pixels.length);
        }
        last = pixels;
      }
      final mean = steps.reduce((a, b) => a + b) / steps.length;
      expect(steps.every((step) => step > mean / 2), isTrue, reason: '$steps');
    }, skip: skipProperGlassTests);
  }
}

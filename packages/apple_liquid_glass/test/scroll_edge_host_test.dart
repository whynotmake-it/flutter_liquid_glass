import 'dart:typed_data';

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// Run with `flutter test --enable-impeller --enable-flutter-gpu`: the band
// reads its backdrop through a seed and a blur, which only Impeller's
// compositor draws for real.
const _key = ValueKey('page');
const _width = 200;

Widget _page(GlassRenderer renderer, ScrollController controller) => MediaQuery(
  data: const MediaQueryData(size: Size(200, 400)),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: GlassScope(
      renderer: renderer,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 200,
          height: 400,
          child: RepaintBoundary(
            key: _key,
            child: GlassPageScaffold(
              backgroundColor: const Color(0xFFFFFFFF),
              navigationBar: const PreferredSize(
                preferredSize: Size.fromHeight(60),
                child: SizedBox(height: 60),
              ),
              child: GlassContentScroll(
                edgeEffects: const GlassScrollEdgeEffects(
                  top: GlassScrollEdgeEffect.hard,
                ),
                child: ListView(
                  controller: controller,
                  children: [
                    Container(
                      height: 1000,
                      color: const Color(0xFFFF0000),
                      alignment: Alignment.topLeft,
                      padding: const EdgeInsets.only(left: 100),
                      child: const SizedBox(
                        width: 2,
                        height: 1000,
                        child: ColoredBox(color: Color(0xFFFFFFFF)),
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
);

Future<Uint8List> _capture(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_key));
  final image = (await tester.runAsync(boundary.toImage))!;
  final bytes = (await tester.runAsync(image.toByteData))!;
  image.dispose();
  return bytes.buffer.asUint8List();
}

List<int> _pixel(Uint8List bytes, int x, int y) {
  final i = (y * _width + x) * 4;
  return bytes.sublist(i, i + 3);
}

Future<Uint8List> _scrolled(WidgetTester tester, GlassRenderer renderer) async {
  final controller = ScrollController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(_page(renderer, controller));
  await tester.pump();
  controller.jumpTo(200);
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  return _capture(tester);
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('the hard band fades the content toward the background and '
      'blurs it on liquid glass', (tester) async {
    final liquid = await _scrolled(tester, const LiquidGlassRenderer());
    final band = _pixel(liquid, 40, 30);
    expect(band[0], greaterThan(240));
    expect(band[1], inInclusiveRange(100, 160));
    final outside = _pixel(liquid, 40, 200);
    expect(outside, [255, 0, 0]);
    expect(_pixel(liquid, 98, 200), [255, 0, 0]);
    expect(_pixel(liquid, 98, 30)[1], greaterThan(band[1] + 10));
  });

  testWidgets('flat glass dissolves the band without a blur', (tester) async {
    final flat = await _scrolled(tester, const FlatGlassRenderer());
    final band = _pixel(flat, 40, 30);
    expect(band[1], inInclusiveRange(100, 160));
    expect(_pixel(flat, 97, 30), band);
  });
}

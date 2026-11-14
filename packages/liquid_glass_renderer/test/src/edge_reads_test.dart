import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:material_ui/material_ui.dart';

import 'shared.dart';

const _key = ValueKey('screen');
const _glass = Rect.fromLTWH(40, 40, 120, 70);

const _clear = LiquidGlassSettings(
  refractionHeight: 0,
  refractionAmount: 0,
  frost: 0,
  highlight: 0,
  contourStrength: 0,
  bevelShadowStrength: 0,
);

Widget _scene(LiquidGlassSettings settings, List<Rect> white) => Directionality(
  textDirection: TextDirection.ltr,
  child: RepaintBoundary(
    key: _key,
    child: Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: Color(0xFF000000))),
        for (final rect in white)
          Positioned.fromRect(
            rect: rect,
            child: const ColoredBox(color: Color(0xFFFFFFFF)),
          ),
        Positioned.fill(
          child: LiquidGlassLayer(
            settings: settings,
            child: Stack(
              children: [
                Positioned.fromRect(
                  rect: _glass,
                  child: const LiquidGlass(
                    appearance: LiquidGlassAppearance(),
                    shape: LiquidRoundedRectangle(borderRadius: 35),
                    child: SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  ),
);

Future<Color Function(int x, int y)> _pixels(
  WidgetTester tester,
  LiquidGlassSettings settings,
  List<Rect> white,
) async {
  await tester.pumpWidget(_scene(settings, white));
  await tester.pump();
  final (Uint8List bytes, int width) = (await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_key),
    );
    final image = await boundary.toImage();
    final bytes = await image.toByteData();
    final width = image.width;
    image.dispose();
    return (bytes!.buffer.asUint8List(), width);
  }))!;
  return (int x, int y) {
    final at = (y * width + x) * 4;
    return Color.fromARGB(255, bytes[at], bytes[at + 1], bytes[at + 2]);
  };
}

int _red(Color color) => (color.r * 255).round();
int _blue(Color color) => (color.b * 255).round();

void _size(WidgetTester tester) {
  tester.view.physicalSize = const Size(200, 150);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('a pull shows what lies just outside the glass inside its edge '
      'and leaves its middle in place', (tester) async {
    _size(tester);
    // A stripe 2 to 6 px above the glass, and a mark on its center.
    const white = [
      Rect.fromLTWH(0, 34, 200, 4),
      Rect.fromLTWH(98, 73, 4, 4),
    ];
    final plain = await _pixels(tester, _clear, white);
    expect(_red(plain(100, 42)), lessThan(10));
    expect(_red(plain(100, 75)), greaterThan(245));

    final pulled = await _pixels(
      tester,
      _clear.copyWith(backdropPull: 9, backdropPullHeight: 36),
      white,
    );
    // 2.5 px deep the glass reads 5.7 px farther out: the stripe.
    expect(_red(pulled(100, 42)), greaterThan(200));
    // 20.5 px deep it reads 1.6 px farther out: the page under the glass.
    expect(_red(pulled(100, 60)), lessThan(10));
    expect(_red(pulled(100, 75)), greaterThan(245));
  }, skip: skipProperGlassTests);

  testWidgets('an aberration parts a line crossing the top edge blue to its '
      'left and red to its right, and one crossing the bottom the other way '
      'round', (tester) async {
    _size(tester);
    const white = [Rect.fromLTWH(99, 0, 2, 150)];
    final plain = await _pixels(tester, _clear, white);
    expect(_red(plain(103, 46)), lessThan(10));
    expect(_blue(plain(96, 46)), lessThan(10));
    expect(_red(plain(100, 46)), greaterThan(245));

    final parted = await _pixels(
      tester,
      _clear.copyWith(aberration: 3, aberrationDepth: 30),
      white,
    );
    // 6.5 px under the top edge red reads up to 2.9 px to the left and
    // blue as far to the right.
    expect(_red(parted(103, 46)), greaterThan(50));
    expect(_blue(parted(103, 46)), lessThan(10));
    expect(_blue(parted(96, 46)), greaterThan(50));
    expect(_red(parted(96, 46)), lessThan(10));
    // 6.5 px over the bottom edge red reads to the right.
    expect(_blue(parted(103, 103)), greaterThan(50));
    expect(_red(parted(103, 103)), lessThan(10));
    expect(_red(parted(96, 103)), greaterThan(50));
    expect(_blue(parted(96, 103)), lessThan(10));
    // The line itself dims: each color reads mostly beside it.
    expect(_red(parted(100, 46)), lessThan(200));
  }, skip: skipProperGlassTests);

  testWidgets('an aberration parts a line crossing the left end red below '
      'and blue above, and one crossing the right end the other way round', (
    tester,
  ) async {
    _size(tester);
    const white = [Rect.fromLTWH(0, 74, 200, 2)];
    final parted = await _pixels(
      tester,
      _clear.copyWith(aberration: 3, aberrationDepth: 30),
      white,
    );
    // 6.5 px inside the left end red reads up to 2.9 px above.
    expect(_red(parted(46, 78)), greaterThan(50));
    expect(_blue(parted(46, 78)), lessThan(10));
    expect(_blue(parted(46, 71)), greaterThan(50));
    expect(_red(parted(46, 71)), lessThan(10));
    // 6.5 px inside the right end red reads below.
    expect(_blue(parted(153, 78)), greaterThan(50));
    expect(_red(parted(153, 78)), lessThan(10));
    expect(_red(parted(153, 71)), greaterThan(50));
    expect(_blue(parted(153, 71)), lessThan(10));
  }, skip: skipProperGlassTests);

  testWidgets('an aberration reads the page past the edge of the glass, so a '
      'white page stays white up to the rim', (tester) async {
    _size(tester);
    const white = [Rect.fromLTWH(0, 0, 200, 150)];
    final parted = await _pixels(
      tester,
      _clear.copyWith(aberration: 3, aberrationDepth: 30),
      white,
    );
    // About 3 px inside the four arcs, and 1.5 px inside the top and the
    // left end.
    for (final (x, y) in [
      (52, 52),
      (148, 52),
      (52, 98),
      (148, 98),
      (100, 41),
      (41, 75),
    ]) {
      expect(_red(parted(x, y)), greaterThan(245), reason: 'red at $x, $y');
      expect(_blue(parted(x, y)), greaterThan(245), reason: 'blue at $x, $y');
    }
  }, skip: skipProperGlassTests);
}

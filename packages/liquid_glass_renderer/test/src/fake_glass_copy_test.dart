@Tags(['macos_pixels'])
library;

import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/composer.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/rendering.dart';
import 'package:liquid_glass_renderer/src/widgets/fake_glass.dart';
import 'package:material_ui/material_ui.dart';

import 'shared.dart';

const _key = ValueKey('screen');

Widget _scene({double shift = 0}) => Directionality(
  textDirection: TextDirection.ltr,
  child: RepaintBoundary(
    key: _key,
    child: Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: const [
                  Color(0xFF1E3A8A),
                  Color(0xFFF59E0B),
                  Color(0xFF10B981),
                ],
                begin: Alignment(-1 + shift, -1),
                end: Alignment.bottomRight,
                tileMode: TileMode.mirror,
              ),
            ),
            child: const Center(
              child: Text(
                'Page under the glass',
                style: TextStyle(color: Color(0xFFFFFFFF), fontSize: 22),
              ),
            ),
          ),
        ),
        Positioned.fromRect(
          rect: const Rect.fromLTWH(40, 70, 180, 60),
          child: FakeGlass(
            shape: const LiquidRoundedSuperellipse(borderRadius: 30),
            settings: LiquidGlassSettings.ios27RegularLight().copyWith(
              frost: 6,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ],
    ),
  ),
);

RenderFakeGlass _glass(WidgetTester tester) =>
    tester.renderObject<RenderFakeGlass>(find.byType(RawFakeGlass));

Future<Uint8List> _pixels(WidgetTester tester, {double dpr = 1}) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_key),
  );
  final image = (await tester.runAsync(
    () => boundary.toImage(pixelRatio: dpr),
  ))!;
  final bytes = (await tester.runAsync(image.toByteData))!;
  image.dispose();
  return bytes.buffer.asUint8List();
}

// The glass's body: 4 px inside its straight edges, clear of the corners.
Uint8List _inside(Uint8List pixels) => Uint8List.fromList([
  for (var y = 74; y < 126; y++)
    ...pixels.sublist((y * 260 + 90) * 4, (y * 260 + 170) * 4),
]);

int _difference(Uint8List a, Uint8List b) {
  var largest = 0;
  for (var i = 0; i < a.length; i++) {
    final d = (a[i] - b[i]).abs();
    if (d > largest) largest = d;
  }
  return largest;
}

void main() {
  tearDown(() {
    debugGlassCopies = null;
    GlassCopyTuning.debugOverride();
  });

  testWidgets('fake glass over a copy draws what reading the backdrop '
      'draws', (tester) async {
    tester.view.physicalSize = const Size(260, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(LiquidGlass.precache);

    // flutter_tester renders only a process's first backdrop filter
    // reliably, so the reference reads the backdrop first.
    debugGlassCopies = false;
    await tester.pumpWidget(_scene());
    await tester.pump();
    final reading = await _pixels(tester);
    expect(_glass(tester).debugBackdropFilterLayer!.serves, isFalse);

    debugGlassCopies = true;
    GlassCopyTuning.debugOverride(shaderFrost: false);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_scene(shift: 0.3));
    await tester.pumpWidget(_scene());
    expect(_glass(tester).debugBackdropFilterLayer!.serves, isTrue);
    expect(tester.layers.whereType<BackdropFilterLayer>(), isEmpty);
    final copied = await _pixels(tester);
    // NEAR: the antialiased rim of the shape differs by a few levels.
    expect(_difference(reading, copied), lessThanOrEqualTo(10));
    expect(
      _difference(_inside(reading), _inside(copied)),
      lessThanOrEqualTo(2),
    );
  }, skip: skipProperGlassTests);

  testWidgets('frosted fake glass over a quarter-size copy stays near what '
      'reading the backdrop draws', (tester) async {
    const dpr = 2.625;
    tester.view.physicalSize = const Size(260 * dpr, 200 * dpr);
    tester.view.devicePixelRatio = dpr;
    addTearDown(tester.view.reset);
    await tester.runAsync(LiquidGlass.precache);

    debugGlassCopies = false;
    await tester.pumpWidget(_scene());
    await tester.pump();
    final reading = await _pixels(tester, dpr: dpr);

    debugGlassCopies = true;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_scene(shift: 0.3));
    await tester.pumpWidget(_scene());
    final layer = _glass(tester).debugBackdropFilterLayer!;
    expect(layer.serves, isTrue);
    expect(layer.frost, isNotNull);
    final copied = await _pixels(tester, dpr: dpr);
    // NEAR, see GlassCopyTuning.shaderFrost: the test font's
    // white blocks are the hardest edges a frost meets.
    expect(_difference(reading, copied), lessThanOrEqualTo(22));
  }, skip: skipProperGlassTests);
}

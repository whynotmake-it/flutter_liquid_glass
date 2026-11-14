import 'dart:typed_data';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import 'shared.dart';

const _key = ValueKey('screen');

const _shapes = 20;

// Rows 80 pixels apart put the second layer's buffer 160 pixels below the
// first, on the same tile grid, so its glass keeps full density where one
// layer's would: a tile's density depends on where it falls.
Rect _rect(int i) =>
    Rect.fromLTWH(20 + (i % 5) * 70.0, 20 + (i ~/ 5) * 80.0, 30, 30);

// [layers] lists, for each glass layer, the shapes it holds.
Widget _scene(List<List<int>> layers) => Directionality(
  textDirection: TextDirection.ltr,
  child: RepaintBoundary(
    key: _key,
    child: Stack(
      children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF1E3A8A), Color(0xFFF59E0B)],
              ),
            ),
          ),
        ),
        for (final shapes in layers)
          Positioned.fill(
            child: LiquidGlassLayer(
              settings: LiquidGlassSettings.ios27RegularLight().copyWith(
                frost: 0,
              ),
              child: Stack(
                children: [
                  for (final i in shapes)
                    Positioned.fromRect(
                      rect: _rect(i),
                      child: const LiquidGlass(
                        shape: LiquidRoundedSuperellipse(borderRadius: 10),
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

Future<Uint8List> _pixels(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_key),
  );
  final image = (await tester.runAsync(boundary.toImage))!;
  final bytes = (await tester.runAsync(image.toByteData))!;
  image.dispose();
  return bytes.buffer.asUint8List();
}

int _difference(Uint8List a, Uint8List b) {
  var largest = 0;
  for (var i = 0; i < a.length; i++) {
    final d = (a[i] - b[i]).abs();
    if (d > largest) largest = d;
  }
  return largest;
}

void main() {
  testWidgets('a layer of more than 16 shapes apart draws every one, as '
      'layers of fewer draw them', (tester) async {
    tester.view.physicalSize = const Size(380, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(LiquidGlass.precache);
    final messages = <String>[];
    final previousDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) messages.add(message);
    };

    Future<Uint8List> draw(List<List<int>> layers) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_scene(layers));
      await tester.pump();
      return _pixels(tester);
    }

    final all = [for (var i = 0; i < _shapes; i++) i];
    final Uint8List one;
    final Uint8List two;
    final Uint8List sixteen;
    try {
      one = await draw([all]);
      two = await draw([all.sublist(0, 10), all.sublist(10)]);
      sixteen = await draw([all.sublist(0, 16)]);
    } finally {
      debugPrint = previousDebugPrint;
    }

    expect(messages.where((m) => m.contains('are not drawn')), isEmpty);
    expect(_difference(one, two), lessThanOrEqualTo(2));
    expect(_difference(one, sixteen), greaterThan(10));
  }, skip: skipProperGlassTests);
}

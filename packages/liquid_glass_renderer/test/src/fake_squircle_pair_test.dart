import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import 'shared.dart';

const _key = ValueKey('fake pair');
const _background = Color(0xFF808080);

Future<Uint8List> _render(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(260, 180)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: _key,
          child: SizedBox(
            width: 260,
            height: 180,
            child: Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: _background)),
                Positioned(
                  left: 30,
                  top: 30,
                  child: LiquidGlassLayer(
                    fake: true,
                    child: LiquidGlass(
                      shape: LiquidRoundedSuperellipse(
                        borderRadius: 16,
                        bottomRadius: 40,
                      ),
                      child: SizedBox(width: 200, height: 120),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_key),
  );
  final image = (await tester.runAsync(boundary.toImage))!;
  final bytes = (await tester.runAsync(image.toByteData))!;
  image.dispose();
  return bytes.buffer.asUint8List();
}

void main() {
  testWidgets('fake glass draws a pair with its bottom radius', (
    tester,
  ) async {
    final pixels = await _render(tester);
    bool touched(int x, int y) {
      final i = (y * 260 + x) * 4;
      return (pixels[i] - 0x80).abs() > 4 ||
          (pixels[i + 1] - 0x80).abs() > 4 ||
          (pixels[i + 2] - 0x80).abs() > 4;
    }

    // How far along the diagonal from a corner of the glass's box the first
    // pixel the glass (or its border) touches lies.
    int reach(int cornerX, int cornerY, int dy) {
      for (var t = 0; t < 40; t++) {
        if (touched(cornerX + t, cornerY + dy * t)) return t;
      }
      return 40;
    }

    final top = reach(30, 30, 1);
    final bottom = reach(30, 149, -1);
    // A 40 pt corner starts about 7 px further in along the diagonal than a
    // 16 pt one.
    expect(bottom - top, greaterThan(4));
  }, skip: skipProperGlassTests);
}

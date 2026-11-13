import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:material_ui/material_ui.dart';

import 'shared.dart';

const _key = ValueKey('screen');
const _glass = Rect.fromLTWH(30, 40, 200, 120);

Widget _scene(double shrink) => Directionality(
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
                end: Alignment.bottomRight,
                begin: Alignment.topLeft,
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: LiquidGlassLayer(
            settings: LiquidGlassSettings.ios27RegularLight().copyWith(
              backdropShrink: shrink,
            ),
            child: Stack(
              children: [
                Positioned.fromRect(
                  rect: _glass,
                  child: const LiquidGlass(
                    shape: LiquidRoundedSuperellipse(borderRadius: 24),
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

Future<(Uint8List, int)> _pixels(WidgetTester tester, double shrink) async {
  await tester.pumpWidget(_scene(shrink));
  await tester.pump();
  return (await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_key),
    );
    final image = await boundary.toImage();
    final bytes = await image.toByteData();
    final width = image.width;
    image.dispose();
    return (bytes!.buffer.asUint8List(), width);
  }))!;
}

void main() {
  testWidgets('deep glass draws the same pixels with and without the shortcut '
      'past its bevel and rim', (tester) async {
    tester.view.physicalSize = const Size(260, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // A shrink too small to see turns the shortcut off.
    final (plain, width) = await _pixels(tester, 0);
    final (full, _) = await _pixels(tester, 0.0005);
    var worst = 0;
    final inside = _glass.deflate(30);
    for (var y = inside.top.toInt(); y < inside.bottom; y++) {
      for (var x = inside.left.toInt(); x < inside.right; x++) {
        final at = (y * width + x) * 4;
        for (var channel = 0; channel < 3; channel++) {
          final delta = (plain[at + channel] - full[at + channel]).abs();
          if (delta > worst) worst = delta;
        }
      }
    }
    expect(worst, lessThanOrEqualTo(2));
    final center = (100 * width + 130) * 4;
    expect(plain[center + 3], 255);
  }, skip: skipProperGlassTests);
}

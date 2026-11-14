import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/read.dart';
import 'package:material_ui/material_ui.dart';

import 'shared.dart';

const _key = ValueKey('screen');
const _dot = Offset(130, 95);

// A black page with one white dot, under frosted glass that covers it.
Widget _scene(double frost) => Directionality(
  textDirection: TextDirection.ltr,
  child: RepaintBoundary(
    key: _key,
    child: Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: Color(0xFF000000))),
        Positioned.fromRect(
          rect: Rect.fromCenter(center: _dot, width: 7, height: 7),
          child: const ColoredBox(color: Color(0xFFFFFFFF)),
        ),
        Positioned.fromRect(
          rect: const Rect.fromLTWH(30, 40, 200, 110),
          child: LiquidGlassLayer(
            settings: LiquidGlassSettings.ios27RegularLight().copyWith(
              frost: frost,
            ),
            child: const LiquidGlass(
              shape: LiquidRoundedSuperellipse(borderRadius: 28),
              child: SizedBox.expand(),
            ),
          ),
        ),
      ],
    ),
  ),
);

void main() {
  // A frost of a few sparse taps draws a point under the glass as that many
  // points: stars under clear glass were small flowers on the iPhone. A
  // copy frosted ahead of the glass weighs every pixel of the copy its
  // frost reaches, so the point is one soft dot: its light only falls
  // along every way out of its middle.
  for (final frost in [5.0, 8.0, 12.0]) {
    testWidgets('a point under glass frosted by $frost stays one point', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(260, 200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(() => debugGlassCopies = null);
      debugGlassCopies = true;
      copyIntoImages();
      await tester.pumpWidget(_scene(frost));
      await tester.pump();
      final glass = tester.allRenderObjects
          .whereType<RenderLiquidGlassLayer>()
          .toSet()
          .single;
      expect(glass.debugDrewOverCopy, isTrue);

      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(_key),
      );
      final image = (await tester.runAsync(boundary.toImage))!;
      final pixels = (await tester.runAsync(
        image.toByteData,
      ))!.buffer.asUint8List();
      final width = image.width;
      image.dispose();
      int light(int x, int y) => pixels[(y * width + x) * 4 + 1];

      final x = _dot.dx.round();
      final y = _dot.dy.round();
      final peak = light(x, y);
      final floor = light(x + 45, y);
      expect(peak - floor, greaterThan(6), reason: 'the dot shows');
      // The largest rise of light on the way out of the dot, over the
      // eight ways: a second point is a rise of many levels.
      var rise = 0;
      for (final (dx, dy) in const [
        (1, 0),
        (-1, 0),
        (0, 1),
        (0, -1),
        (1, 1),
        (-1, 1),
        (1, -1),
        (-1, -1),
      ]) {
        var lowest = peak;
        for (var step = 1; step <= 40; step++) {
          final at = light(x + dx * step, y + dy * step);
          if (at - lowest > rise) rise = at - lowest;
          if (at < lowest) lowest = at;
        }
      }
      debugPrint('POINT frost $frost peak ${peak - floor} rise $rise');
      expect(rise, lessThanOrEqualTo(1));
    }, skip: skipProperGlassTests);
  }
}

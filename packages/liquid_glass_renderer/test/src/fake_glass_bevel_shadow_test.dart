import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import 'shared.dart';

const _size = Size(200, 64);
const _origin = Offset(20, 28);

/// Darkening of FakeGlass over white, in 8-bit levels, 8 pt inside the top
/// and bottom walls relative to the center of the face.
Future<({double top, double bottom})> _innerShadow(
  WidgetTester tester,
  LiquidGlassSettings settings,
) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(240, 120);
  addTearDown(tester.view.reset);
  final key = GlobalKey();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        key: key,
        child: ColoredBox(
          color: Colors.white,
          child: LiquidGlassLayer(
            fake: true,
            settings: settings,
            defaultAppearance: const LiquidGlassAppearance.ios27ToolbarLight(),
            child: Stack(
              children: [
                Positioned(
                  left: _origin.dx,
                  top: _origin.dy,
                  child: const LiquidGlass(
                    shape: LiquidRoundedSuperellipse(borderRadius: 32),
                    child: SizedBox(width: 200, height: 64),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  for (var frame = 0; frame < 10; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage();
  final bytes = (await tester.runAsync(image.toByteData))!;
  final width = image.width;
  image.dispose();
  double luma(double x, double y) {
    final i = (y.round() * width + x.round()) * 4;
    return 0.2126 * bytes.getUint8(i) +
        0.7152 * bytes.getUint8(i + 1) +
        0.0722 * bytes.getUint8(i + 2);
  }

  final x = _origin.dx + _size.width / 2;
  final face = luma(x, _origin.dy + _size.height / 2);
  return (
    top: face - luma(x, _origin.dy + 8),
    bottom: face - luma(x, _origin.dy + _size.height - 8),
  );
}

void main() {
  final base = const LiquidGlassSettings.ios27ToolbarLight(
    frost: 0,
  ).copyWith(highlight: 0, contourStrength: 0);

  testWidgets(
    'FakeGlass draws the preset inner shadow below the top wall only',
    (tester) async {
      final preset = await _innerShadow(tester, base);
      final none = await _innerShadow(
        tester,
        base.copyWith(bevelShadowStrength: 0),
      );
      final strong = await _innerShadow(
        tester,
        base.copyWith(bevelShadowStrength: 0.15),
      );

      expect(none.top, closeTo(0, 0.6));
      // Measured on the iOS 27 references: about 4 levels on white.
      expect(preset.top, inInclusiveRange(2.5, 5.5));
      expect(preset.bottom, lessThan(1.5));
      // The shadow follows the configured strength, as in real glass.
      expect(strong.top / preset.top, closeTo(0.15 / 0.017, 1.5));
    },
    skip: skipProperGlassTests,
  );
}

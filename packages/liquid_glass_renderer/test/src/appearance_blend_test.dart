import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import 'shared.dart';

const _dpr = 2.0;
const _sceneSize = 360.0;

/// Light, dark, clear and tinted glass merged in one blend group, laid out
/// as a 2x2 grid of 108 pt circles 100 pt apart (the example playground's
/// Colors scene).
class _MergedAppearances extends StatelessWidget {
  const _MergedAppearances();

  static const _swatches = [
    (Offset(-50, -50), LiquidGlassAppearance.ios27RegularLight()),
    (Offset(50, -50), LiquidGlassAppearance.ios27RegularDark()),
    (Offset(-50, 50), LiquidGlassAppearance.ios27Clear()),
    (
      Offset(50, 50),
      LiquidGlassAppearance.ios27RegularLight(tint: Color(0xFF0A84FF)),
    ),
  ];

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFF8C8C8C),
    child: LiquidGlassLayer(
      settings: LiquidGlassSettings.ios27Toolbar(brightness: Brightness.dark),
      child: LiquidGlassBlendGroup(
        blend: 24,
        child: Stack(
          children: [
            for (final (offset, appearance) in _swatches)
              Positioned(
                left: _sceneSize / 2 + offset.dx - 54,
                top: _sceneSize / 2 + offset.dy - 54,
                child: LiquidGlass.grouped(
                  appearance: appearance,
                  shape: const LiquidOval(),
                  child: const SizedBox.square(dimension: 108),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'merged appearances blend across the bridge without a seam',
    (tester) async {
      tester.view
        ..devicePixelRatio = _dpr
        ..physicalSize = const Size.square(_sceneSize * _dpr);
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: RepaintBoundary(key: key, child: const _MergedAppearances()),
        ),
      );
      for (var frame = 0; frame < 30; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: _dpr);
      final bytes = (await tester.runAsync(image.toByteData))!;
      final width = image.width;
      image.dispose();

      List<int> pixel(double x, double y) {
        final offset = ((y * _dpr).round() * width + (x * _dpr).round()) * 4;
        return bytes.buffer.asUint8List(bytes.offsetInBytes + offset, 3);
      }

      // Each bridge is crossed along the direction its appearance changes,
      // away from the rims and the hole in the middle.
      final bridges = <String, (Offset, Offset)>{
        'light-dark': (const Offset(150, 110), const Offset(210, 110)),
        'light-clear': (const Offset(110, 150), const Offset(110, 210)),
        'clear-blue': (const Offset(150, 226), const Offset(210, 226)),
        'dark-blue': (const Offset(250, 150), const Offset(250, 210)),
      };
      for (final MapEntry(key: name, value: (start, end)) in bridges.entries) {
        final steps = ((end - start).distance * _dpr).round();
        var largestStep = 0;
        List<int>? previous;
        for (var i = 0; i <= steps; i++) {
          final p = Offset.lerp(start, end, i / steps)!;
          final current = List<int>.of(pixel(p.dx, p.dy));
          if (previous != null) {
            for (var c = 0; c < 3; c++) {
              final step = (current[c] - previous[c]).abs();
              if (step > largestStep) largestStep = step;
            }
          }
          previous = current;
        }
        final first = pixel(start.dx, start.dy);
        final last = pixel(end.dx, end.dy);
        final span = [
          for (var c = 0; c < 3; c++) (first[c] - last[c]).abs(),
        ].reduce((a, b) => a > b ? a : b);
        expect(
          span,
          greaterThan(20),
          reason: '$name: the two appearances should differ',
        );
        expect(
          largestStep,
          lessThanOrEqualTo(6),
          reason: '$name: largest step between neighboring pixels',
        );
      }
    },
    skip: skipProperGlassTests,
  );
}

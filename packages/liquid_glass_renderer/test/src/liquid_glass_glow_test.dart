import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

import 'shared.dart';

const _key = ValueKey('glow');
const _view = Size(260, 180);
const _glass = Rect.fromLTWH(30, 40, 200, 100);
const _gray = Color(0xFF808080);

final _glow = LiquidGlassGlow(
  bounds: _glass,
  cornerRadius: 20,
  center: const Offset(80, 90),
  radius: 20,
  gain: 0.5,
  wash: 0.1,
);

Widget _scene(LiquidGlassGlow? glow) => Directionality(
  textDirection: TextDirection.ltr,
  child: Center(
    child: RepaintBoundary(
      key: _key,
      child: SizedBox.fromSize(
        size: _view,
        child: ColoredBox(
          color: _gray,
          child: LiquidGlassLayer(
            settings: LiquidGlassSettings.ios27RegularLight(),
            // A paint over a solid color: no backdrop filter, so every
            // render of the process draws.
            backdrop: const LiquidGlassBackdrop.solid(_gray),
            glow: glow,
            child: Stack(
              children: [
                Positioned.fromRect(
                  rect: _glass,
                  child: const LiquidGlass(
                    shape: LiquidRoundedSuperellipse(borderRadius: 20),
                    child: SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  ),
);

Future<Uint8List> _render(WidgetTester tester, LiquidGlassGlow? glow) async {
  tester.view
    ..physicalSize = _view
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_scene(glow));
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
  testWidgets('a glow lights the glass as its CPU reference does', (
    tester,
  ) async {
    final plain = await _render(tester, null);
    final lit = await _render(tester, _glow);
    final uniforms = LiquidGlassGlow.uniformsOf(_glow, 1);

    (double, double, double) at(Uint8List rgba, Offset p) {
      final i = (p.dy.toInt() * _view.width.toInt() + p.dx.toInt()) * 4;
      return (rgba[i] / 255, rgba[i + 1] / 255, rgba[i + 2] / 255);
    }

    for (final p in const [
      Offset(80, 90),
      Offset(100, 100),
      Offset(200, 90),
      Offset(60, 120),
    ]) {
      final expected = LiquidGlassGlow.shade(
        uniforms,
        p + const Offset(0.5, 0.5),
        at(plain, p),
      );
      final actual = at(lit, p);
      expect(actual.$1, closeTo(expected.$1, 3 / 255), reason: '$p red');
      expect(actual.$2, closeTo(expected.$2, 3 / 255), reason: '$p green');
      expect(actual.$3, closeTo(expected.$3, 3 / 255), reason: '$p blue');
    }
    // The spot is brighter than the wash alone.
    expect(
      at(lit, const Offset(80, 90)).$1,
      greaterThan(at(lit, const Offset(200, 90)).$1),
    );
    // Outside the lit shape nothing changes.
    for (final p in const [Offset(10, 10), Offset(245, 90), Offset(130, 160)]) {
      expect(at(lit, p), at(plain, p), reason: '$p');
    }
  }, skip: skipProperGlassTests);

  test('no glow writes zero uniforms', () {
    expect(LiquidGlassGlow.uniformsOf(null, 3), List<double>.filled(12, 0));
  });

  testWidgets('a new glow reaches the retained pass without a repaint', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: LiquidGlassLayer(
          settings: LiquidGlassSettings.ios27RegularLight(),
          child: Stack(
            children: [
              Positioned.fromRect(
                rect: _glass,
                child: const LiquidGlass(
                  shape: LiquidRoundedSuperellipse(borderRadius: 20),
                  child: SizedBox.expand(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final layer = tester.allRenderObjects
        .whereType<RenderLiquidGlassLayer>()
        .toSet()
        .single;
    final unlit = layer.debugBackdropFilterLayer!.filter;

    layer.glow = _glow;
    expect(layer.debugNeedsPaint, isFalse);
    expect(layer.debugBackdropFilterLayer!.filter, isNot(unlit));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump();
    expect(layer.glow, _glow);
  }, skip: skipProperGlassTests);
}

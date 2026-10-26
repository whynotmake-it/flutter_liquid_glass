import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

import 'shared.dart';

const _key = ValueKey('solid');
const _view = Size(300, 200);
const _gray = Color(0xFF7A8290);

Widget _scene(LiquidGlassBackdrop backdrop) => Directionality(
  textDirection: TextDirection.ltr,
  child: RepaintBoundary(
    key: _key,
    child: SizedBox.fromSize(
      size: _view,
      child: ColoredBox(
        color: _gray,
        child: LiquidGlassLayer(
          settings: LiquidGlassSettings.ios27RegularLight(),
          backdrop: backdrop,
          child: Stack(
            children: [
              Positioned.fromRect(
                rect: const Rect.fromLTWH(40, 50, 200, 90),
                child: const LiquidGlass(
                  shape: LiquidRoundedSuperellipse(borderRadius: 30),
                  child: SizedBox.expand(),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);

Future<Uint8List> _render(
  WidgetTester tester,
  LiquidGlassBackdrop backdrop,
) async {
  tester.view
    ..physicalSize = _view
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_scene(backdrop));
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
  testWidgets('glass over a solid backdrop paints what reading it draws', (
    tester,
  ) async {
    // flutter_tester renders a process's first backdrop filter reliably
    // only: the reference reads the backdrop first.
    final reading = await _render(tester, const LiquidGlassBackdrop.read());
    final layer = tester.allRenderObjects
        .whereType<RenderLiquidGlassLayer>()
        .toSet()
        .single;
    expect(layer.debugBackdropFilterLayer, isNotNull);

    final solid = await _render(tester, const LiquidGlassBackdrop.solid(_gray));
    expect(layer.debugBackdropFilterLayer, isNull);
    var largest = 0;
    for (var i = 0; i < reading.length; i++) {
      final d = (reading[i] - solid[i]).abs();
      if (d > largest) largest = d;
    }
    expect(largest, lessThanOrEqualTo(1));

    // The glass shades the declared color, not what lies behind it.
    final other = await _render(
      tester,
      const LiquidGlassBackdrop.solid(Color(0xFF203040)),
    );
    var moved = 0;
    for (var i = 0; i < reading.length; i++) {
      final d = (reading[i] - other[i]).abs();
      if (d > moved) moved = d;
    }
    expect(moved, greaterThan(32));
  }, skip: skipProperGlassTests);
}

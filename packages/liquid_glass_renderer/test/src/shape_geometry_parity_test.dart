import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/shading.dart';
import 'package:material_ui/material_ui.dart';

import 'shared.dart';

const _key = ValueKey('parity');
const _view = Size(320, 240);
const _gray = Color(0xFF7A8290);
const _glass = Rect.fromLTWH(30, 30, 200, 140);

// One glass in the middle of [_glass]; with [beside], a second, small one in
// the corner of the view, which makes the layer's geometry an atlas.
Widget _scene(Widget glass, {required bool beside}) => Directionality(
  textDirection: TextDirection.ltr,
  child: RepaintBoundary(
    key: _key,
    child: SizedBox.fromSize(
      size: _view,
      child: ColoredBox(
        color: _gray,
        child: LiquidGlassLayer(
          // Large glass whose refraction fits its shape leans its normals
          // and is an atlas alone too; this one's shader works it out.
          settings: LiquidGlassSettings.ios27RegularLight().copyWith(
            refractionFitsShape: false,
          ),
          // A paint over a solid color, not a backdrop filter: flutter_tester
          // renders only a process's first backdrop filter reliably.
          backdrop: const LiquidGlassBackdrop.solid(_gray),
          child: Stack(
            children: [
              Positioned.fromRect(
                rect: _glass,
                child: Center(child: glass),
              ),
              if (beside)
                const Positioned(
                  right: 8,
                  bottom: 8,
                  width: 16,
                  height: 16,
                  child: LiquidGlass(
                    shape: LiquidOval(),
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

Widget _shape(LiquidShape shape, Size size) => SizedBox.fromSize(
  size: size,
  child: LiquidGlass(shape: shape, child: const SizedBox.expand()),
);

Future<Uint8List> _capture(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_key),
  );
  final image = (await tester.runAsync(
    () => boundary.toImage(pixelRatio: tester.view.devicePixelRatio),
  ))!;
  final bytes = (await tester.runAsync(image.toByteData))!;
  image.dispose();
  return bytes.buffer.asUint8List();
}

RenderLiquidGlassLayer _layer(WidgetTester tester) =>
    tester.allRenderObjects.whereType<RenderLiquidGlassLayer>().toSet().single;

void main() {
  // The geometry of glass is one function of its shapes and a pixel
  // (gpu/sdf.glsl). Glass of one shape has the shader work it out at each
  // fragment; the same glass beside another reads it from an atlas, whose
  // smooth parts hold a texel for every 4 x 4 pixels. The two draw the
  // same glass, within what those texels cost.
  for (final (name, glass) in [
    (
      'a rounded superellipse',
      _shape(
        const LiquidRoundedSuperellipse(borderRadius: 30),
        const Size(160, 110),
      ),
    ),
    (
      'a capsule',
      _shape(
        const LiquidRoundedSuperellipse(borderRadius: 1000),
        const Size(180, 48),
      ),
    ),
    (
      'a rounded rectangle',
      _shape(
        const LiquidRoundedRectangle(borderRadius: 22),
        const Size(150, 100),
      ),
    ),
    ('an oval', _shape(const LiquidOval(), const Size(170, 100))),
    (
      'a pair of radii',
      _shape(
        const LiquidRoundedSuperellipse(borderRadius: 16, bottomRadius: 40),
        const Size(180, 90),
      ),
    ),
    (
      'a turned, scaled superellipse',
      Transform.rotate(
        angle: 0.35,
        child: Transform.scale(
          scale: 1.2,
          child: _shape(
            const LiquidRoundedSuperellipse(borderRadius: 24),
            const Size(120, 70),
          ),
        ),
      ),
    ),
  ]) {
    for (final dpr in [1.0, 3.0]) {
      testWidgets('$name alone draws as it does from an atlas at $dpr', (
        tester,
      ) async {
        tester.view
          ..physicalSize = _view * dpr
          ..devicePixelRatio = dpr;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_scene(glass, beside: false));
        await tester.pump();
        expect(_layer(tester).debugGeometry, isA<ComputedGeometry>());
        expect(_layer(tester).gpuGeometryRenderer!.debugRenderCount, 0);
        final computed = await _capture(tester);

        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(_scene(glass, beside: true));
        await tester.pump();
        expect(_layer(tester).debugGeometry, isA<AtlasGeometry>());
        final atlas = await _capture(tester);

        final width = (_view.width * dpr).round();
        var seen = 0;
        var farthest = 0;
        for (var y = (_glass.top * dpr).round(); y < _glass.bottom * dpr; y++) {
          for (
            var x = (_glass.left * dpr).round();
            x < _glass.right * dpr;
            x++
          ) {
            final at = (y * width + x) * 4;
            if (computed[at] != 0x7A) seen++;
            for (var c = 0; c < 3; c++) {
              farthest = max(
                farthest,
                (computed[at + c] - atlas[at + c]).abs(),
              );
            }
          }
        }
        expect(seen, greaterThan(1000), reason: 'the glass is drawn');
        // Measured: at most 5 of 255, an oval's rim at 3 pixels a point.
        expect(farthest, lessThanOrEqualTo(6));
      }, skip: skipProperGlassTests);
    }
  }
}

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/rounded_superellipse_parameters.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

import 'gpu_test_helpers.dart';
import 'shared.dart';

const _key = ValueKey('pair');
const _size = Size(200, 120);
const _top = 16.0;
const _bottom = 40.0;

Widget _scene({required bool glass}) => Directionality(
  textDirection: TextDirection.ltr,
  child: Center(
    child: RepaintBoundary(
      key: _key,
      child: SizedBox(
        width: 260,
        height: 180,
        child: Stack(
          children: [
            // Stripes, so the glass's bevel visibly moves the backdrop near
            // its rim.
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1E3A8A), Color(0xFFF8FAFC)],
                    stops: [0.5, 0.5],
                    tileMode: TileMode.repeated,
                    end: Alignment(-0.9, -1),
                  ),
                ),
              ),
            ),
            if (glass)
              const Positioned(
                left: 30,
                top: 30,
                child: LiquidGlassLayer(
                  settings: LiquidGlassSettings(frost: 4),
                  child: LiquidGlass(
                    shape: LiquidRoundedSuperellipse(
                      borderRadius: _top,
                      bottomRadius: _bottom,
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
);

Future<Uint8List> _render(WidgetTester tester, {required bool glass}) async {
  tester.view
    ..physicalSize = const Size(260, 180)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // The test config precaches the glass, so it is real from the first frame.
  await tester.pumpWidget(_scene(glass: glass));
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
  testWidgets('a squircle pair draws its top and bottom radii', (
    tester,
  ) async {
    // flutter_tester renders only a process's first backdrop filter
    // reliably, so the glass renders first; the reference has none.
    final withGlass = await _render(tester, glass: true);
    final backdrop = await _render(tester, glass: false);
    final rect = const Offset(30, 30) & _size;
    final pair = const LiquidRoundedSuperellipse(
      borderRadius: _top,
      bottomRadius: _bottom,
    ).getOuterPath(rect);
    final uniform = const LiquidRoundedSuperellipse(
      borderRadius: _top,
    ).getOuterPath(rect);

    bool changed(int x, int y) {
      final i = (y * 260 + x) * 4;
      for (var c = 0; c < 3; c++) {
        if ((withGlass[i + c] - backdrop[i + c]).abs() > 6) return true;
      }
      return false;
    }

    const around = [Offset(1.5, 1.5), Offset(-1.5, 1.5), Offset(1.5, -1.5)];
    bool clearlyIn(Path path, Offset p) =>
        around.every((d) => path.contains(p + d) && path.contains(p - d));
    bool clearlyOut(Path path, Offset p) =>
        around.every((d) => !path.contains(p + d) && !path.contains(p - d));

    // The bottom corners' band between the top-radius and bottom-radius
    // corners: glass there means the bottom was drawn with the top radius.
    var band = 0;
    var bandChanged = 0;
    var glass = 0;
    for (var y = 90; y < 150; y++) {
      for (var x = 30; x < 230; x++) {
        final p = Offset(x + 0.5, y + 0.5);
        if (clearlyOut(pair, p) && clearlyIn(uniform, p)) {
          band++;
          if (changed(x, y)) bandChanged++;
        }
        if (changed(x, y)) glass++;
      }
    }
    expect(glass, greaterThan(2000), reason: 'the glass draws');
    expect(band, greaterThan(100));
    expect(bandChanged, 0);
  }, skip: skipProperGlassTests);

  test('a pair is a squircle with different bottom corners', () {
    const pair = LiquidRoundedSuperellipse(borderRadius: 16, bottomRadius: 40);
    expect(pair.isUniform, isFalse);
    expect(pair.effectiveBottomRadius, 40);
    expect(
      pair.scale(0.5),
      const LiquidRoundedSuperellipse(borderRadius: 8, bottomRadius: 20),
    );
    expect(
      const LiquidRoundedSuperellipse(borderRadius: 16).isUniform,
      isTrue,
    );
  });

  test('radii that overflow a side scale down together, as Impeller does', () {
    // Two 80 pt top corners need 160 pt of a 100 pt side: every radius
    // takes 100 / 160, so the bottom corners draw at 12.5, not 20.
    final pair = roundedSuperellipsePairParameters(
      const Size(100, 300),
      80,
      20,
    );
    expect(
      pair.sublist(0, 12),
      roundedSuperellipseParameters(const Size(100, 480), 50),
    );
    expect(pair[12 + 8], 12.5);
  });

  testWidgets('a pair has no step in its depth at the split line', (
    tester,
  ) async {
    // 60 tall with radii 16 and 40: the top half is about 17 tall, thinner
    // than the bevel, so a step at the line would show in the refraction.
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: LiquidGlassLayer(
            settings: LiquidGlassSettings.ios27RegularLight(),
            child: const SizedBox(
              width: 240,
              height: 60,
              child: LiquidGlass(
                shape: LiquidRoundedSuperellipse(
                  borderRadius: 16,
                  bottomRadius: 40,
                ),
                child: SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final layer = tester.allRenderObjects
        .whereType<RenderLiquidGlassLayer>()
        .toSet()
        .single;
    final image = layer.debugGeometryImage!;
    final field = (await tester.runAsync(() => readGeometryField(image)))!;
    final bounds = layer.debugGeometryMatteBounds;
    final x = bounds.width ~/ 2;
    double depth(int y) => fieldInwardAt(
      field,
      image.width,
      x,
      y,
      scale: layer.matteScale,
    );
    var steepest = 0.0;
    for (var y = 0; y + 1 < bounds.height; y++) {
      if (depth(y) <= 0 || depth(y + 1) <= 0) continue;
      steepest = max(steepest, (depth(y + 1) - depth(y)).abs());
    }
    // The depth moves at most one matte pixel per matte pixel, plus the
    // matte's interpolation.
    expect(steepest, lessThan(2));
  }, skip: skipProperGlassTests);
}

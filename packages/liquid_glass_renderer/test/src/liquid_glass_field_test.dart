import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import 'shared.dart';

const _key = ValueKey('field');
const _view = Size(260, 180);
const _circleCenter = Offset(60, 60);
const _circleRadius = 30.0;
const _box = Rect.fromLTWH(120, 30, 100, 120);
const _boxRadius = 20.0;
const _blend = 100.0;

double _circle(Offset p) => (p - _circleCenter).distance - _circleRadius;

double _roundedBox(Offset p) {
  final q = Offset(
    (p.dx - _box.center.dx).abs() - _box.width / 2 + _boxRadius,
    (p.dy - _box.center.dy).abs() - _box.height / 2 + _boxRadius,
  );
  final outside = Offset(math.max(q.dx, 0), math.max(q.dy, 0)).distance;
  return outside + math.min(math.max(q.dx, q.dy), 0) - _boxRadius;
}

/// The circle and the box fused by a polynomial smooth minimum: a neck
/// joins them where neither shape lies.
double _body(Offset p) {
  final a = _circle(p);
  final b = _roundedBox(p);
  final h = (0.5 + 0.5 * (b - a) / _blend).clamp(0.0, 1.0);
  return b + (a - b) * h - _blend * h * (1 - h);
}

LiquidGlassField _field() {
  const step = 4.0;
  final cols = (_view.width / step).ceil() + 1;
  final rows = (_view.height / step).ceil() + 1;
  final samples = Float32List(cols * rows * 4);
  for (var j = 0; j < rows; j++) {
    for (var i = 0; i < cols; i++) {
      final p = Offset(i * step, j * step);
      final at = (j * cols + i) * 4;
      samples[at] = _body(p);
      samples[at + 1] =
          _body(p + const Offset(0.5, 0)) - _body(p - const Offset(0.5, 0));
      samples[at + 2] =
          _body(p + const Offset(0, 0.5)) - _body(p - const Offset(0, 0.5));
      samples[at + 3] = _circleRadius;
    }
  }
  return LiquidGlassField(
    samples: samples,
    cols: cols,
    rows: rows,
    origin: Offset.zero,
    step: step,
  );
}

Widget _scene({required bool glass, LiquidGlassField? field}) => Directionality(
  textDirection: TextDirection.ltr,
  child: Center(
    child: RepaintBoundary(
      key: _key,
      child: SizedBox.fromSize(
        size: _view,
        child: Stack(
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1E3A8A), Color(0xFFF8FAFC)],
                    stops: [0.5, 0.5],
                    tileMode: TileMode.repeated,
                    // Stripes about 5 px apart: any frost changes them.
                    begin: Alignment.topLeft,
                    end: Alignment(-0.97, -0.96),
                  ),
                ),
              ),
            ),
            if (glass)
              Positioned.fill(
                child: LiquidGlassLayer(
                  settings: const LiquidGlassSettings(frost: 4),
                  field: field,
                  child: Stack(
                    children: [
                      Positioned.fromRect(
                        rect: Rect.fromCircle(
                          center: _circleCenter,
                          radius: _circleRadius,
                        ),
                        child: const LiquidGlass(
                          shape: LiquidOval(),
                          child: SizedBox.expand(),
                        ),
                      ),
                      Positioned.fromRect(
                        rect: _box,
                        child: const LiquidGlass(
                          shape: LiquidRoundedSuperellipse(
                            borderRadius: _boxRadius,
                          ),
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
    ),
  ),
);

Future<Uint8List> _render(WidgetTester tester, Widget scene) async {
  tester.view
    ..physicalSize = _view
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(scene);
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
  testWidgets('a field shades the body its owner fused', (tester) async {
    // flutter_tester renders a process's first backdrop filter reliably
    // only; the reference has none.
    final withGlass = await _render(
      tester,
      _scene(glass: true, field: _field()),
    );
    final backdrop = await _render(tester, _scene(glass: false));

    bool changed(int x, int y) {
      final i = (y * _view.width.toInt() + x) * 4;
      for (var c = 0; c < 3; c++) {
        if ((withGlass[i + c] - backdrop[i + c]).abs() > 6) return true;
      }
      return false;
    }

    // The neck: inside the fused body, clearly outside both shapes.
    var neck = 0;
    var neckChanged = 0;
    var outside = 0;
    var outsideChanged = 0;
    for (var y = 0; y < _view.height.toInt(); y++) {
      for (var x = 0; x < _view.width.toInt(); x++) {
        final p = Offset(x + 0.5, y + 0.5);
        if (_body(p) < -6 && _circle(p) > 4 && _roundedBox(p) > 4) {
          neck++;
          if (changed(x, y)) neckChanged++;
        }
        if (_body(p) > 4) {
          outside++;
          if (changed(x, y)) outsideChanged++;
        }
      }
    }
    expect(neck, greaterThan(100));
    expect(neckChanged / neck, greaterThan(0.9));
    expect(outsideChanged / outside, lessThan(0.01));
  }, skip: skipProperGlassTests);
}

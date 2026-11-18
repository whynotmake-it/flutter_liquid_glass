import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4;

const _box = Size(120, 44);

LiquidGlassShapeFrame _frame({Rect? rect, double sx = 1, double sy = 1}) =>
    LiquidGlassShapeFrame(
      shape: const LiquidRoundedSuperellipse(radius: 12),
      rect: rect,
      scaleX: sx,
      scaleY: sy,
    );

void main() {
  test('a body in place has no transform and paints at the box', () {
    const body = LiquidGlassBody(_box);
    expect(body.toBox, isNull);
    expect(body.childToBox, isNull);
    expect(body.size, _box);
    expect(body.drawnRect, Offset.zero & _box);
    expect(body.childOffset, Offset.zero);
  });

  test('the body maps onto its drawn rect, the child centered on it', () {
    for (final (rect, sx, sy) in [
      (const Rect.fromLTWH(10, 4, 60, 30), 1.0, 1.0),
      (const Rect.fromLTWH(10, 4, 60, 30), 1.2, 0.9),
      (null, 1.15, 1.15),
      (const Rect.fromLTWH(-5, 0, 200, 44), 0.8, 1.3),
    ]) {
      final body = _frame(rect: rect, sx: sx, sy: sy).bodyIn(_box);
      final toBox = body.toBox ?? Matrix4.identity();
      expect(
        MatrixUtils.transformRect(toBox, Offset.zero & body.size),
        rectMoreOrLessEquals(body.drawnRect, epsilon: 1e-9),
      );
      final childCenter = MatrixUtils.transformPoint(
        toBox,
        _box.center(Offset.zero) + body.childOffset,
      );
      expect(childCenter.dx, moreOrLessEquals(body.drawnRect.center.dx));
      expect(childCenter.dy, moreOrLessEquals(body.drawnRect.center.dy));
      expect(
        MatrixUtils.transformPoint(
          body.childToBox ?? Matrix4.identity(),
          _box.center(Offset.zero),
        ),
        offsetMoreOrLessEquals(childCenter),
      );
    }
  });

  test('bodies are equal when they draw in the same place', () {
    const rect = Rect.fromLTWH(10, 4, 60, 30);
    final bodies = [
      () => _frame().bodyIn(_box),
      () => _frame(rect: rect).bodyIn(_box),
      () => _frame(rect: rect, sx: 1.2).bodyIn(_box),
      () => _frame(rect: rect, sy: 1.2).bodyIn(_box),
      () => _frame().bodyIn(const Size(120, 50)),
    ];
    for (final (i, a) in bodies.indexed) {
      for (final (j, b) in bodies.indexed) {
        expect(a() == b(), i == j, reason: '${a()} and ${b()}');
        if (i == j) expect(a().hashCode, b().hashCode);
      }
    }
    expect(
      _frame().bodyIn(_box),
      _frame(rect: Offset.zero & _box).bodyIn(_box),
      reason: 'no rect is the whole box',
    );
    expect(
      '${_frame(rect: rect, sx: 1.2).bodyIn(_box)}',
      'LiquidGlassBody(Rect.fromLTRB(10.0, 4.0, 70.0, 34.0) in '
          'Size(120.0, 44.0), scale: 1.2 x 1.0)',
    );
  });

  test('frames are equal when they describe the same glass', () {
    const shadow = LiquidGlassShadow(
      color: Color(0x40000000),
      offset: Offset(0, 4),
      blurRadius: 12,
    );
    final frames = [
      _frame,
      () => _frame(rect: const Rect.fromLTWH(10, 4, 60, 30)),
      () => _frame(sx: 1.2),
      () => _frame(sy: 1.2),
      () => const LiquidGlassShapeFrame(shape: LiquidOval()),
      () => LiquidGlassShapeFrame(
        shape: const LiquidRoundedSuperellipse(radius: 12),
        shadows: List.of(const [shadow]),
      ),
      () => const LiquidGlassShapeFrame(
        shape: LiquidRoundedSuperellipse(radius: 12),
        appearance: LiquidGlassAppearance(visibility: 0.5),
      ),
      () => const LiquidGlassShapeFrame(
        shape: LiquidRoundedSuperellipse(radius: 12),
        glow: LiquidGlassGlow(wash: 0.1),
      ),
    ];
    for (final (i, a) in frames.indexed) {
      for (final (j, b) in frames.indexed) {
        expect(a() == b(), i == j, reason: '${a()} and ${b()}');
        if (i == j) expect(a().hashCode, b().hashCode);
      }
    }
  });
}

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/painting.dart';

/// The four values of the node of [field] nearest [at].
(double, double, double, double) _node(LiquidGlassField field, Offset at) {
  final i = ((at.dx - field.origin.dx) / field.step).round();
  final j = ((at.dy - field.origin.dy) / field.step).round();
  final k = (j * field.cols + i) * 4;
  final s = field.samples;
  return (s[k], s[k + 1], s[k + 2], s[k + 3]);
}

void main() {
  test('the field of a circle holds its distance, its outward gradient and '
      'its radius as half thickness', () {
    const center = Offset(100, 80);
    final field = LiquidGlassField.fromPath(
      Path()..addOval(Rect.fromCircle(center: center, radius: 40)),
    );
    for (final (at, distance, gx, gy) in [
      (const Offset(100, 80), -40.0, 0.0, 0.0),
      (const Offset(120, 80), -20.0, 1.0, 0.0),
      (const Offset(100, 60), -20.0, 0.0, -1.0),
      (const Offset(144, 80), 4.0, 1.0, 0.0),
      (const Offset(100, 124), 4.0, 0.0, 1.0),
    ]) {
      final (d, x, y, half) = _node(field, at);
      expect(d, closeTo(distance, 0.3), reason: '$at');
      // The gradient at the very center has no direction.
      if (distance > -40) {
        expect(x, closeTo(gx, 0.05), reason: '$at');
        expect(y, closeTo(gy, 0.05), reason: '$at');
      }
      expect(half, closeTo(40, 0.5));
    }
  });

  test('the grid covers the body with a margin of at least two nodes', () {
    final field = LiquidGlassField.fromPath(
      Path()..addRect(const Rect.fromLTWH(11, 7, 50, 30)),
      step: 4,
    );
    expect(field.origin.dx, lessThanOrEqualTo(11 - 8));
    expect(field.origin.dy, lessThanOrEqualTo(7 - 8));
    final right = field.origin.dx + (field.cols - 1) * field.step;
    final bottom = field.origin.dy + (field.rows - 1) * field.step;
    expect(right, greaterThanOrEqualTo(61 + 8));
    expect(bottom, greaterThanOrEqualTo(37 + 8));
    expect(field.samples.length, field.cols * field.rows * 4);
  });

  test('a hole is outside the body', () {
    final ring = Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(Rect.fromCircle(center: const Offset(60, 60), radius: 40))
      ..addOval(Rect.fromCircle(center: const Offset(60, 60), radius: 20));
    final field = LiquidGlassField.fromPath(ring);
    expect(_node(field, const Offset(60, 60)).$1, closeTo(20, 0.3));
    expect(_node(field, const Offset(90, 60)).$1, closeTo(-10, 0.3));
    // The ring is 20 thick.
    expect(_node(field, const Offset(90, 60)).$4, closeTo(10, 0.5));
  });

  test('contours that overlap form one body, with no edge inside it', () {
    final body = Path()
      ..addOval(Rect.fromCircle(center: const Offset(60, 60), radius: 40))
      ..addOval(Rect.fromCircle(center: const Offset(100, 60), radius: 40));
    final field = LiquidGlassField.fromPath(body);
    // (80, 60) lies on neither circle's edge but 20 inside both; the
    // nearest edge of the body is where the circles cross, at (80, 60 +-
    // 34.6).
    expect(_node(field, const Offset(80, 60)).$1, closeTo(-34.6, 0.5));
    // (98, 60) lies 2 inside the first circle's edge, which runs through
    // the second circle there and is no edge of the body: the nearest one
    // is where the circles cross, 39.0 away.
    expect(_node(field, const Offset(98, 60)).$1, closeTo(-39.0, 0.5));
  });

  test('a thickness given is the thickness everywhere', () {
    final field = LiquidGlassField.fromPath(
      Path()..addRect(const Rect.fromLTWH(0, 0, 80, 40)),
      thickness: 12,
    );
    expect(_node(field, const Offset(40, 20)).$4, 6);
    expect(_node(field, const Offset(-4, 20)).$4, 6);
  });

  test('a path that encloses nothing is refused', () {
    expect(() => LiquidGlassField.fromPath(Path()), throwsArgumentError);
    expect(
      () => LiquidGlassField.fromPath(
        Path()..addRect(const Rect.fromLTWH(0, 0, 10, 10)),
        step: 0,
      ),
      throwsArgumentError,
    );
  });
}

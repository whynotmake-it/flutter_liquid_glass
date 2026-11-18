import 'dart:ui';

import 'package:apple_liquid_glass/motions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/painting.dart';

PopoverShape _down(double width, double height, double center) => PopoverShape(
  content: Rect.fromLTWH(0, 0, width, height),
  direction: PopoverArrowDirection.down,
  arrowCenter: center,
  cornerRadius: 34,
);

double _sample(LiquidGlassField field, Offset p) {
  final gx = (p.dx - field.origin.dx) / field.step;
  final gy = (p.dy - field.origin.dy) / field.step;
  final i = gx.floor();
  final j = gy.floor();
  final u = gx - i;
  final v = gy - j;
  double at(int i, int j) => field.samples[(j * field.columns + i) * 4];
  return at(i, j) * (1 - u) * (1 - v) +
      at(i + 1, j) * u * (1 - v) +
      at(i, j + 1) * (1 - u) * v +
      at(i + 1, j + 1) * u * v;
}

void main() {
  // The points below are on the path UIKit's popover chrome draws for an
  // action sheet on the iOS 27 simulator (content 240 x 264.33, arrow
  // centered, and the arrow slid toward a corner).
  const h = 264.333;

  test('the arrow leaves the edge through fillets and ends in a round tip', () {
    final path = _down(240, h, 120).path;
    // The tip: its cubic's controls sit 13 below the edge, so it reaches
    // 12.75.
    expect(path.contains(const Offset(120, h + 12.6)), isTrue);
    expect(path.contains(const Offset(120, h + 12.9)), isFalse);
    // The fillet passes 0.75 below the edge half a base from the center.
    expect(path.contains(const Offset(107, h + 0.5)), isTrue);
    expect(path.contains(const Offset(107, h + 1)), isFalse);
    // It starts 18.5 from the center.
    expect(path.contains(const Offset(101, h + 0.2)), isFalse);
    // The straight side runs from (7.5, 6) to (2, 12) off the center.
    expect(path.contains(const Offset(115.5, h + 9)), isTrue);
    expect(path.contains(const Offset(115, h + 9)), isFalse);
  });

  test('the corners are continuous and give way to the arrow', () {
    // A continuous corner of 34 passes 9.91 from both edges at its middle.
    final centered = _down(240, h, 120).path;
    expect(centered.contains(const Offset(9.5, 9.5)), isFalse);
    expect(centered.contains(const Offset(10.3, 10.3)), isTrue);
    expect(centered.contains(const Offset(9.5, h - 9.5)), isFalse);
    // An arrow 60 from the side ends the corner 44 along the edge: a
    // continuous corner of 28.78, 8.39 from the edges at its middle.
    final slid = _down(240, h, 60).path;
    expect(slid.contains(const Offset(8.1, h - 8.1)), isFalse);
    expect(slid.contains(const Offset(8.8, h - 8.8)), isTrue);
    expect(slid.contains(const Offset(9.5, 9.5)), isFalse);
    // A popover of one action, 80 tall: the corners shrink to fit the box
    // with its arrow (93 tall), radius 30.42.
    final small = _down(240, 80, 120).path;
    expect(small.contains(const Offset(8.6, 8.6)), isFalse);
    expect(small.contains(const Offset(9.2, 9.2)), isTrue);
  });

  test('every direction draws the same arrow turned onto its edge', () {
    const content = Rect.fromLTWH(20, 30, 240, h);
    for (final (direction, tip, inside) in const [
      (
        PopoverArrowDirection.down,
        Offset(140, 30 + h + 13),
        Offset(0, -1),
      ),
      (PopoverArrowDirection.up, Offset(140, 30 - 13.0), Offset(0, 1)),
      (PopoverArrowDirection.left, Offset(20 - 13.0, 150), Offset(1, 0)),
      (
        PopoverArrowDirection.right,
        Offset(20 + 240 + 13, 150),
        Offset(-1, 0),
      ),
    ]) {
      final vertical =
          direction == PopoverArrowDirection.down ||
          direction == PopoverArrowDirection.up;
      final shape = PopoverShape(
        content: content,
        direction: direction,
        arrowCenter: vertical ? 140 : 150,
        cornerRadius: 34,
      );
      expect(
        shape.path.contains(tip + inside * 0.5),
        isTrue,
        reason: '$direction',
      );
      expect(
        shape.path.contains(tip + inside * 0.1),
        isFalse,
        reason: '$direction',
      );
      expect(
        shape.bounds,
        content.expandToInclude(
          Rect.fromCenter(center: tip, width: 0, height: 0),
        ),
        reason: '$direction',
      );
    }
  });

  test('the distance field traces the path', () {
    for (final shape in [
      _down(240, h, 120),
      _down(240, h, 48),
      _down(240, 80, 120),
      PopoverShape(
        content: const Rect.fromLTWH(13, 0, 240, h),
        direction: PopoverArrowDirection.left,
        arrowCenter: 132.17,
        cornerRadius: 34,
      ),
    ]) {
      final field = shape.outline.field!;
      var worst = 0.0;
      for (final metric in shape.path.computeMetrics()) {
        for (var d = 0.0; d < metric.length; d += 0.25) {
          final p = metric.getTangentForOffset(d)!.position;
          final value = _sample(field, p).abs();
          if (value > worst) worst = value;
        }
      }
      // The bilinear field rounds the arrow's tip 0.2 short.
      expect(worst, lessThan(0.25));
      expect(
        _sample(field, shape.content.center),
        closeTo(-shape.content.shortestSide / 2, 1),
      );
    }
  });
}

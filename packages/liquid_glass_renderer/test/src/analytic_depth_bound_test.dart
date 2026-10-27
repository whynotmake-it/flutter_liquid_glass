import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

/// The vertices of the octagon analytic_geometry.glsl's shapeDepthBound
/// measures depth in: [cut] cut off every corner of a box of [size], every
/// edge moved [margin] inward.
List<Offset> _octagon(Size size, Offset cut, double margin) {
  final hx = size.width / 2;
  final hy = size.height / 2;
  return [
    for (final (sx, sy) in const [
      (1.0, 1.0),
      (-1.0, 1.0),
      (1.0, -1.0),
      (-1.0, -1.0),
    ])
      for (final corner in [
        Offset(
          hx - cut.dx - margin * (cut.distance - cut.dx) / cut.dy,
          hy - margin,
        ),
        Offset(
          hx - margin,
          hy - cut.dy - margin * (cut.distance - cut.dy) / cut.dx,
        ),
      ])
        Offset(sx * corner.dx, sy * corner.dy),
  ];
}

void main() {
  const widths = [10.0, 20.0, 32.0, 44.0, 90.0, 126.0, 240.0, 600.0, 975.0];
  const heights = [10.0, 20.0, 32.0, 36.0, 63.0, 126.0, 180.0, 400.0, 1298.0];

  test('a rounded superellipse holds the octagon its depth bound uses, up '
      'to a capsule', () {
    for (final width in widths) {
      for (final height in heights) {
        final half = min(width, height) / 2;
        for (final radius in [
          0.5,
          4.0,
          16.0,
          40.0,
          83.0,
          half * 0.45,
          half * 0.9,
          half,
        ]) {
          if (radius > half) continue;
          final size = Size(width, height);
          final shape = RSuperellipse.fromRectAndRadius(
            Offset(-width / 2, -height / 2) & size,
            Radius.circular(radius),
          );
          final cut = Offset(
            min(2 * radius, width / 2),
            min(2 * radius, height / 2),
          );
          for (final vertex in _octagon(size, cut, 0.01 * radius)) {
            expect(
              shape.contains(vertex),
              isTrue,
              reason: '$size, radius $radius: $vertex',
            );
          }
        }
      }
    }
  });

  test('a pair whose radii fit holds the octagon its depth bound uses', () {
    for (final width in widths) {
      for (final height in heights) {
        for (final (top, bottom) in [(12.0, 40.0), (40.0, 12.0), (4.0, 30.0)]) {
          final extent = max(top, bottom) * 2;
          if (extent > min(width, height) / 2) continue;
          final size = Size(width, height);
          final shape = RSuperellipse.fromRectAndCorners(
            Offset(-width / 2, -height / 2) & size,
            topLeft: Radius.circular(top),
            topRight: Radius.circular(top),
            bottomLeft: Radius.circular(bottom),
            bottomRight: Radius.circular(bottom),
          );
          final margin = 0.01 * max(top, bottom);
          for (final vertex in _octagon(size, Offset(extent, extent), margin)) {
            expect(
              shape.contains(vertex),
              isTrue,
              reason: '$size, radii $top/$bottom: $vertex',
            );
          }
        }
      }
    }
  });
}

import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/rendering/rounded_superellipse_parameters.dart';

/// Points along the outline of the rounded rectangle of half size ([hx],
/// [hy]) with corners of [radius], each moved [push] along the outline's
/// normal.
Iterable<Offset> _roundedBox(
  double hx,
  double hy,
  double radius, {
  double push = 0,
}) sync* {
  const steps = 48;
  for (final (sx, sy) in const [
    (1.0, 1.0),
    (-1.0, 1.0),
    (1.0, -1.0),
    (-1.0, -1.0),
  ]) {
    for (var k = 0; k <= steps; k++) {
      final angle = k / steps * pi / 2;
      yield Offset(
        sx * (hx - radius + (radius + push) * cos(angle)),
        sy * (hy - radius + (radius + push) * sin(angle)),
      );
    }
    for (var k = 0; k <= steps; k++) {
      final t = k / steps;
      yield Offset(sx * (hx - radius) * t, sy * (hy + push));
      yield Offset(sx * (hx + push), sy * (hy - radius) * t);
    }
  }
}

void main() {
  // The rounded rectangles the geometry tiler bounds a box shape between
  // (geometry_tiling.dart): the one of its box and [least] radius around
  // it, within a 500th of that radius, and inside it the one inset by a
  // fiftieth of its [greatest] radius and a hundredth of a pixel, with
  // corners of that radius, unless that radius is longer than the box's
  // shorter half.
  void expectBetween(
    RSuperellipse shape,
    Size size, {
    required double least,
    required double greatest,
    required String reason,
  }) {
    final hx = size.width / 2;
    final hy = size.height / 2;
    final shorter = min(hx, hy);
    final around = min(least, shorter);
    for (final point in _roundedBox(
      hx,
      hy,
      around,
      push: 0.002 * around + 1e-3,
    )) {
      expect(shape.contains(point), isFalse, reason: '$reason: $point');
    }
    if (greatest > shorter) return;
    final corner = min(greatest, shorter);
    final inset = min(0.02 * corner + 0.01, shorter / 2);
    for (final point in _roundedBox(
      hx - inset,
      hy - inset,
      min(corner, shorter - inset),
    )) {
      expect(shape.contains(point), isTrue, reason: '$reason: $point');
    }
  }

  test('a rounded superellipse lies between the rounded rectangles its '
      'bounds use, up to a capsule', () {
    for (final half in [5.0, 22.0, 63.0, 200.0]) {
      for (var aspect = 1.0; aspect <= 12; aspect *= 1.09) {
        for (var k = 1; k <= 20; k++) {
          final radius = half * k / 20;
          for (final size in [
            Size(2 * half, 2 * half * aspect),
            Size(2 * half * aspect, 2 * half),
          ]) {
            expectBetween(
              RSuperellipse.fromRectAndRadius(
                Offset(-size.width / 2, -size.height / 2) & size,
                Radius.circular(radius),
              ),
              size,
              least: radius,
              greatest: radius,
              reason: '$size, radius $radius',
            );
          }
        }
      }
    }
  });

  test('a pair whose greater radius fits its box holds the rounded '
      'rectangle its bounds use', () {
    const widths = [10.0, 20.0, 32.0, 44.0, 90.0, 126.0, 240.0, 600.0, 975.0];
    const heights = [10.0, 20.0, 32.0, 36.0, 63.0, 126.0, 180.0, 400.0, 1298.0];
    for (final width in widths) {
      for (final height in heights) {
        for (final (top, bottom) in [
          (12.0, 40.0),
          (40.0, 12.0),
          (4.0, 30.0),
          (0.0, 16.0),
          (60.0, 60.0),
          (300.0, 20.0),
        ]) {
          final size = Size(width, height);
          // Radii that do not fit are scaled down together; a shape's row
          // holds the top one as it was asked for and the bottom one fitted.
          final fit = roundedSuperellipsePairFit(size, top, bottom);
          expectBetween(
            RSuperellipse.fromRectAndCorners(
              Offset(-width / 2, -height / 2) & size,
              topLeft: Radius.circular(top * fit),
              topRight: Radius.circular(top * fit),
              bottomLeft: Radius.circular(bottom * fit),
              bottomRight: Radius.circular(bottom * fit),
            ),
            size,
            least: 0,
            greatest: max(top, bottom * fit),
            reason: '$size, radii $top/$bottom',
          );
        }
      }
    }
  });
}

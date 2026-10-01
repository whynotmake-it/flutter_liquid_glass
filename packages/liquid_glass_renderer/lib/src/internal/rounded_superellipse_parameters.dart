// The lookup table and construction are adapted from Flutter's
// impeller/geometry/round_superellipse_param.cc (Flutter 3.47.1):
//   Copyright 2013 The Flutter Authors. All rights reserved.
//   Use of this source code is governed by a BSD-style license that can be
//   found in third_party/flutter/LICENSE.

import 'dart:math';
import 'dart:ui';

import 'package:meta/meta.dart';

(double, double) _rseNAndXj(double ratio) {
  const table = <(double, double)>[
    (2.00000000, 1.13276676),
    (2.18349805, 1.20311921),
    (2.33888662, 1.28698796),
    (2.48660575, 1.36351941),
    (2.62226596, 1.44717976),
    (2.75148990, 1.53385819),
    (3.36298265, 1.98288283),
    (4.08649929, 2.23811846),
    (4.85481134, 2.47563463),
    (5.62945551, 2.72948597),
    (6.43023796, 2.98020421),
  ];
  if (ratio > 5.0) {
    final n = 1.559599389 * (ratio - 5.0) + table.last.$1;
    final kXj = 0.522807185 * (ratio - 5.0) + table.last.$2;
    return (n, 1.0 - 1.0 / kXj);
  }
  final clampedRatio = ratio.clamp(2.0, 5.0);
  final steps = clampedRatio < 2.5
      ? (clampedRatio - 2.0) * 10.0
      : (clampedRatio - 2.5) * 2.0 + 5.0;
  final left = steps.floor().clamp(0, table.length - 2);
  final fraction = steps - left;
  final a = table[left];
  final b = table[left + 1];
  final n = a.$1 + (b.$1 - a.$1) * fraction;
  final kXj = a.$2 + (b.$2 - a.$2) * fraction;
  return (n, 1.0 - 1.0 / kXj);
}

(double, double, Offset, double) _rseOctant(
  double axis,
  double radius,
) {
  if (radius <= 1e-3) return (0.0, 0.0, Offset.zero, 0.0);
  final (n, xJOverA) = _rseNAndXj(2.0 * axis / radius);
  final xJ = xJOverA * axis;
  final yJ =
      pow(
        max(1.0 - pow(xJOverA, n).toDouble(), 0.0),
        1.0 / n,
      ).toDouble() *
      axis;
  final tanPhi = pow(xJ / max(yJ, 1e-6), n - 1.0).toDouble();
  final d = (xJ - tanPhi * yJ) / (1.0 - tanPhi);
  final gap = (1.0 - cos(pi / 4.0)) * radius;
  final circleRadius = (axis - d - gap) * sqrt2;
  final pointJ = Offset(xJ, yJ);
  final pointM = Offset(axis - gap, axis - gap);
  final chord = pointM - pointJ;
  final midpoint = (pointJ + pointM) / 2.0;
  final perpendicular = Offset(-chord.dy, chord.dx);
  final perpendicularLength = perpendicular.distance;
  final halfChord = chord.distance / 2.0;
  final centerDistance = sqrt(
    max(circleRadius * circleRadius - halfChord * halfChord, 0.0),
  );
  final circleCenter = perpendicularLength <= 1e-6
      ? midpoint
      : midpoint - perpendicular * (centerDistance / perpendicularLength);
  final fromM = pointM - circleCenter;
  final fromJ = pointJ - circleCenter;
  final span = atan2(
    fromM.dx * fromJ.dy - fromM.dy * fromJ.dx,
    fromM.dx * fromJ.dx + fromM.dy * fromJ.dy,
  ).abs();
  return (n, span, circleCenter, circleRadius);
}

/// Parameters of Flutter 3.47's rounded superellipse for its symmetric SDF
/// (`sdfSquircle`), three vec4s: octant degrees and arc spans, circle
/// centers, then semi-axes and circle radii. Flutter computes them when the
/// geometry changes; mirroring that construction keeps lookup-table
/// interpolation and circle fitting out of the fragment shader. Lengths are
/// [size] units times [scale].
@internal
List<double> roundedSuperellipseParameters(
  Size size,
  double cornerRadius, {
  double scale = 1,
}) {
  final halfWidth = size.width * scale / 2.0;
  final halfHeight = size.height * scale / 2.0;
  final radius = min(
    cornerRadius * scale,
    min(halfWidth, halfHeight),
  );
  final (topN, topSpan, topCenter, topRadius) = _rseOctant(
    halfWidth,
    radius,
  );
  final (rightN, rightSpan, rightCenter, rightRadius) = _rseOctant(
    halfHeight,
    radius,
  );
  return <double>[
    topN,
    rightN,
    topSpan,
    rightSpan,
    topCenter.dx,
    topCenter.dy,
    rightCenter.dx,
    rightCenter.dy,
    halfWidth,
    halfHeight,
    topRadius,
    rightRadius,
  ];
}

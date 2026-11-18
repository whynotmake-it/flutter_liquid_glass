// The lookup table and construction are adapted from Flutter's
// impeller/geometry/round_superellipse_param.cc (Flutter 3.47.1):
//   Copyright 2013 The Flutter Authors. All rights reserved.
//   Use of this source code is governed by a BSD-style license that can be
//   found in third_party/flutter/LICENSE.

import 'dart:math';
import 'dart:ui';

import 'package:liquid_glass_renderer/src/painting/shader_constants.dart';
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

SquircleOctant _rseOctant(double axis, double radius) {
  if (radius <= 1e-3) {
    return SquircleOctant(
      axis: axis,
      degree: 0,
      span: 0,
      circleCenter: Offset.zero,
      circleRadius: 0,
    );
  }
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
  return SquircleOctant(
    axis: axis,
    degree: n,
    span: span,
    circleCenter: circleCenter,
    circleRadius: circleRadius,
  );
}

@internal
SquircleParameters roundedSuperellipseParameters(
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
  return SquircleParameters(
    top: _rseOctant(halfWidth, radius),
    right: _rseOctant(halfHeight, radius),
  );
}

/// [roundedSuperellipseParameters] of the top and bottom halves of Flutter
/// 3.47's rounded superellipse of [size] whose two top corners have radius
/// [top] and two bottom corners [bottom]. Impeller's `MakeBoundsRadii` splits
/// the sides where the radii divide them in their own ratio; each half is a
/// symmetric rounded superellipse centered on that split line, and the shape
/// is the top one above the line and the bottom one below it, as Impeller's
/// quadrants are. Radii that do not fit are scaled down together
/// ([RSuperellipse.scaleRadii]), as Impeller does. Lengths are [size] units
/// times [scale].
@internal
SquirclePairParameters roundedSuperellipsePairParameters(
  Size size,
  double top,
  double bottom, {
  double scale = 1,
}) {
  final fitted = RSuperellipse.fromRectAndCorners(
    Offset.zero & size,
    topLeft: Radius.circular(top),
    topRight: Radius.circular(top),
    bottomLeft: Radius.circular(bottom),
    bottomRight: Radius.circular(bottom),
  ).scaleRadii();
  final upper = top + bottom <= 0
      ? size.height / 2
      : size.height * top / (top + bottom);
  final lower = size.height - upper;
  return SquirclePairParameters(
    top: roundedSuperellipseParameters(
      Size(size.width, 2 * upper),
      fitted.tlRadiusX,
      scale: scale,
    ),
    bottom: roundedSuperellipseParameters(
      Size(size.width, 2 * lower),
      fitted.blRadiusX,
      scale: scale,
    ),
    topRadius: fitted.tlRadiusX * scale,
    bottomRadius: fitted.blRadiusX * scale,
  );
}

/// One of the two octants of a quadrant of Flutter 3.47's rounded
/// superellipse: the one at the top side, whose semi-[axis] is half the width,
/// or the one at the right side, whose semi-axis is half the height. Between
/// the side and the circular cap of [circleRadius] around [circleCenter], which
/// spans [span] radians, it is a superellipse of [degree].
@internal
@immutable
class SquircleOctant {
  const SquircleOctant({
    required this.axis,
    required this.degree,
    required this.span,
    required this.circleCenter,
    required this.circleRadius,
  });

  final double axis;
  final double degree;
  final double span;
  final Offset circleCenter;
  final double circleRadius;
}

@internal
@immutable
class SquircleParameters {
  const SquircleParameters({required this.top, required this.right});

  final SquircleOctant top;
  final SquircleOctant right;

  /// The row `sdfSquircle` reads.
  List<double> get floats => _floats(top.axis);

  List<double> _floats(double topAxis) => laneRow(SquircleLane.values, {
    SquircleLane.topDegree: top.degree,
    SquircleLane.rightDegree: right.degree,
    SquircleLane.topSpan: 1.0 - cos(top.span),
    SquircleLane.rightSpan: 1.0 - cos(right.span),
    SquircleLane.topCenterX: top.circleCenter.dx,
    SquircleLane.topCenterY: top.circleCenter.dy,
    SquircleLane.rightCenterX: right.circleCenter.dx,
    SquircleLane.rightCenterY: right.circleCenter.dy,
    SquircleLane.topAxis: topAxis,
    SquircleLane.rightAxis: right.axis,
    SquircleLane.topRadius: top.circleRadius,
    SquircleLane.rightRadius: right.circleRadius,
  });
}

@internal
@immutable
class SquirclePairParameters {
  const SquirclePairParameters({
    required this.top,
    required this.bottom,
    required this.topRadius,
    required this.bottomRadius,
  });

  final SquircleParameters top;
  final SquircleParameters bottom;

  /// The radius of the two top corners, fitted and scaled.
  final double topRadius;

  /// The radius of the two bottom corners, fitted and scaled.
  final double bottomRadius;

  /// [bottom]'s floats as the geometry shaders read them: [bottomRadius] in
  /// place of the semi-axis of its top octant, which is [top]'s
  /// (`pairBottomRadius` in sdf.glsl).
  List<double> get geometryBottomFloats => bottom._floats(bottomRadius);
}

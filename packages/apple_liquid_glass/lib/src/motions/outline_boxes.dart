import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:liquid_glass_renderer/painting.dart';

/// Rounded boxes laid out for inner loops: per box its center, half
/// extents and corner radius, clamped to half its thickness.
///
/// The menu's fused outline, the plain union of rounded boxes and the
/// popover's field measure distances and optical corners through it.
@internal
class OutlineBoxes {
  /// Lays out [shapes], whose corners must share one circular radius.
  OutlineBoxes(List<RRect> shapes)
    : length = shapes.length,
      _data = Float64List(shapes.length * 5) {
    for (var i = 0; i < shapes.length; i++) {
      final shape = shapes[i];
      assertUniformCorners(shape);
      final hx = shape.width / 2;
      final hy = shape.height / 2;
      _data[i * 5] = shape.center.dx;
      _data[i * 5 + 1] = shape.center.dy;
      _data[i * 5 + 2] = hx;
      _data[i * 5 + 3] = hy;
      _data[i * 5 + 4] = math.min(shape.tlRadiusX, math.min(hx, hy));
    }
  }

  /// The number of boxes.
  final int length;

  final Float64List _data;

  /// The x of box [i]'s center.
  double centerX(int i) => _data[i * 5];

  /// The y of box [i]'s center.
  double centerY(int i) => _data[i * 5 + 1];

  /// Half the width of box [i].
  double halfX(int i) => _data[i * 5 + 2];

  /// Half the height of box [i].
  double halfY(int i) => _data[i * 5 + 3];

  /// The corner radius of box [i], at most [halfMinor].
  double radius(int i) => _data[i * 5 + 4];

  /// The half thickness of box [i].
  double halfMinor(int i) => math.min(_data[i * 5 + 2], _data[i * 5 + 3]);

  /// The corner radius box [i]'s optical normals turn on: [radius] times
  /// [LiquidGlassField.opticalCornerScale], at most [halfMinor].
  double opticalRadius(int i) => math.min(
    _data[i * 5 + 4] * LiquidGlassField.opticalCornerScale,
    halfMinor(i),
  );

  /// Whether box [i]'s optical normals ever differ from its exact ones:
  /// false for a capsule or a circle, whose corners are already as round
  /// as its thickness allows.
  bool turns(int i) => _data[i * 5 + 4] > 0 && _data[i * 5 + 4] < halfMinor(i);

  /// The signed distance from (x, y) to box [i].
  double distance(int i, double x, double y) {
    final r = _data[i * 5 + 4];
    final qx = (x - _data[i * 5]).abs() - _data[i * 5 + 2] + r;
    final qy = (y - _data[i * 5 + 1]).abs() - _data[i * 5 + 3] + r;
    return boxDistance(qx, qy, r);
  }

  /// Whether (x, y) lies where box [i]'s optical normals can differ from
  /// its exact ones: in the square of a corner of the optical radius.
  bool inOpticalCorner(int i, double x, double y) =>
      inOpticalCornerColumns(i, x) && inOpticalCornerRows(i, y);

  /// Whether [x] lies in the columns of box [i]'s optical corners: the
  /// horizontal half of [inOpticalCorner].
  bool inOpticalCornerColumns(int i, double x) =>
      (x - _data[i * 5]).abs() > _data[i * 5 + 2] - opticalRadius(i);

  /// Whether [y] lies in the rows of box [i]'s optical corners: the
  /// vertical half of [inOpticalCorner].
  bool inOpticalCornerRows(int i, double y) =>
      (y - _data[i * 5 + 1]).abs() > _data[i * 5 + 3] - opticalRadius(i);

  /// The rotation from box [i]'s exact normal at (x, y) to its optical
  /// normal, the one a corner [LiquidGlassField.opticalCornerScale] times
  /// rounder gives, as (cos, sin) written into [out] at [at].
  void opticalTurn(int i, double x, double y, Float64List out, int at) {
    final exact = _data[i * 5 + 4];
    final optical = opticalRadius(i);
    final px = x - _data[i * 5];
    final py = y - _data[i * 5 + 1];
    final ax = px.abs() - _data[i * 5 + 2];
    final ay = py.abs() - _data[i * 5 + 3];
    writeOpticalTurn(
      exact: exact,
      optical: optical,
      ox: ax + optical,
      oy: ay + optical,
      ex: ax + exact,
      ey: ay + exact,
      mirrored: (px < 0) != (py < 0),
      out: out,
      at: at,
    );
  }
}

/// Writes into [out] at [at], as (cos, sin), the rotation from a rounded
/// box's exact normal at a point to its optical one.
///
/// [ex], [ey] are the point's offsets past the inner corner of the exact
/// radius [exact] along each axis, [ox], [oy] past that of the [optical]
/// radius, both measured in the box's quadrant; [mirrored] is true in the
/// two quadrants whose axes turn the other way. Outside the optical
/// corner, or where the optical radius is no rounder, the turn is none.
@internal
@pragma('vm:prefer-inline')
void writeOpticalTurn({
  required double exact,
  required double optical,
  required double ox,
  required double oy,
  required double ex,
  required double ey,
  required bool mirrored,
  required Float64List out,
  required int at,
}) {
  out[at] = 1;
  out[at + 1] = 0;
  if (optical <= exact || ox <= 0 || oy <= 0) return;
  double enx;
  double eny;
  if (ex > 0 && ey > 0) {
    final length = math.sqrt(ex * ex + ey * ey);
    enx = ex / length;
    eny = ey / length;
  } else if (ex > ey) {
    enx = 1;
    eny = 0;
  } else {
    enx = 0;
    eny = 1;
  }
  final length = math.sqrt(ox * ox + oy * oy);
  final onx = ox / length;
  final ony = oy / length;
  out[at] = enx * onx + eny * ony;
  out[at + 1] = (enx * ony - eny * onx) * (mirrored ? -1 : 1);
}

/// Normalizes the (cos, sin) pair at [at], blended from several turns.
@internal
void normalizeTurn(Float64List turn, int at) {
  final c = turn[at];
  final s = turn[at + 1];
  final length = math.sqrt(c * c + s * s);
  if (length < 1e-9) {
    turn[at] = 1;
    turn[at + 1] = 0;
  } else {
    turn[at] = c / length;
    turn[at + 1] = s / length;
  }
}

/// The signed distance of a rounded box from its corner-relative offsets
/// [qx], [qy] (the distance past the box's inner rectangle along each
/// axis) and its corner radius [r].
@internal
double boxDistance(double qx, double qy, double r) {
  double outside;
  if (qx > 0) {
    outside = qy > 0 ? math.sqrt(qx * qx + qy * qy) : qx;
  } else {
    outside = qy > 0 ? qy : 0;
  }
  final inner = qx > qy ? qx : qy;
  return outside + (inner < 0 ? inner : 0.0) - r;
}

/// Whether rounded box [outer] covers rounded box [inner]: every corner
/// circle of [inner] lies inside it, and with them, [outer] being convex,
/// all of [inner].
@internal
bool encloses(RRect outer, RRect inner) {
  final boxes = OutlineBoxes([outer, inner]);
  final r = boxes.radius(1);
  final hx = boxes.halfX(1) - r;
  final hy = boxes.halfY(1) - r;
  for (final (sx, sy) in const [
    (-1.0, -1.0),
    (1.0, -1.0),
    (-1.0, 1.0),
    (1.0, 1.0),
  ]) {
    final x = boxes.centerX(1) + sx * hx;
    final y = boxes.centerY(1) + sy * hy;
    if (boxes.distance(0, x, y) > -r) return false;
  }
  return true;
}

/// Asserts that [shape]'s four corners share one circular radius, which
/// the distance fields of glass bodies require.
@internal
void assertUniformCorners(RRect shape) {
  assert(
    shape.tlRadiusX == shape.tlRadiusY &&
        shape.tlRadius == shape.trRadius &&
        shape.tlRadius == shape.blRadius &&
        shape.tlRadius == shape.brRadius,
    'Glass distance fields require uniform circular corner radii.',
  );
}

part of 'geometry_tiling.dart';

/// Closed-form bounds of one encoded shape's distance over the tiles of a
/// buffer, in the units the geometry pass writes (local distance times the
/// shape's distance scale). A tile's preimage is a parallelogram, the same
/// size for every tile, grown by the apron of the tile's strip.
///
/// A box shape lies between two rounded rectangles: it holds one inset by a
/// fiftieth of its radius, and the rounded rectangle of its box and radius
/// holds it within a 500th of the radius; a pair holds the one of its
/// greater radius, where that fits its box, and lies in its box
/// (shape_bounds_test). A rounded rectangle's distance is convex and grows
/// with |x| and with |y|, so it is least over a box at the box's point
/// nearest the axes and greatest over a parallelogram at a corner.
final class _ShapeBounds {
  _ShapeBounds._({
    required this.type,
    required this.halfWidth,
    required this.halfHeight,
    required this.outerRadius,
    required this.outset,
    required this.inset,
    required this.innerRadius,
    required this.foldInset,
    required this.a,
    required this.b,
    required this.c,
    required this.d,
    required this.centerX,
    required this.centerY,
    required this.scale,
    required this.blend,
    required this.foldMargin,
    required this.apron,
    required this.cell,
    required double slack,
  }) : _half = cell / 2 + apron,
       _extentX = (a.abs() + b.abs()) * (cell / 2 + apron),
       _extentY = (c.abs() + d.abs()) * (cell / 2 + apron),
       _ellipse = type == RawShapeType.ellipse.shaderIndex,
       // A shape that moves by some distance changes its own distance by
       // no more anywhere.
       _slack =
           slack +
           (type == RawShapeType.roundedRectangle.shaderIndex
               ? 0
               : _solveSlack);

  /// Shape [i] of [shapes] over tiles of [cell] buffer pixels a side;
  /// [foldsOverTile] looks [foldMargin] pixels around a tile, and every
  /// bound [apron] pixels around it, for the shape anywhere within [slack]
  /// pixels of where it is.
  factory _ShapeBounds.of(
    ShapeSet shapes,
    int i, {
    int cell = Tiling.size,
    double foldMargin = 0,
    double apron = 0.5,
    double slack = 0,
  }) {
    final row = shapes.shapes;
    final o = i * 12;
    final type = row[o];
    final halfWidth = row[o + 1] / 2;
    final halfHeight = row[o + 2] / 2;
    final shorter = min(halfWidth, halfHeight);
    var radius = row[o + 3];
    var least = radius;
    // A pair's corner can be as tall as its box, which no rounded rectangle
    // inside it follows.
    var hollow = false;
    if (type == RawShapeType.squirclePair.shaderIndex) {
      // The row holds the top radius as it was asked for, which a pair that
      // does not fit scales down: only the pair's box is known to hold it.
      least = 0;
      radius = max(radius, shapes.superellipsesLower[i * 12 + 8]);
      hollow = radius > shorter;
    }
    final corner = min(radius, shorter);
    var foldInset = corner;
    if (type == RawShapeType.squircle.shaderIndex) {
      // The corner's two octants are arcs of circles centered on the
      // diagonal that touch at the corner's 45-degree point, a gap in from
      // the box: they fold the distance deeper than the nearer center.
      final cap = min(
        shapes.superellipses[i * 12 + 10],
        shapes.superellipses[i * 12 + 11],
      );
      foldInset = cap > 0
          ? min(corner, (1 - sqrt1_2) * corner + cap * sqrt1_2)
          : double.negativeInfinity;
    }
    final exact = type == RawShapeType.roundedRectangle.shaderIndex;
    final inset = exact ? 0.0 : min(0.02 * corner + 0.01, shorter / 2);
    final around = min(least, shorter);
    return _ShapeBounds._(
      type: type,
      halfWidth: halfWidth,
      halfHeight: halfHeight,
      outerRadius: around,
      outset: exact ? 0.0 : 0.002 * around,
      inset: inset,
      innerRadius: hollow ? double.infinity : min(corner, shorter - inset),
      foldInset: foldInset,
      a: row[o + 4],
      b: row[o + 5],
      c: row[o + 6],
      d: row[o + 7],
      centerX: row[o + 8],
      centerY: row[o + 9],
      scale: row[o + 10],
      blend: max(0, row[o + 11]),
      foldMargin: foldMargin,
      apron: apron,
      cell: cell,
      slack: slack,
    );
  }

  final double type;
  final double halfWidth;
  final double halfHeight;

  // The rounded rectangle around a box shape: of its box, with corners of
  // [outerRadius], which the shape passes by at most [outset].
  final double outerRadius;
  final double outset;

  // The rounded rectangle inside a box shape: its box [inset] from the
  // shape's, with corners of [innerRadius], infinite where the shape is
  // known to hold none.
  final double inset;
  final double innerRadius;

  // Where a box shape's corner diagonal stops folding, in from the box's
  // corner along both axes: the center of the arc of a rounded rectangle
  // (the optical normal's wider arc lies deeper), the nearer center of a
  // continuous corner's arcs; a box with sharp corners folds out past it.
  final double foldInset;

  // The inverse basis: local = (a x + b y, c x + d y) from the center.
  final double a;
  final double b;
  final double c;
  final double d;
  final double centerX;
  final double centerY;
  final double scale;

  // The radius of the shape's smooth union with those before it in its
  // group; 0 for the first.
  final double blend;
  final double foldMargin;
  final double apron;
  final int cell;

  // What the geometry pass's continuous corners, a bisection and a chord,
  // can lie off the shape dart:ui draws.
  static const double _solveSlack = 0.25;

  final double _half;
  final double _extentX;
  final double _extentY;
  late final double _foldExtentX =
      (a.abs() + b.abs()) * (cell / 2 + foldMargin);
  late final double _foldExtentY =
      (c.abs() + d.abs()) * (cell / 2 + foldMargin);
  final bool _ellipse;
  final double _slack;

  /// The tiles [lowerOverTile] can bound below [reach]: the shape's box
  /// grown by the reach in its own units, mapped into the buffer. The
  /// geometry pass measures distance in the shape's units times [scale], the
  /// basis's least stretch, so a box in buffer pixels grown by [reach] can
  /// miss pixels beside a stretched shape.
  (int, int, int, int) tileSpan(double reach, int columns, int rows) {
    final determinant = a * d - b * c;
    final room = (reach + 2 * apron + _slack) / scale;
    final grownX = halfWidth + room;
    final grownY = halfHeight + room;
    final extentX = (d.abs() * grownX + b.abs() * grownY) / determinant.abs();
    final extentY = (c.abs() * grownX + a.abs() * grownY) / determinant.abs();
    int tile(double at, int tiles) => (at / cell).floor().clamp(0, tiles - 1);
    return (
      tile(centerX - extentX, columns),
      tile(centerY - extentY, rows),
      tile(centerX + extentX, columns),
      tile(centerY + extentY, rows),
    );
  }

  double _localX(int column, int row) =>
      a * ((column + 0.5) * cell - centerX) +
      b * ((row + 0.5) * cell - centerY);

  double _localY(int column, int row) =>
      c * ((column + 0.5) * cell - centerX) +
      d * ((row + 0.5) * cell - centerY);

  // A box shape whose axes are the buffer's bounds a tile from its column
  // and its row alone: per column the |x| of the preimage's point nearest
  // the center, then of its farthest, and per row the same of |y|.
  bool _separable = false;
  Float64List _columnsX = _none;
  Float64List _rowsY = _none;
  static final Float64List _none = Float64List(0);

  /// Readies the bounds for a buffer of [columns] x [rows] tiles.
  void prepare(int columns, int rows) {
    if (_ellipse || b != 0 || c != 0) return;
    Float64List table(int count, double inverse, double center, double extent) {
      final table = Float64List(count * 2);
      for (var i = 0; i < count; i++) {
        final at = (inverse * ((i + 0.5) * cell - center)).abs();
        table[i * 2] = _positive(at - extent);
        table[i * 2 + 1] = at + extent;
      }
      return table;
    }

    _separable = true;
    _columnsX = table(columns, a, centerX, _extentX);
    _rowsY = table(rows, d, centerY, _extentY);
  }

  /// A lower bound of the distance (negative inside) over tile [column],
  /// [row]: the least distance of the shape around this one over the box
  /// around the tile's preimage.
  double lowerOverTile(int column, int row) {
    // The shapes are convex and mirror-symmetric in both local axes, so
    // their distance grows with |x| and with |y|: the box's point nearest
    // the axes is its nearest point.
    final double qx;
    final double qy;
    if (_separable) {
      qx = _columnsX[column * 2];
      qy = _rowsY[row * 2];
    } else {
      qx = _positive(_localX(column, row).abs() - _extentX);
      qy = _positive(_localY(column, row).abs() - _extentY);
    }
    if (!_ellipse) {
      // The geometry pass measures a sharp box by its farther side.
      if (outerRadius <= 1e-4) {
        return max(qx - halfWidth, qy - halfHeight) * scale - _slack;
      }
      return (_roundedBox(qx, qy, halfWidth, halfHeight, outerRadius) -
                  outset) *
              scale -
          _slack;
    }
    if (halfWidth <= 0 || halfHeight <= 0) {
      final gx = _positive(qx - halfWidth);
      final gy = _positive(qy - halfHeight);
      return sqrt(gx * gx + gy * gy) * scale - _slack;
    }
    final a2 = halfWidth * halfWidth;
    final b2 = halfHeight * halfHeight;
    final nx = qx / a2;
    final ny = qy / b2;
    if (nx * qx + ny * qy <= 1) return double.negativeInfinity;
    // Any support line bounds the distance to a convex shape from below;
    // the one whose normal is the ellipse's at q's radial projection is
    // close to the nearest.
    final length = sqrt(nx * nx + ny * ny);
    final ux = nx / length;
    final uy = ny / length;
    final support = ux * qx + uy * qy - sqrt(a2 * ux * ux + b2 * uy * uy);
    final gx = _positive(qx - halfWidth);
    final gy = _positive(qy - halfHeight);
    return max(sqrt(gx * gx + gy * gy), support) * scale - _slack;
  }

  /// An upper bound of the distance over tile [column], [row]: the greatest
  /// distance of the shape inside this one over the tile's preimage, which
  /// a convex distance takes at a corner.
  double upperOverTile(int column, int row) {
    if (innerRadius == double.infinity) return double.infinity;
    if (_separable) {
      return _roundedBox(
                _columnsX[column * 2 + 1],
                _rowsY[row * 2 + 1],
                halfWidth - inset,
                halfHeight - inset,
                innerRadius,
              ) *
              scale +
          _slack;
    }
    final x = _localX(column, row);
    final y = _localY(column, row);
    final ux = (a + b) * _half;
    final uy = (c + d) * _half;
    final vx = (a - b) * _half;
    final vy = (c - d) * _half;
    if (!_ellipse) {
      final hw = halfWidth - inset;
      final hh = halfHeight - inset;
      final r = innerRadius;
      final distance = max(
        max(
          _roundedBox((x + ux).abs(), (y + uy).abs(), hw, hh, r),
          _roundedBox((x - ux).abs(), (y - uy).abs(), hw, hh, r),
        ),
        max(
          _roundedBox((x + vx).abs(), (y + vy).abs(), hw, hh, r),
          _roundedBox((x - vx).abs(), (y - vy).abs(), hw, hh, r),
        ),
      );
      return distance * scale + _slack;
    }
    if (halfWidth <= 0 || halfHeight <= 0) return double.infinity;
    // An ellipse holds its copy scaled by rho about the center (the copy
    // through the point) grown by (1 - rho) times its minor semi-axis, and
    // the circle of its minor semi-axis. Both bounds are convex.
    final minor = min(halfWidth, halfHeight);
    var rho = 0.0;
    var radius = 0.0;
    for (final (px, py) in [
      (x + ux, y + uy),
      (x - ux, y - uy),
      (x + vx, y + vy),
      (x - vx, y - vy),
    ]) {
      final rx = px / halfWidth;
      final ry = py / halfHeight;
      rho = max(rho, sqrt(rx * rx + ry * ry));
      radius = max(radius, sqrt(px * px + py * py));
    }
    return (rho <= 1 ? (rho - 1) * minor : radius - minor) * scale + _slack;
  }

  // The signed distance from (x, y), both positive, to the box of half size
  // (hw, hh) with corners of radius r.
  static double _roundedBox(
    double x,
    double y,
    double hw,
    double hh,
    double r,
  ) {
    final gx = x - hw + r;
    final gy = y - hh + r;
    if (gx <= 0 || gy <= 0) return max(gx, gy) - r;
    return sqrt(gx * gx + gy * gy) - r;
  }

  /// Whether the shape's distance or its normal can fold within
  /// [foldMargin] of tile [column], [row]: its medial axis (the center line
  /// and each corner's diagonal, where the nearest edge changes) or a
  /// corner's center of curvature can lie there. A pair's halves meet on a
  /// line of their own, so a pair folds anywhere.
  bool foldsOverTile(int column, int row) {
    if (type == RawShapeType.squirclePair.shaderIndex) return true;
    final x = _localX(column, row).abs();
    final y = _localY(column, row).abs();
    // The box folded into the first quadrant, which the medial axis of a
    // mirror-symmetric shape is in.
    var nearX = _positive(x - _foldExtentX);
    var nearY = _positive(y - _foldExtentY);
    var farX = x + _foldExtentX;
    var farY = y + _foldExtentY;
    var long = halfWidth;
    var short = halfHeight;
    if (short > long) {
      (long, short) = (short, long);
      (nearX, nearY) = (nearY, nearX);
      (farX, farY) = (farY, farX);
    }
    if (_ellipse) {
      // The medial axis runs along the major axis to the center of
      // curvature of its vertex.
      return nearY <= 0 && nearX <= long - short * short / max(long, 1e-9);
    }
    final spine = long - short;
    if (nearY <= 0 && nearX <= spine) return true;
    // Each corner's diagonal, from the spine's end to [foldInset].
    final from = max(spine, max(nearX, nearY + spine));
    final to = min(long - foldInset, min(farX, farY + spine));
    return from <= to;
  }

  static double _positive(double value) => value > 0 ? value : 0.0;
}

import 'dart:math' as math;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/src/motions/outline_boxes.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:liquid_glass_renderer/painting.dart';

/// The field samples of an outline, four per node, row-major, on `cols`
/// by `rows` nodes `step` logical pixels apart from `origin`: a
/// [LiquidGlassField]'s grid as plain data.
@internal
typedef OutlineGrid = ({
  Float32List samples,
  int cols,
  int rows,
  Offset origin,
  double step,
});

/// A fused outline before it becomes a [GlassOutline]: its edge as closed
/// loops of contour crossings and, unless the body is only filled, its
/// field samples, plain typed data that any isolate can compute and send.
///
/// [outlineFromParts] turns the loops into the edge, the
/// quadratic B-spline through the crossings.
@internal
final class OutlineParts {
  /// Creates the parts of an outline; without a [grid] for a flat fill.
  const OutlineParts({required this.points, required this.loops, this.grid});

  /// The field samples, or null for an edge alone.
  final OutlineGrid? grid;

  /// The contour crossings, (x, y) after (x, y), loop after loop.
  final Float64List points;

  /// The number of crossings of each loop, in the order of [points].
  final Int32List loops;
}

/// The parts of an outline traced from sampled fields.
@internal
@pragma('vm:unsafe:no-bounds-checks')
OutlineParts outlinePartsFromFields({
  required Float64List trace,
  required int cols,
  required int rows,
  required Uint8List near,
  required int blockCols,
  required int block,
  required Float64List distance,
  required Float64List halfMinor,
  required Float64List turn,
  required int stride,
  required double left,
  required double top,
  required double step,
}) {
  final fieldCols = (cols - 1) ~/ stride + 1;
  final fieldRows = (rows - 1) ~/ stride + 1;
  final fieldStep = step * stride;
  final samples = Float32List(fieldCols * fieldRows * 4);
  for (var j = 0; j < fieldRows; j++) {
    final up = j > 0 ? j - 1 : 0;
    final down = j < fieldRows - 1 ? j + 1 : fieldRows - 1;
    for (var i = 0; i < fieldCols; i++) {
      final back = i > 0 ? i - 1 : 0;
      final ahead = i < fieldCols - 1 ? i + 1 : fieldCols - 1;
      final at = j * fieldCols + i;
      final gx =
          (distance[j * fieldCols + ahead] - distance[j * fieldCols + back]) /
          ((ahead - back) * fieldStep);
      final gy =
          (distance[down * fieldCols + i] - distance[up * fieldCols + i]) /
          ((down - up) * fieldStep);
      final c = turn[at * 2];
      final s = turn[at * 2 + 1];
      final out = at * 4;
      samples[out] = distance[at];
      samples[out + 1] = gx * c - gy * s;
      samples[out + 2] = gx * s + gy * c;
      samples[out + 3] = halfMinor[at];
    }
  }
  final edge = outlineEdgeParts(
    trace: trace,
    cols: cols,
    rows: rows,
    near: near,
    blockCols: blockCols,
    block: block,
    left: left,
    top: top,
    step: step,
  );
  return OutlineParts(
    points: edge.points,
    loops: edge.loops,
    grid: (
      samples: samples,
      cols: fieldCols,
      rows: fieldRows,
      origin: Offset(left, top),
      step: fieldStep,
    ),
  );
}

/// The edge of a trace grid alone, without field samples: the contour
/// crossings [outlinePartsFromFields] traces from the same
/// [trace] grid and [near] blocks, for a body that is only filled.
@internal
OutlineParts outlineEdgeParts({
  required Float64List trace,
  required int cols,
  required int rows,
  required Uint8List near,
  required int blockCols,
  required int block,
  required double left,
  required double top,
  required double step,
}) {
  final (points, loops) = _OutlineTracer.trace(
    trace,
    cols,
    rows,
    near: near,
    blockCols: blockCols,
    block: block,
    left: left,
    top: top,
    step: step,
  );
  return OutlineParts(points: points, loops: loops);
}

/// The outline [parts] describe: the quadratic B-spline through each loop
/// of crossings as one even-odd path, shaded from the field samples.
///
/// Parts that carry no samples give the field [shaded] computes when a
/// renderer first reads it, and no field without [shaded].
///
/// A run of crossings along one grid row or column, where the spline is
/// straight, becomes one line.
@internal
@pragma('vm:unsafe:no-bounds-checks')
GlassOutline outlineFromParts(
  OutlineParts parts, {
  OutlineParts Function()? shaded,
}) {
  final path = _outlinePath(parts.points, parts.loops);
  if (parts.grid case final grid?) {
    return GlassOutline(path, field: () => _field(grid, path));
  }
  if (shaded == null) return GlassOutline(path);
  return GlassOutline(path, field: () => _field(shaded().grid!, path));
}

LiquidGlassField _field(OutlineGrid grid, Path edge) => LiquidGlassField(
  samples: grid.samples,
  columns: grid.cols,
  rows: grid.rows,
  origin: grid.origin,
  step: grid.step,
  edge: edge,
);

@pragma('vm:unsafe:no-bounds-checks')
Path _outlinePath(Float64List xy, Int32List loops) {
  final path = Path();
  path.fillType = PathFillType.evenOdd;
  var base = 0;
  for (var l = 0; l < loops.length; l++) {
    final n = loops[l];
    final first = base;
    final last = base + n - 1;
    var fromX = (xy[last * 2] + xy[first * 2]) / 2;
    var fromY = (xy[last * 2 + 1] + xy[first * 2 + 1]) / 2;
    path.moveTo(fromX, fromY);
    var startX = 0.0;
    var startY = 0.0;
    var lined = false;
    for (var k = 0; k < n; k++) {
      final p = base + k;
      final q = k + 1 < n ? p + 1 : first;
      final px = xy[p * 2];
      final py = xy[p * 2 + 1];
      final toX = (px + xy[q * 2]) / 2;
      final toY = (py + xy[q * 2 + 1]) / 2;
      final across =
          fromY == py && py == toY && (fromX <= px ? px <= toX : px >= toX);
      final down =
          fromX == px && px == toX && (fromY <= py ? py <= toY : py >= toY);
      if (across || down) {
        final continues =
            lined &&
            (across
                ? startY == fromY && (startX <= fromX) == (fromX <= toX)
                : startX == fromX && (startY <= fromY) == (fromY <= toY));
        if (!continues) {
          if (lined) path.lineTo(fromX, fromY);
          startX = fromX;
          startY = fromY;
          lined = true;
        }
      } else {
        if (lined) {
          path.lineTo(fromX, fromY);
          lined = false;
        }
        path.quadraticBezierTo(px, py, toX, toY);
      }
      fromX = toX;
      fromY = toY;
    }
    if (lined) path.lineTo(fromX, fromY);
    path.close();
    base += n;
  }
  return path;
}

/// Marching squares over the near blocks of a trace grid, stitched by the
/// grid edges the contour crosses and smoothed into the quadratic B-spline
/// through the crossings (the limit of Chaikin's corner cutting).
///
/// A saddle cell is resolved by the mean of its corners. The buffers live
/// across calls in [_TracerBuffers] (statics are per isolate, and each
/// isolate traces one outline at a time). They retain the largest traced
/// grid until the isolate exits.
class _OutlineTracer {
  factory _OutlineTracer(int edges) {
    final buffers = _TracerBuffers.claim(edges);
    return _OutlineTracer._(
      buffers.stamp,
      buffers.slot,
      buffers.generation,
      buffers.xs,
      buffers.ys,
      buffers.links,
      buffers.seen,
    );
  }

  _OutlineTracer._(
    this._stamp,
    this._slot,
    this._generation,
    this._xs,
    this._ys,
    this._links,
    this._seen,
  );

  final Int32List _stamp;
  final Int32List _slot;
  final int _generation;
  Float64List _xs;
  Float64List _ys;
  Int32List _links;
  Uint8List _seen;
  int _count = 0;

  static (Float64List, Int32List) trace(
    Float64List values,
    int cols,
    int rows, {
    required Uint8List near,
    required int blockCols,
    required int block,
    required double left,
    required double top,
    required double step,
  }) {
    final horizontal = rows * (cols - 1);
    final tracer = _OutlineTracer(horizontal + (rows - 1) * cols);
    final blockRows = near.length ~/ blockCols;
    for (var bj = 0; bj < blockRows; bj++) {
      for (var bi = 0; bi < blockCols; bi++) {
        if (near[bj * blockCols + bi] == 0) continue;
        final jEnd = math.min(bj * block + block, rows - 1);
        final iEnd = math.min(bi * block + block, cols - 1);
        for (var j = bj * block; j < jEnd; j++) {
          final upper = j * cols;
          final lower = upper + cols;
          final y0 = top + j.toDouble() * step;
          for (var i = bi * block; i < iEnd; i++) {
            final tl = values[upper + i];
            final tr = values[upper + i + 1];
            final br = values[lower + i + 1];
            final bl = values[lower + i];
            final mask =
                (tl < 0 ? 8 : 0) |
                (tr < 0 ? 4 : 0) |
                (br < 0 ? 2 : 0) |
                (bl < 0 ? 1 : 0);
            if (mask == 0 || mask == 15) continue;
            final x0 = left + i.toDouble() * step;
            final eTop = j * (cols - 1) + i;
            final eLeft = horizontal + j * cols + i;
            final saddle = mask == 5 || mask == 10;
            final first = saddle && (tl + tr + br + bl < 0) == (mask == 5)
                ? 2
                : 0;
            final last = saddle ? first + 2 : 1;
            for (var k = first; k < last; k++) {
              final pair = saddle ? _saddlePairs[k] : _pairs[mask];
              tracer._link(
                tracer._edge(
                  pair >> 2,
                  eTop,
                  eLeft,
                  cols,
                  x0,
                  y0,
                  step,
                  tl,
                  tr,
                  br,
                  bl,
                ),
                tracer._edge(
                  pair & 3,
                  eTop,
                  eLeft,
                  cols,
                  x0,
                  y0,
                  step,
                  tl,
                  tr,
                  br,
                  bl,
                ),
              );
            }
          }
        }
      }
    }
    return tracer._stitch();
  }

  /// Per corner mask, the two crossed sides of a one-segment cell packed
  /// as `a << 2 | b` (sides: 0 top, 1 right, 2 bottom, 3 left).
  static const List<int> _pairs = [
    0,
    3 << 2 | 2,
    2 << 2 | 1,
    3 << 2 | 1,
    0 << 2 | 1,
    0,
    0 << 2 | 2,
    3 << 2 | 0,
    3 << 2 | 0,
    0 << 2 | 2,
    0,
    0 << 2 | 1,
    3 << 2 | 1,
    2 << 2 | 1,
    3 << 2 | 2,
    0,
  ];

  /// The two ways through a saddle cell: the first two pairs keep the
  /// inside corners apart, the last two join them through the center.
  static const List<int> _saddlePairs = [
    3 << 2 | 2,
    0 << 2 | 1,
    3 << 2 | 0,
    2 << 2 | 1,
  ];

  int _edge(
    int side,
    int eTop,
    int eLeft,
    int cols,
    double x0,
    double y0,
    double step,
    double tl,
    double tr,
    double br,
    double bl,
  ) => switch (side) {
    0 => _crossing(eTop, x0, y0, tl, x0 + step, y0, tr),
    1 => _crossing(eLeft + 1, x0 + step, y0, tr, x0 + step, y0 + step, br),
    2 => _crossing(
      eTop + cols - 1,
      x0,
      y0 + step,
      bl,
      x0 + step,
      y0 + step,
      br,
    ),
    _ => _crossing(eLeft, x0, y0, tl, x0, y0 + step, bl),
  };

  int _crossing(
    int edge,
    double x0,
    double y0,
    double v0,
    double x1,
    double y1,
    double v1,
  ) {
    if (_stamp[edge] == _generation) return _slot[edge];
    final slot = _count++;
    if (slot >= _xs.length) _grow();
    _stamp[edge] = _generation;
    _slot[edge] = slot;
    final denom = v0 - v1;
    var t = denom.abs() < 1e-6 ? 0.5 : v0 / denom;
    if (t < 0) t = 0;
    if (t > 1) t = 1;
    _xs[slot] = x0 + (x1 - x0) * t;
    _ys[slot] = y0 + (y1 - y0) * t;
    _links[slot * 2] = -1;
    _links[slot * 2 + 1] = -1;
    _seen[slot] = 0;
    return slot;
  }

  void _grow() {
    _TracerBuffers.grow();
    _xs = _TracerBuffers.xs;
    _ys = _TracerBuffers.ys;
    _links = _TracerBuffers.links;
    _seen = _TracerBuffers.seen;
  }

  void _link(int a, int b) {
    if (_links[a * 2] < 0) {
      _links[a * 2] = b;
    } else {
      _links[a * 2 + 1] = b;
    }
    if (_links[b * 2] < 0) {
      _links[b * 2] = a;
    } else {
      _links[b * 2 + 1] = a;
    }
  }

  (Float64List, Int32List) _stitch() {
    final points = Float64List(_count * 2);
    final loops = <int>[];
    var written = 0;
    for (var start = 0; start < _count; start++) {
      if (_seen[start] != 0) continue;
      final from = written;
      var current = start;
      while (current >= 0 && _seen[current] == 0) {
        _seen[current] = 1;
        points[written * 2] = _xs[current];
        points[written * 2 + 1] = _ys[current];
        written++;
        final a = _links[current * 2];
        final b = _links[current * 2 + 1];
        current = a >= 0 && _seen[a] == 0
            ? a
            : b >= 0 && _seen[b] == 0
            ? b
            : -1;
      }
      if (written - from < 3) {
        written = from;
      } else {
        loops.add(written - from);
      }
    }
    return (
      Float64List.sublistView(points, 0, written * 2),
      Int32List.fromList(loops),
    );
  }
}

/// The buffers of [_OutlineTracer], kept across calls: per grid edge the
/// generation it was last crossed in and its crossing's slot, per slot
/// the crossing and its two neighbours along the contour.
abstract final class _TracerBuffers {
  static Int32List stamp = Int32List(0);
  static Int32List slot = Int32List(0);
  static int generation = 0;
  static Float64List xs = Float64List(256);
  static Float64List ys = Float64List(256);
  static Int32List links = Int32List(512);
  static Uint8List seen = Uint8List(256);

  /// Readies the buffers for a grid of [edges] edges and starts a new
  /// generation.
  static ({
    Int32List stamp,
    Int32List slot,
    int generation,
    Float64List xs,
    Float64List ys,
    Int32List links,
    Uint8List seen,
  })
  claim(int edges) {
    if (stamp.length < edges) {
      stamp = Int32List(edges + edges ~/ 2);
      slot = Int32List(stamp.length);
      generation = 0;
    }
    generation++;
    if (generation == 0x3FFFFFFF) {
      stamp.fillRange(0, stamp.length, 0);
      generation = 1;
    }
    return (
      stamp: stamp,
      slot: slot,
      generation: generation,
      xs: xs,
      ys: ys,
      links: links,
      seen: seen,
    );
  }

  /// Doubles the per-slot buffers, keeping their contents.
  static void grow() {
    final size = xs.length * 2;
    final nextXs = Float64List(size);
    nextXs.setAll(0, xs);
    xs = nextXs;
    final nextYs = Float64List(size);
    nextYs.setAll(0, ys);
    ys = nextYs;
    final nextLinks = Int32List(size * 2);
    nextLinks.setAll(0, links);
    links = nextLinks;
    final nextSeen = Uint8List(size);
    nextSeen.setAll(0, seen);
    seen = nextSeen;
  }
}

/// The latest unions, the one used last at the end.
final List<(List<RRect>, GlassOutline)> _recentUnions = [];

/// How many unions [_recentUnions] keeps per isolate.
const int _recentLimit = 4;

/// The plain union of [shapes], whose corners must share one circular
/// radius each: one closed contour per connected part, a box inside
/// another adding nothing. The latest unions are kept.
///
/// Its field, computed when a renderer first reads it, is sampled every 4
/// points over the union and a margin: each node holds the
/// distance to the nearest shape, its gradient by central differences,
/// turned as the renderer turns a rounded box's normals near its corners
/// ([LiquidGlassField.opticalCornerScale]), and that shape's half
/// thickness.
@internal
GlassOutline unionOutline(List<RRect> shapes) {
  for (var k = 0; k < _recentUnions.length; k++) {
    final (recent, outline) = _recentUnions[k];
    if (listEquals(recent, shapes)) {
      if (k < _recentUnions.length - 1) {
        _recentUnions.add(_recentUnions.removeAt(k));
      }
      return outline;
    }
  }
  final kept = List<RRect>.unmodifiable(shapes);
  final path = _unionPath(kept);
  final outline = GlassOutline(
    path,
    field: () => _unionField(kept, path),
  );
  _recentUnions.add((kept, outline));
  if (_recentUnions.length > _recentLimit) _recentUnions.removeAt(0);
  return outline;
}

/// The edge of the plain union of [shapes]: one closed contour per
/// connected part, a box inside another adding nothing.
Path _unionPath(List<RRect> shapes) {
  for (final shape in shapes) {
    assertUniformCorners(shape);
  }
  final kept = [
    for (var i = 0; i < shapes.length; i++)
      if (!_covered(shapes, i)) shapes[i],
  ];
  var union = _rrectPath(kept.first);
  for (final shape in kept.skip(1)) {
    union = Path.combine(PathOperation.union, union, _rrectPath(shape));
  }
  return union;
}

Path _rrectPath(RRect shape) {
  final path = Path();
  path.addRRect(shape);
  return path;
}

/// Whether shape [i] of [shapes] adds nothing to their union: another
/// shape encloses it, and of two that enclose each other the first stays.
bool _covered(List<RRect> shapes, int i) {
  final shape = shapes[i];
  for (var j = 0; j < shapes.length; j++) {
    if (j == i) continue;
    final other = shapes[j];
    if (encloses(other, shape) && (j < i || !encloses(shape, other))) {
      return true;
    }
  }
  return false;
}

LiquidGlassField _unionField(List<RRect> kept, Path edge) {
  const step = 4.0;
  final boxes = OutlineBoxes(kept);
  final area = edge.getBounds().inflate(2 * step + 4);
  final cols = (area.width / step).ceil() + 1;
  final rows = (area.height / step).ceil() + 1;
  final distance = Float64List(cols * rows);
  final nearest = Int32List(cols * rows);
  for (var j = 0; j < rows; j++) {
    final y = area.top + j * step;
    for (var i = 0; i < cols; i++) {
      final x = area.left + i * step;
      var best = double.infinity;
      var which = 0;
      for (var b = 0; b < boxes.length; b++) {
        final d = boxes.distance(b, x, y);
        if (d < best) {
          best = d;
          which = b;
        }
      }
      distance[j * cols + i] = best;
      nearest[j * cols + i] = which;
    }
  }
  final samples = Float32List(cols * rows * 4);
  final turn = Float64List(2);
  for (var j = 0; j < rows; j++) {
    final up = j > 0 ? j - 1 : 0;
    final down = j < rows - 1 ? j + 1 : rows - 1;
    for (var i = 0; i < cols; i++) {
      final back = i > 0 ? i - 1 : 0;
      final ahead = i < cols - 1 ? i + 1 : cols - 1;
      final at = j * cols + i;
      var gx =
          (distance[j * cols + ahead] - distance[j * cols + back]) /
          ((ahead - back) * step);
      var gy =
          (distance[down * cols + i] - distance[up * cols + i]) /
          ((down - up) * step);
      final which = nearest[at];
      final x = area.left + i * step;
      final y = area.top + j * step;
      if (boxes.inOpticalCorner(which, x, y)) {
        boxes.opticalTurn(which, x, y, turn, 0);
        final tx = gx * turn[0] - gy * turn[1];
        gy = gx * turn[1] + gy * turn[0];
        gx = tx;
      }
      final out = at * 4;
      samples[out] = distance[at];
      samples[out + 1] = gx;
      samples[out + 2] = gy;
      samples[out + 3] = boxes.halfMinor(which);
    }
  }
  return LiquidGlassField(
    samples: samples,
    columns: cols,
    rows: rows,
    origin: area.topLeft,
    step: step,
    edge: edge,
  );
}

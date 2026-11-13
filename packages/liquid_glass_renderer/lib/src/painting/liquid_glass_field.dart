import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// The signed distance field of one glass body whose outline its owner has
/// already fused, sampled on a square grid.
///
/// Give it to `LiquidGlassLayer.field` when the shapes of a layer form one
/// body that no blend of their outlines describes: a menu that grows out of
/// its button and stays joined to it by a neck, or any outline a widget
/// computes itself. [LiquidGlassField.fromPath] computes the field of any
/// path. The layer then shades the body the field describes; its
/// shapes still supply the appearance, the shadows, the content clips and
/// the bounds of the glass, which must contain the body.
///
/// Every node holds four values in [samples]: the signed distance (negative
/// inside), its gradient along x and y, and the half minor extent of the
/// part of the body the node belongs to (half the thickness the bevel and
/// the refraction fit). The distance and the extent are in logical pixels
/// of the layer. The gradient is the distance's own, not normalized: where
/// its length drops below 1, as where a smooth union joins two parts, the
/// refraction weakens as it does where blended shapes join. Node (i, j)
/// sits at [origin] + (i, j) * [step] in the layer's coordinates. The grid
/// must cover the body with a margin of at least two nodes and hold at
/// least two nodes along each axis.
///
/// The layer interpolates the four nodes around a pixel bilinearly, so the
/// distance and the normal stay continuous. A layer shades a field again
/// only when a field that is not equal arrives, and uploads [samples] again
/// when a different list arrives: reuse a list only while its contents are
/// the same.
@immutable
class LiquidGlassField {
  /// Creates a field from its samples.
  const LiquidGlassField({
    required this.samples,
    required this.cols,
    required this.rows,
    required this.origin,
    required this.step,
  }) : assert(cols >= 2 && rows >= 2, 'A field needs two nodes per axis.'),
       assert(step > 0, 'A field needs a positive step.');

  /// The field of the body whose edge is [path], in the coordinates of the
  /// path: any closed outline, with as many contours and holes as its fill
  /// type gives it. Contours that overlap form one body: the parts of them
  /// inside the fill are no edge of it.
  ///
  /// Nodes lie [step] logical pixels apart; 2 follows corners of a few
  /// pixels' radius, and a larger step costs less and rounds sharp corners
  /// more. [thickness] is the thickness of the glass the bevel and the
  /// refraction fit, the same over the whole body; it defaults to the
  /// widest the body is across its narrowest direction (twice the radius of
  /// the largest circle that fits in it).
  ///
  /// The distance of every node is measured to every piece of the edge, so
  /// the cost grows with the body's area over the square of [step] times
  /// the length of its edge: about 90 ms in a debug build for a rounded
  /// body of 300 by 200 at a step of 2, and a third of that at a step of
  /// 4. Compute a field when its path changes and keep it, not once a
  /// frame; for an outline that animates, a coarser step or a field the
  /// owner computes from its own description of the body is cheaper.
  ///
  /// Throws an [ArgumentError] for a path that encloses nothing.
  factory LiquidGlassField.fromPath(
    Path path, {
    double step = 2,
    double? thickness,
  }) {
    if (!(step > 0)) throw ArgumentError.value(step, 'step', 'not positive');
    final bounds = path.getBounds();
    if (!bounds.isFinite || bounds.isEmpty) {
      throw ArgumentError.value(path, 'path', 'encloses nothing');
    }
    // The edge as short straight pieces, x0 y0 x1 y1 each.
    final spacing = math.min(step / 2, 1);
    final pieces = <double>[];
    for (final contour in path.computeMetrics()) {
      final length = contour.length;
      if (length <= 0) continue;
      final count = math.max(2, (length / spacing).ceil());
      var from = contour.getTangentForOffset(0)!.position;
      final first = from;
      for (var k = 1; k <= count; k++) {
        final to = contour.getTangentForOffset(length * k / count)!.position;
        pieces
          ..add(from.dx)
          ..add(from.dy)
          ..add(to.dx)
          ..add(to.dy);
        from = to;
      }
      // A contour left open is filled as if closed.
      if (from != first) {
        pieces
          ..add(from.dx)
          ..add(from.dy)
          ..add(first.dx)
          ..add(first.dy);
      }
    }
    // Where contours overlap, a piece of one runs through the fill of the
    // other: it is no edge of the body, and measured to it the glass would
    // show a rim along it. A piece is an edge only where the fill differs
    // on its two sides.
    final probe = math.min(step / 4, 0.5);
    final outline = <double>[];
    for (var s = 0; s < pieces.length; s += 4) {
      final dx = pieces[s + 2] - pieces[s];
      final dy = pieces[s + 3] - pieces[s + 1];
      final length = math.sqrt(dx * dx + dy * dy);
      if (length <= 0) continue;
      final middle = Offset(
        (pieces[s] + pieces[s + 2]) / 2,
        (pieces[s + 1] + pieces[s + 3]) / 2,
      );
      final across = Offset(-dy, dx) / length * probe;
      if (path.contains(middle + across) != path.contains(middle - across)) {
        outline.addAll(pieces.getRange(s, s + 4));
      }
    }
    if (outline.isEmpty) {
      throw ArgumentError.value(path, 'path', 'encloses nothing');
    }
    final edge = Float64List.fromList(outline);
    const margin = 3;
    final origin = Offset(
      (bounds.left / step).floorToDouble() * step - margin * step,
      (bounds.top / step).floorToDouble() * step - margin * step,
    );
    final cols = ((bounds.right - origin.dx) / step).ceil() + margin + 1;
    final rows = ((bounds.bottom - origin.dy) / step).ceil() + margin + 1;
    final distance = Float64List(cols * rows);
    var deepest = 0.0;
    for (var j = 0; j < rows; j++) {
      final y = origin.dy + j * step;
      for (var i = 0; i < cols; i++) {
        final x = origin.dx + i * step;
        var nearest = double.infinity;
        for (var s = 0; s < edge.length; s += 4) {
          final ax = edge[s];
          final ay = edge[s + 1];
          final bx = edge[s + 2] - ax;
          final by = edge[s + 3] - ay;
          final px = x - ax;
          final py = y - ay;
          final along = bx * bx + by * by;
          final t = along <= 0
              ? 0.0
              : ((px * bx + py * by) / along).clamp(0.0, 1.0);
          final dx = px - bx * t;
          final dy = py - by * t;
          final d = dx * dx + dy * dy;
          if (d < nearest) nearest = d;
        }
        final d = math.sqrt(nearest);
        final inside = path.contains(Offset(x, y));
        if (inside && d > deepest) deepest = d;
        distance[j * cols + i] = inside ? -d : d;
      }
    }
    if (deepest <= 0 && thickness == null) {
      throw ArgumentError.value(path, 'path', 'encloses nothing');
    }
    final half = (thickness ?? deepest * 2) / 2;
    final samples = Float32List(cols * rows * 4);
    for (var j = 0; j < rows; j++) {
      final up = math.max(j - 1, 0);
      final down = math.min(j + 1, rows - 1);
      for (var i = 0; i < cols; i++) {
        final left = math.max(i - 1, 0);
        final right = math.min(i + 1, cols - 1);
        final at = (j * cols + i) * 4;
        samples[at] = distance[j * cols + i];
        samples[at + 1] =
            (distance[j * cols + right] - distance[j * cols + left]) /
            ((right - left) * step);
        samples[at + 2] =
            (distance[down * cols + i] - distance[up * cols + i]) /
            ((down - up) * step);
        samples[at + 3] = half;
      }
    }
    return LiquidGlassField(
      samples: samples,
      cols: cols,
      rows: rows,
      origin: origin,
      step: step,
    );
  }

  /// Four values per node, row-major: at least `cols * rows * 4`.
  final Float32List samples;

  /// The number of nodes along x.
  final int cols;

  /// The number of nodes along y.
  final int rows;

  /// The position of node (0, 0) in the layer's logical coordinates.
  final Offset origin;

  /// The distance between neighboring nodes, in logical pixels.
  final double step;

  /// Fields are equal when they share one sample list and the same grid.
  @override
  bool operator ==(Object other) =>
      other is LiquidGlassField &&
      identical(other.samples, samples) &&
      other.cols == cols &&
      other.rows == rows &&
      other.origin == origin &&
      other.step == step;

  @override
  int get hashCode =>
      Object.hash(identityHashCode(samples), cols, rows, origin, step);

  /// The same field moved by [offset]; it shares the samples.
  LiquidGlassField shift(Offset offset) => LiquidGlassField(
    samples: samples,
    cols: cols,
    rows: rows,
    origin: origin + offset,
    step: step,
  );
}

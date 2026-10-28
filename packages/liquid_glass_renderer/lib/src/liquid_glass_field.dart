import 'dart:ui';

import 'package:flutter/foundation.dart';

/// The signed distance field of one glass body whose outline its owner has
/// already fused, sampled on a square grid.
///
/// Give it to `LiquidGlassLayer.field` when the shapes of a layer form one
/// body that no blend of their outlines describes: a menu that grows out of
/// its button and stays joined to it by a neck, or any outline a widget
/// computes itself. The layer then shades the body the field describes; its
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

import 'dart:collection';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_settings.dart';
import 'package:liquid_glass_renderer/src/rendering/drawn_values.dart';
import 'package:liquid_glass_renderer/src/rendering/render_liquid_glass_geometry.dart';

/// What a glass layer's last painted frame committed to the retained layer
/// tree.
@internal
enum GlassFrameState {
  /// The frame drew no glass effect: no shapes are registered, or none is
  /// drawn and the effect keeps no geometry.
  empty,

  /// Shapes are registered but none is drawn ([FrameShapes.drawn]).
  idle,

  /// The frame drew the glass effect for at least one drawn shape.
  active,
}

/// How a shape's own axes map into its layer: the images of its unit axes
/// and their determinant.
@internal
typedef ShapeBasis = ({Offset axisX, Offset axisY, double determinant});

/// One shape a layer's committed frame draws.
@internal
final class FrameShape {
  FrameShape._(this.committed, this.shape, this.basis);

  /// The geometry that holds [shape], built by the glass itself or by the
  /// blend group it joins.
  final CommittedGeometry committed;

  /// The shape.
  final ShapeGeometry shape;

  /// How the shape's axes map into the layer, invertibly.
  final ShapeBasis basis;

  /// The transform from the shape's own coordinates into the layer, over
  /// storage no one can write, so it may be kept past the frame.
  late final Matrix4 toLayer = Matrix4.fromFloat64List(
    switch (shape.shapeToGeometry) {
      final toGeometry? => committed.toLayer.multiplied(toGeometry),
      null => committed.toLayer.clone(),
    }.storage.asUnmodifiableView(),
  );

  /// The shape's glow where it draws.
  DrawnGlow? get glow => shape.renderObject.glow;
}

/// A geometry a glass layer's frame committed: the render object it came
/// from, the cache that render object built, and its transform into the
/// layer.
@internal
@immutable
final class CommittedGeometry {
  /// Commits [cache] of [source] at [toLayer].
  const CommittedGeometry(this.source, this.cache, this.toLayer);

  /// The render object the geometry came from.
  final RenderLiquidGlassGeometry source;

  /// The geometry [source] built.
  final GeometryCache cache;

  /// The transform from the geometry into the layer.
  final Matrix4 toLayer;

  /// This geometry with a transform of its own, which a later poll cannot
  /// move.
  CommittedGeometry snapshot() =>
      CommittedGeometry(source, cache, toLayer.clone());

  /// Whether [other] is this geometry at the same revision: the same render
  /// object at the same revision, wherever it lies.
  bool sameRevision(CommittedGeometry other) =>
      identical(source, other.source) && cache.revision == other.cache.revision;

  /// Whether [other] is this geometry built from the same inputs: the same
  /// render object and cache, at the same transform.
  bool sameInputs(CommittedGeometry other) =>
      identical(source, other.source) &&
      identical(cache, other.cache) &&
      MatrixUtils.matrixEquals(toLayer, other.toLayer);
}

/// The shapes a glass layer's frame committed, and the ones it draws: those
/// that show ([DrawnAppearance.shows]) through a transform that keeps them a
/// shape.
@internal
final class FrameShapes {
  final List<CommittedGeometry> _geometries = [];
  final List<FrameShape> _drawn = [];
  double? _smallestShortSide;

  /// The committed geometries in paint order, each with its transform into
  /// the layer.
  late final List<CommittedGeometry> geometries = UnmodifiableListView(
    _geometries,
  );

  /// The committed shapes the layer draws, in paint order.
  late final List<FrameShape> drawn = UnmodifiableListView(_drawn);

  /// The short side the layer's frost and shared color model are worn at:
  /// that of the smallest drawn shape in the layer's logical pixels, at
  /// least one, or the widest a frost fits ([frostFitShortSides]) where
  /// none draws.
  double get wornShortSide =>
      max(1, _smallestShortSide ?? frostFitShortSides.largest);

  /// The state of this frame in an effect that [encodesGeometry] or not.
  GlassFrameState state({required bool encodesGeometry}) {
    if (_geometries.isEmpty) return GlassFrameState.empty;
    if (_drawn.isNotEmpty) return GlassFrameState.active;
    return encodesGeometry ? GlassFrameState.idle : GlassFrameState.empty;
  }

  /// The drawn shape of [renderObject], or null where the frame draws none.
  FrameShape? drawnOf(RenderObject? renderObject) {
    if (renderObject == null) return null;
    for (final drawn in _drawn) {
      if (identical(drawn.shape.renderObject, renderObject)) return drawn;
    }
    return null;
  }

  /// Takes [geometries] as the committed frame.
  void commit(List<CommittedGeometry> geometries) {
    _geometries
      ..clear()
      ..addAll(geometries);
    _drawn.clear();
    _smallestShortSide = null;
    for (final committed in geometries) {
      for (final shape in committed.cache.shapes) {
        if (!shape.appearance.shows) continue;
        final basis = _basis(shape, committed.toLayer);
        if (basis == null) continue;
        _drawn.add(FrameShape._(committed, shape, basis));
        final side = MatrixUtils.transformRect(
          committed.toLayer,
          shape.shapeBounds,
        ).shortestSide;
        if (side <= 0) continue;
        _smallestShortSide = min(_smallestShortSide ?? side, side);
      }
    }
  }

  static ShapeBasis? _basis(ShapeGeometry shape, Matrix4 geometryToLayer) {
    final shapeToGeometry = shape.shapeToGeometry;
    Offset toLayer(Offset point) => MatrixUtils.transformPoint(
      geometryToLayer,
      shapeToGeometry == null
          ? point
          : MatrixUtils.transformPoint(shapeToGeometry, point),
    );
    final origin = toLayer(Offset.zero);
    final axisX = toLayer(const Offset(1, 0)) - origin;
    final axisY = toLayer(const Offset(0, 1)) - origin;
    final determinant = axisX.dx * axisY.dy - axisY.dx * axisX.dy;
    if (determinant.abs() < 1e-8) return null;
    return (axisX: axisX, axisY: axisY, determinant: determinant);
  }
}

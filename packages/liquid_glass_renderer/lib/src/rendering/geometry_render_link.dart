import 'dart:collection';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_shape_helpers.dart';
import 'package:liquid_glass_renderer/src/rendering/render_liquid_glass_geometry.dart';

/// Where the glass shapes and blend groups of one glass layer register, in
/// paint order, so the layer draws their geometry.
class GeometryRenderLink {
  final List<RenderLiquidGlassGeometry> _shapeGeometries = [];

  /// The registered geometries in paint order.
  late final UnmodifiableListView<RenderLiquidGlassGeometry> shapes =
      UnmodifiableListView(_shapeGeometries);

  bool _dirty = false;

  /// Whether geometry changed since the layer last consumed the flag.
  bool get isDirty => _dirty;

  /// Consumes the dirty flag after the layer rebuilt its frame.
  void markClean() => _dirty = false;

  List<RenderLiquidGlassGeometry> _painted = const [];

  /// The registered geometries the owner paints, in paint order, as of the
  /// last [updatePaintOrder].
  List<RenderLiquidGlassGeometry> get painted => _painted;

  /// Sorts the registered geometries into the paint order under [owner], and
  /// each of them its own shapes. The geometry is dirty where the order or
  /// the geometries [owner] paints changed: one back onstage keeps its
  /// registration and its geometry.
  void updatePaintOrder(RenderObject owner) {
    if (sortGlassPaintOrder(owner, _shapeGeometries, (source) => source)) {
      _dirty = true;
    }
    for (final geometry in _shapeGeometries) {
      geometry.updatePaintOrder();
    }
    final painted = [
      for (final geometry in _shapeGeometries)
        if (isGlassShapePainted(geometry, owner)) geometry,
    ];
    if (!listEquals(painted, _painted)) _dirty = true;
    _painted = painted;
  }

  /// Rebuilds the geometry of every registered render object that changed,
  /// on a layer whose default appearance is [defaultAppearance].
  void updateAllGeometries(LiquidGlassAppearance defaultAppearance) {
    for (final renderObject in _shapeGeometries) {
      renderObject.maybeRebuildGeometry(defaultAppearance);
    }
  }

  /// Called when a glass or a blend group registers with or leaves the layer.
  VoidCallback? onMembershipChanged;

  LiquidGlassShapeRenderObject? _lit;

  /// The shape whose glow the layer draws.
  LiquidGlassShapeRenderObject? get lit => _lit;

  /// Called when the lit shape or its glow changes.
  VoidCallback? onGlowChanged;

  /// Takes the new glow of [shape], which [draws] says draws.
  void reportGlow(LiquidGlassShapeRenderObject shape, {required bool draws}) {
    if (!draws && !identical(shape, _lit)) return;
    _lit = draws ? shape : null;
    onGlowChanged?.call();
  }

  /// Adds [renderObject]'s geometry to the layer.
  void registerGeometry(
    RenderLiquidGlassGeometry renderObject,
  ) {
    if (_shapeGeometries.contains(renderObject)) return;
    _dirty = true;
    _shapeGeometries.add(renderObject);
    onMembershipChanged?.call();
  }

  /// Marks the geometry as changed since the layer last drew it.
  void markDirty() {
    _dirty = true;
  }

  /// Removes [renderObject]'s geometry from the layer.
  void unregisterGeometry(RenderLiquidGlassGeometry renderObject) {
    if (_shapeGeometries.remove(renderObject)) {
      _dirty = true;
      onMembershipChanged?.call();
    }
  }

  /// Forgets every registered geometry.
  void dispose() {
    _shapeGeometries.clear();
    _painted = const [];
    _lit = null;
  }
}

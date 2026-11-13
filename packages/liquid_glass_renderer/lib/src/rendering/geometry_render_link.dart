import 'dart:collection';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/rendering/render_liquid_glass_geometry.dart';

/// Where the glass shapes and blend groups of one glass layer register, in
/// paint order, so the layer draws their geometry.
class GeometryRenderLink {
  final List<RenderLiquidGlassGeometry> _shapeGeometries = [];

  /// The registered geometries in paint order.
  late final UnmodifiableListView<RenderLiquidGlassGeometry> shapes =
      UnmodifiableListView(_shapeGeometries);

  LiquidGlassSettings _settings = const LiquidGlassSettings();

  /// The settings of the layer, which every registered geometry holds.
  ///
  /// The layer writes them; each geometry takes them in the same call, and a
  /// geometry that registers later takes them as it registers.
  LiquidGlassSettings get settings => _settings;
  set settings(LiquidGlassSettings value) {
    if (_settings == value) return;
    _settings = value;
    for (final geometry in _shapeGeometries) {
      geometry.settings = value;
    }
  }

  bool _dirty = false;

  /// Whether geometry changed since the layer last consumed the flag.
  bool get isDirty => _dirty;

  /// Consumes the dirty flag after the layer rebuilt its frame.
  void markClean() => _dirty = false;

  /// Sorts the registered geometries into the paint order under [owner], and
  /// each of them its own shapes.
  void updatePaintOrder(RenderObject owner) {
    if (sortGlassPaintOrder(owner, _shapeGeometries, (source) => source)) {
      _dirty = true;
    }
    for (final geometry in _shapeGeometries) {
      geometry.updatePaintOrder();
    }
  }

  /// Rebuilds the geometry of every registered render object that changed.
  void updateAllGeometries() {
    for (final renderObject in _shapeGeometries) {
      renderObject.maybeRebuildGeometry();
    }
  }

  /// Called when a glass or a blend group registers with or leaves the layer.
  VoidCallback? onMembershipChanged;

  /// Adds [renderObject]'s geometry to the layer.
  void registerGeometry(
    RenderLiquidGlassGeometry renderObject,
  ) {
    if (_shapeGeometries.contains(renderObject)) return;
    renderObject.settings = _settings;
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
  }
}

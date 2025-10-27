// ignore_for_file: avoid_positional_boolean_parameters

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/liquid_shape.dart';
import 'package:meta/meta.dart';

/// A link that connects liquid glass shapes to their parent layer for
/// efficient communication of position, size, and transform changes.
///
/// This replaces the ticker-based approach with an event-driven system
/// similar to follow_the_leader's LeaderLink pattern.
@internal
@Deprecated('Use BlendGroupLink instead')
class GlassLink with ChangeNotifier {
  /// Creates a new [GlassLink].
  GlassLink();

  /// Information about a shape registered with this link.
  final Map<RenderLiquidGlass, GlassShapeInfo> _shapes = {};

  /// Register a shape with this link.
  void registerShape(
    RenderLiquidGlass renderObject,
    LiquidShape shape, {
    required bool glassContainsChild,
  }) {
    _shapes[renderObject] = GlassShapeInfo(
      shape: shape,
      glassContainsChild: glassContainsChild,
    );
    notifyListeners();
  }

  /// Unregister a shape from this link.
  void unregisterShape(RenderObject renderObject) {
    _shapes.remove(renderObject);
    notifyListeners();
  }

  /// Update the shape properties for a registered render object.
  void updateShape(
    RenderObject renderObject,
    LiquidShape shape, {
    required bool glassContainsChild,
  }) {
    final info = _shapes[renderObject];
    if (info != null) {
      info
        ..shape = shape
        ..glassContainsChild = glassContainsChild;
      notifyListeners();
    }
  }

  /// Notify that a shape's layout has changed.
  void notifyShapeLayoutChanged(RenderObject renderObject) {
    if (_shapes.containsKey(renderObject)) {
      notifyListeners();
    }
  }

  /// Check if any shapes are registered.
  bool get hasShapes => _shapes.isNotEmpty;

  Iterable<MapEntry<RenderLiquidGlass, GlassShapeInfo>> get shapeEntries =>
      _shapes.entries;

  @override
  void dispose() {
    _shapes.clear();
    super.dispose();
  }
}

/// Information about a shape stored in the [GlassLink].
class GlassShapeInfo {
  /// Creates a new [GlassShapeInfo].
  GlassShapeInfo({
    required this.shape,
    required this.glassContainsChild,
  });

  /// The liquid shape.
  LiquidShape shape;

  /// Whether the glass contains the child.
  bool glassContainsChild;
}

/// A link that connects liquid glass shapes to their parent layer for
/// efficient communication of position, size, and transform changes.
///
/// This replaces the ticker-based approach with an event-driven system
/// similar to follow_the_leader's LeaderLink pattern.
@internal
class BlendGroupLink with ChangeNotifier {
  /// Creates a new [BlendGroupLink].
  BlendGroupLink();

  /// Information about a shape registered with this link.
  final Map<RenderLiquidGlass, (LiquidShape shape, bool glassContainsChild)>
      _shapes = {};

  List<
      MapEntry<RenderLiquidGlass,
          (LiquidShape shape, bool glassContainsChild)>> get shapeEntries =>
      _shapes.entries.toList();

  /// Check if any shapes are registered.
  bool get hasShapes => _shapes.isNotEmpty;

  /// Register a shape with this link.
  void registerShape(
    RenderLiquidGlass renderObject,
    LiquidShape shape,
    bool glassContainsChild,
  ) {
    _shapes[renderObject] = (shape, glassContainsChild);
    notifyListeners();
  }

  /// Unregister a shape from this link.
  void unregisterShape(RenderLiquidGlass renderObject) {
    _shapes.remove(renderObject);
    notifyListeners();
  }

  /// Update the shape properties for a registered render object.
  void updateShape(
    RenderLiquidGlass renderObject,
    LiquidShape shape,
    bool glassContainsChild,
  ) {
    _shapes[renderObject] = (shape, glassContainsChild);
    notifyListeners();
  }

  /// Notify that a shape's layout has changed.
  void notifyShapeLayoutChanged(RenderObject renderObject) {
    if (_shapes.containsKey(renderObject)) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _shapes.clear();
    super.dispose();
  }
}

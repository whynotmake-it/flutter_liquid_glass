import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_scope.dart';
import 'package:liquid_glass_renderer/src/liquid_shape.dart';

/// A link that connects liquid glass shapes to their parent layer for
/// efficient communication of position, size, and transform changes.
///
/// This replaces the ticker-based approach with an event-driven system
/// similar to follow_the_leader's LeaderLink pattern.
@internal
class GlassLink with ChangeNotifier {
  /// Creates a new [GlassLink].
  GlassLink();

  static GlassLink of(BuildContext context) {
    return LiquidGlassScope.of(context).link;
  }

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
    _notifyChange();
  }

  /// Unregister a shape from this link.
  void unregisterShape(RenderObject renderObject) {
    _shapes.remove(renderObject);
    _notifyChange();
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
      _notifyChange();
    }
  }

  /// Notify that a shape's layout has changed.
  void notifyShapeLayoutChanged(RenderObject renderObject) {
    if (_shapes.containsKey(renderObject)) {
      _notifyChange();
    }
  }

  /// Check if any shapes are registered.
  bool get hasShapes => _shapes.isNotEmpty;

  Iterable<MapEntry<RenderLiquidGlass, GlassShapeInfo>> get shapeEntries =>
      _shapes.entries;

  bool _postFrameCallbackScheduled = false;

  void _notifyChange() {
    if (WidgetsBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      // We're in the middle of a layout and paint phase. Notify listeners
      // at the end of the frame.
      if (!_postFrameCallbackScheduled) {
        _postFrameCallbackScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _postFrameCallbackScheduled = false;
          if (hasListeners) notifyListeners();
        });
      }
      return;
    }

    // We're not in a layout/paint phase. Immediately notify listeners.
    notifyListeners();
  }

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

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:liquid_glass_renderer/src/liquid_shape.dart';

/// A link that connects liquid glass shapes to their parent layer for
/// efficient communication of position, size, and transform changes.
///
/// This replaces the ticker-based approach with an event-driven system
/// similar to follow_the_leader's LeaderLink pattern.
class GlassLink with ChangeNotifier {
  /// Creates a new [GlassLink].
  GlassLink();

  /// Information about a shape registered with this link.
  final Map<RenderObject, GlassShapeInfo> _shapes = {};

  /// Register a shape with this link.
  void registerShape(
    RenderObject renderObject,
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

  /// Get all currently registered shapes with their computed information.
  List<ComputedShapeInfo> get computedShapes {
    final result = <ComputedShapeInfo>[];

    for (final entry in _shapes.entries) {
      final renderObject = entry.key;
      final shapeInfo = entry.value;

      if (renderObject is RenderBox &&
          renderObject.attached &&
          renderObject.hasSize) {
        try {
          // Get transform relative to global coordinates
          final transform = renderObject.getTransformTo(null);
          final rect = MatrixUtils.transformRect(
            transform,
            Offset.zero & renderObject.size,
          );

          result.add(
            ComputedShapeInfo(
              renderObject: renderObject,
              shape: shapeInfo.shape,
              glassContainsChild: shapeInfo.glassContainsChild,
              globalBounds: rect,
              transform: transform,
            ),
          );
        } catch (e) {
          // Skip shapes that can't be transformed
          debugPrint('Failed to compute shape info: $e');
        }
      }
    }

    return result;
  }

  /// Check if any shapes are registered.
  bool get hasShapes => _shapes.isNotEmpty;

  /// Get the number of registered shapes.
  int get shapeCount => _shapes.length;

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

/// Computed information about a shape including its global positioning.
class ComputedShapeInfo {
  /// Creates a new [ComputedShapeInfo].
  ComputedShapeInfo({
    required this.renderObject,
    required this.shape,
    required this.glassContainsChild,
    required this.globalBounds,
    required this.transform,
  });

  /// The render object for this shape.
  final RenderObject renderObject;

  /// The liquid shape.
  final LiquidShape shape;

  /// Whether the glass contains the child.
  final bool glassContainsChild;

  /// The global bounds of the shape.
  final Rect globalBounds;

  /// The transform matrix for the shape.
  final Matrix4 transform;
}

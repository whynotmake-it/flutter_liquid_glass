import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';
import 'package:meta/meta.dart';

@internal
mixin TransformTrackingRepaintBoundaryMixin on RenderProxyBox {
  @override
  GeometryTransformTrackingLayer? get layer =>
      super.layer as GeometryTransformTrackingLayer?;

  @override
  bool get isRepaintBoundary => true;

  /// Transform compared across frames to decide whether [onTransformChanged]
  /// should fire. Defaults to the world transform.
  Matrix4 trackedTransform() => getTransformTo(null);

  @override
  OffsetLayer updateCompositedLayer({
    covariant GeometryTransformTrackingLayer? oldLayer,
  }) {
    final layer = oldLayer ??= GeometryTransformTrackingLayer();

    // ignore: cascade_invocations
    layer
      ..renderObject = this
      ..trackedTransform = trackedTransform
      ..onTransformChanged = () {
        if (attached) {
          onTransformChanged();
        }
      }
      ..onCompositing = () {
        if (attached) {
          onCompositing();
        }
      };

    return layer;
  }

  @mustCallSuper
  @override
  void paint(PaintingContext context, ui.Offset offset) {
    layer!.offset = offset;
    super.paint(context, offset);
  }

  void onTransformChanged();

  /// Runs every time this tracking layer is composited, including frames where
  /// the tracked transform is unchanged.
  void onCompositing() {}
}

@internal
mixin TransformTrackingRenderObjectMixin on RenderProxyBox {
  @override
  GeometryTransformTrackingLayer? get layer =>
      super.layer as GeometryTransformTrackingLayer?;

  @override
  @nonVirtual
  bool get isRepaintBoundary => false;

  @override
  bool get alwaysNeedsCompositing => true;

  /// Transform compared across frames to decide whether [onTransformChanged]
  /// should fire. Defaults to the world transform.
  Matrix4 trackedTransform() => getTransformTo(null);

  @mustCallSuper
  @override
  void paint(PaintingContext context, ui.Offset offset) {
    setUpLayer(offset);
    context.pushLayer(layer!, (context, offset) {}, offset);
    super.paint(context, offset);
  }

  GeometryTransformTrackingLayer setUpLayer(Offset offset) {
    return (layer ??= GeometryTransformTrackingLayer())
      ..renderObject = this
      ..onDetached = onTrackingLayerDetached
      ..trackedTransform = trackedTransform
      ..onTransformChanged = () {
        if (attached) {
          onTransformChanged();
        }
      }
      ..onCompositing = () {
        if (attached) {
          onCompositing();
        }
      };
  }

  /// Paints normal children after an override has inserted its tracker.
  /// Calling this mixin's paint again would move that same tracker behind
  /// the effect whose retained-rendering dirtiness it must update first.
  @protected
  void paintTrackedChild(PaintingContext context, Offset offset) {
    super.paint(context, offset);
  }

  /// Also runs when a mounted subtree stops being painted by its ancestor.
  void onTrackingLayerDetached() {}

  void onTransformChanged();

  /// Runs every time this tracking layer is composited, including frames where
  /// the tracked transform is unchanged.
  void onCompositing() {}
}

@internal
class GeometryTransformTrackingLayer extends OffsetLayer {
  GeometryTransformTrackingLayer();

  RenderObject? renderObject;
  Matrix4 Function()? trackedTransform;
  VoidCallback? onTransformChanged;
  VoidCallback? onCompositing;
  VoidCallback? onDetached;
  Matrix4? _lastTransform;

  @override
  void detach() {
    super.detach();
    onDetached?.call();
  }

  @override
  bool get alwaysNeedsAddToScene => true;

  @override
  void updateSubtreeNeedsAddToScene() {
    // Resolve retained transforms after layout and paint, but before Flutter
    // propagates retained-rendering dirtiness and submits any engine layers.
    // Updating an effect from addToScene is too late: a containing layer may
    // already have been selected for retained rendering.
    final renderObject = this.renderObject;
    if (renderObject != null && renderObject.attached) {
      final currentTransform =
          trackedTransform?.call() ?? renderObject.getTransformTo(null);
      if (!MatrixUtils.matrixEquals(currentTransform, _lastTransform)) {
        onTransformChanged?.call();
        _lastTransform = currentTransform;
      }
      onCompositing?.call();
    }
    super.updateSubtreeNeedsAddToScene();
  }

  @override
  void addToScene(ui.SceneBuilder builder) {
    // Every scene containing glass is built through this layer, before the
    // effect that samples its matte and before the scene is rendered.
    FlutterGpuGeometryRenderer.flushPendingSubmissions();
  }
}

/// Remembers whether a glass layer polled its shapes' transforms while the
/// current frame painted, so its compositing hook can skip a second poll.
///
/// Nothing between paint and compositing in one frame moves a render object,
/// so that poll would only find the transforms paint just recorded.
@internal
class FramePollMarker {
  bool _polled = false;

  /// Whether this frame's paint already polled.
  bool get polledThisFrame => _polled;

  /// Records a poll made during the current frame's paint. Polls outside a
  /// frame, such as `toImage` captures, are not recorded.
  void markPolled() {
    if (_polled ||
        SchedulerBinding.instance.schedulerPhase !=
            SchedulerPhase.persistentCallbacks) {
      return;
    }
    _polled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) => _polled = false);
  }
}

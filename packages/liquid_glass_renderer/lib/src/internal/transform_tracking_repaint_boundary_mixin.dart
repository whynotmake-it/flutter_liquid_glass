import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
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
  void addToScene(ui.SceneBuilder builder) {}
}

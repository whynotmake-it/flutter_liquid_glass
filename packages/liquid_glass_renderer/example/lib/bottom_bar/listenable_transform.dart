import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Signature for [ListenableTransform.transform].
typedef SizedTransform = Matrix4 Function(Size size);

/// Applies [transform] to its child at paint time and repaints whenever
/// [listenable] notifies, without rebuilding or re-laying out anything.
///
/// Hit testing follows the transform.
class ListenableTransform extends SingleChildRenderObjectWidget {
  const ListenableTransform({
    required this.listenable,
    required this.transform,
    super.child,
    super.key,
  });

  final Listenable listenable;

  /// The transform for the child's current size, read on every paint.
  final SizedTransform transform;

  @override
  RenderListenableTransform createRenderObject(BuildContext context) =>
      RenderListenableTransform(listenable: listenable, transform: transform);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderListenableTransform renderObject,
  ) {
    renderObject
      ..listenable = listenable
      ..transform = transform;
  }
}

class RenderListenableTransform extends RenderProxyBox {
  RenderListenableTransform({
    required this._listenable,
    required this._transform,
  });

  Listenable _listenable;
  Listenable get listenable => _listenable;
  set listenable(Listenable value) {
    if (identical(value, _listenable)) return;
    if (attached) {
      _listenable.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _listenable = value;
    markNeedsPaint();
  }

  SizedTransform _transform;
  SizedTransform get transform => _transform;
  set transform(SizedTransform value) {
    if (identical(value, _transform)) return;
    _transform = value;
    markNeedsPaint();
  }

  Matrix4 get _matrix => _transform(size);

  @override
  bool get alwaysNeedsCompositing => child != null;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _listenable.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _listenable.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) {
      layer = null;
      return;
    }
    final matrix = _matrix;
    final det = matrix.determinant();
    if (det == 0 || !det.isFinite) {
      layer = null;
      return;
    }
    layer = context.pushTransform(
      needsCompositing,
      offset,
      matrix,
      super.paint,
      oldLayer: layer is TransformLayer ? layer! as TransformLayer : null,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return result.addWithPaintTransform(
      transform: _matrix,
      position: position,
      hitTest: (result, position) =>
          super.hitTestChildren(result, position: position),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.multiply(_matrix);
  }
}

/// Scales by [scaleX] and [scaleY] (default [scaleX]) about [center].
Matrix4 scaleAbout(Offset center, double scaleX, [double? scaleY]) =>
    Matrix4.translationValues(center.dx, center.dy, 0)
      ..scaleByDouble(scaleX, scaleY ?? scaleX, 1, 1)
      ..translateByDouble(-center.dx, -center.dy, 0, 1);

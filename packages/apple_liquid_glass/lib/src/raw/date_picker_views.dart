part of 'date_picker.dart';

/// The states of the header's parts, one controller for each part's input
/// region.
final class _HeaderStates {
  final WidgetStatesController title = WidgetStatesController();
  final WidgetStatesController previous = WidgetStatesController();
  final WidgetStatesController next = WidgetStatesController();

  void dispose() {
    title.dispose();
    previous.dispose();
    next.dispose();
  }
}

/// A repaint boundary that is also a build scope of its own, as a
/// [LayoutBuilder] is: a rebuild of its subtree lays out and repaints
/// from here down, where the overlay's [LayoutBuilder] above would lay
/// itself out and repaint the overlay's box around it.
class _ScopedRepaintBoundary extends ConstrainedLayoutBuilder<BoxConstraints> {
  const _ScopedRepaintBoundary({required super.builder});

  @override
  RenderAbstractLayoutBuilderMixin<BoxConstraints, RenderBox>
  createRenderObject(BuildContext context) => _RenderScopedRepaintBoundary();
}

class _RenderScopedRepaintBoundary extends RenderBox
    with
        RenderObjectWithChildMixin<RenderBox>,
        RenderObjectWithLayoutCallbackMixin,
        RenderAbstractLayoutBuilderMixin<BoxConstraints, RenderBox> {
  @override
  bool get isRepaintBoundary => true;

  // A layout marks its render object for paint; this one paints nothing
  // but its child at its origin, so a layout that keeps its size and its
  // child leaves the paint to whatever below it changed (a change below
  // marks this boundary on its own).
  bool _keepsPaint = false;

  @override
  void markNeedsPaint() {
    if (_keepsPaint) {
      _keepsPaint = false;
      return;
    }
    super.markNeedsPaint();
  }

  @override
  void performLayout() {
    final constraints = this.constraints;
    final before = hasSize ? size : null;
    final childBefore = this.child;
    runLayoutCallback();
    final child = this.child;
    if (child != null) {
      child.layout(constraints, parentUsesSize: true);
      size = constraints.constrain(child.size);
    } else {
      size = constraints.biggest;
    }
    _keepsPaint = size == before && identical(child, childBefore);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      child?.hitTest(result, position: position) ?? false;

  @override
  void paint(PaintingContext context, Offset offset) {
    _keepsPaint = false;
    final child = this.child;
    if (child != null) context.paintChild(child, offset);
  }
}

/// Paints its child clipped [inset] inside its left and right edges, but
/// takes hits and bounds semantics in its whole box: the outer days'
/// targets reach past the grid that the paging months must not paint
/// beyond.
class _PageClip extends SingleChildRenderObjectWidget {
  const _PageClip({required this.inset, super.child});

  final double inset;

  @override
  _RenderPageClip createRenderObject(BuildContext context) =>
      _RenderPageClip(inset);
}

class _RenderPageClip extends RenderProxyBox {
  _RenderPageClip(this._inset);

  final double _inset;

  final LayerHandle<ClipRectLayer> _clip = LayerHandle<ClipRectLayer>();

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) {
      _clip.layer = null;
      return;
    }
    _clip.layer = context.pushClipRect(
      needsCompositing,
      offset,
      Rect.fromLTRB(_inset, 0, size.width - _inset, size.height),
      super.paint,
      oldLayer: _clip.layer,
    );
  }

  @override
  Rect? describeApproximatePaintClip(RenderObject child) => Offset.zero & size;

  @override
  void dispose() {
    _clip.layer = null;
    super.dispose();
  }
}

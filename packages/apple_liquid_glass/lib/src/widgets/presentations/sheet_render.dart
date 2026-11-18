part of 'sheet.dart';

/// Lays the sheet out as tall as its frame and draws it moved, scaled and
/// clipped to its body by the frame, laying out again only when its height
/// changes.
class _SheetBox extends SingleChildRenderObjectWidget {
  const _SheetBox({required this.frame, required super.child});

  final ValueListenable<_Frame> frame;

  @override
  _RenderSheetBox createRenderObject(BuildContext context) =>
      _RenderSheetBox(frame);
}

class _RenderSheetBox extends RenderProxyBox {
  _RenderSheetBox(this._frame);

  // The view's own notifier, which lives as long as the view.
  final ValueListenable<_Frame> _frame;

  double _laidOut = -1;
  final _clip = LayerHandle<ClipRSuperellipseLayer>();

  void _changed() {
    if (_frame.value.height != _laidOut) {
      markNeedsLayout();
    } else {
      markNeedsPaint();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _frame.addListener(_changed);
  }

  @override
  void detach() {
    _frame.removeListener(_changed);
    super.detach();
  }

  @override
  void dispose() {
    _clip.layer = null;
    super.dispose();
  }

  @override
  bool get alwaysNeedsCompositing => child != null;

  @override
  void performLayout() {
    size = constraints.biggest;
    final h = _frame.value.height;
    _laidOut = h;
    child?.layout(BoxConstraints.tight(Size(size.width, math.max(0, h))));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    final frame = _frame.value;
    return result.addWithPaintTransform(
      transform: frame.transform,
      position: position,
      hitTest: (result, local) =>
          frame.body.contains(local) && child.hitTest(result, position: local),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.multiply(_frame.value.transform);
  }

  // The glass renderer places a resting sheet's backdrop pass from its
  // ancestors' clips, as Impeller sizes the pass; without this clip the
  // sheet's glass sits off by the sheet's inset at rest.
  @override
  Rect? describeApproximatePaintClip(RenderObject child) {
    final frame = _frame.value;
    return MatrixUtils.transformRect(frame.transform, frame.body.outerRect);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    final frame = _frame.value;
    context.pushTransform(needsCompositing, offset, frame.transform, (
      context,
      offset,
    ) {
      _clip.layer = context.pushClipRSuperellipse(
        needsCompositing,
        offset,
        Offset.zero & child.size,
        frame.body,
        (context, offset) => context.paintChild(child, offset),
        oldLayer: _clip.layer,
      );
    });
  }
}

/// A touch on the sheet as it reaches the sheet, before any gesture in it:
/// the press that swells the sheet, a tap on its top band, and the stamp a
/// drag the content's scrollable hands on happens at.
final class _SheetTouch extends Interaction {
  _SheetTouch(this.sheet) : super(role: InteractionRole.observer);

  final _SheetViewState sheet;

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput():
        sheet._down(input);
      case PointerMoveInput():
        sheet._move(input);
      case PointerUpInput(:final pointer, :final time):
        sheet._up(pointer, time, lifted: true);
      case PointerCancelInput(:final pointer, :final time):
        sheet._up(pointer, time, lifted: false);
      default:
        break;
    }
    return InteractionUpdate.none;
  }
}

abstract final class _SheetLook {
  /// The radius of the top corners, in the sheet's unscaled points.
  static const double topRadius = 38;

  static const double dimmingOpacity = 0.2;

  /// The grabber's size in unscaled points.
  static const Size grabberSize = Size(60, 4);

  /// The distance from the sheet's top edge to the grabber's center.
  static const double grabberOffset = 8;
}

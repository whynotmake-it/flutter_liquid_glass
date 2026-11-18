import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';

/// Shows or hides [child] as a listenable value changes, without building.
///
/// UIKit: `isHidden` and `isUserInteractionEnabled` on a view. SwiftUI: an
/// `opacity(0)` with `allowsHitTesting(false)` and
/// `accessibilityHidden(true)`. Flutter: `Visibility` whose `visible` is a
/// listenable.
///
/// While [visible] is false the child is not painted, takes no hits and
/// contributes no semantics, unless [maintainPaint], [maintainInteractivity]
/// or [maintainSemantics] keeps that part; semantics kept for a child that
/// takes no hits offer no actions, as under `IgnorePointer`. The child stays
/// built and laid out either way, so switching costs a paint and a
/// semantics update, never a build or a layout. Several of them in a
/// `Stack`, given values that select one each (such as `MotionSelection`s of
/// one state), switch between subtrees: the shown one is chosen when the
/// frame paints, so a value the frame's resolve phase changes shows in that
/// frame.
///
/// Focus and tickers are not affected: a hidden child keeps a focused node
/// and runs its animations.
class MotionVisibility extends SingleChildRenderObjectWidget {
  /// Shows [child] while [visible] is true.
  const MotionVisibility({
    required this.visible,
    this.maintainPaint = false,
    this.maintainInteractivity = false,
    this.maintainSemantics = false,
    super.child,
    super.key,
  });

  /// Whether the child is shown.
  final ValueListenable<bool> visible;

  /// Whether a hidden child is still painted.
  final bool maintainPaint;

  /// Whether a hidden child still takes hits.
  final bool maintainInteractivity;

  /// Whether a hidden child still contributes semantics.
  final bool maintainSemantics;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderVisibility(
    visible,
    maintainPaint: maintainPaint,
    maintainInteractivity: maintainInteractivity,
    maintainSemantics: maintainSemantics,
  );

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    final visibility = renderObject as _RenderVisibility;
    visibility.visible = visible;
    visibility.maintainPaint = maintainPaint;
    visibility.maintainInteractivity = maintainInteractivity;
    visibility.maintainSemantics = maintainSemantics;
  }
}

class _RenderVisibility extends RenderProxyBox {
  _RenderVisibility(
    this._visible, {
    required this._maintainPaint,
    required this._maintainInteractivity,
    required this._maintainSemantics,
  });

  ValueListenable<bool> _visible;
  ValueListenable<bool> get visible => _visible;
  set visible(ValueListenable<bool> value) {
    if (identical(value, _visible)) return;
    if (attached) _visible.removeRenderListener(_changed);
    _visible = value;
    if (attached) _visible.addRenderListener(_changed);
    _changed();
  }

  bool _maintainPaint;
  bool get maintainPaint => _maintainPaint;
  set maintainPaint(bool value) {
    if (value == _maintainPaint) return;
    _maintainPaint = value;
    markNeedsPaint();
  }

  bool _maintainInteractivity;
  bool get maintainInteractivity => _maintainInteractivity;
  set maintainInteractivity(bool value) {
    if (value == _maintainInteractivity) return;
    _maintainInteractivity = value;
    markNeedsSemanticsUpdate();
  }

  bool _maintainSemantics;
  bool get maintainSemantics => _maintainSemantics;
  set maintainSemantics(bool value) {
    if (value == _maintainSemantics) return;
    _maintainSemantics = value;
    markNeedsSemanticsUpdate();
  }

  bool _shown = true;

  void _changed() {
    final shown = _visible.value;
    if (shown == _shown) return;
    _shown = shown;
    if (!_maintainPaint) markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _visible.addRenderListener(_changed);
    _shown = _visible.value;
  }

  @override
  void detach() {
    _visible.removeRenderListener(_changed);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_shown || _maintainPaint) super.paint(context, offset);
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!_shown && !_maintainInteractivity) return false;
    return super.hitTest(result, position: position);
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (_shown || _maintainSemantics) super.visitChildrenForSemantics(visitor);
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config.isBlockingUserActions = !_shown && !_maintainInteractivity;
  }
}

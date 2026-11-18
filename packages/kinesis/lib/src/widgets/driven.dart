import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';

/// Drives any chain of single-child render-object widgets from motion
/// values without building.
///
/// UIKit: setting layer properties every frame. SwiftUI: an `Animatable`
/// modifier. Flutter: `AnimatedBuilder` without the build.
///
/// [template] returns the chain, such as `Padding(padding: ..., child:
/// ClipRRect(borderRadius: ...))`, whose innermost child is null; [child]
/// goes there. Its render objects are made once. Whenever the motion
/// values [template] reads change, each level updates its render object
/// before paint, so a frame costs what the changed properties cost (a
/// paint or a layout), never a build. A layout property that the frame's
/// resolve phase changes, such as one read from a `MotionLayout` child's
/// place or from a `MotionMeasure`, is laid out again in that frame. The
/// chain keeps its shape: the same widget types at the same depths. Under
/// a muted `TickerMode` it stops following.
class MotionDriven extends RenderObjectWidget {
  /// Creates a driven chain around [child].
  const MotionDriven({required this.template, this.child, super.key});

  /// Returns the chain of single-child render-object widgets to drive.
  final SingleChildRenderObjectWidget Function() template;

  /// The widget inside the chain.
  final Widget? child;

  @override
  RenderObjectElement createElement() => _MotionDrivenElement(this);

  // The chain's widgets are never mounted: this widget stands for them, and
  // makes and updates their render objects as their own elements would.
  static RenderObject _make(RenderObjectWidget level, BuildContext context) =>
      level.createRenderObject(context);

  static void _update(
    RenderObjectWidget level,
    BuildContext context,
    RenderObject renderObject,
  ) => level.updateRenderObject(context, renderObject);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      (context as _MotionDrivenElement)._create();

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (context as _MotionDrivenElement)._apply();
}

class _MotionDrivenElement extends RenderObjectElement {
  _MotionDrivenElement(MotionDriven super.widget);

  late MotionSelection<SingleChildRenderObjectWidget> _chain = MotionSelection(
    (widget as MotionDriven).template,
  );
  final List<RenderObjectWithChildMixin<RenderObject>> _levels = [];
  Element? _child;
  bool _following = false;

  RenderObject _create() {
    final levels = _widgets(_chain.value);
    for (final level in levels) {
      final renderObject = MotionDriven._make(level, this);
      assert(
        renderObject is RenderObjectWithChildMixin<RenderObject>,
        '${level.runtimeType} makes a ${renderObject.runtimeType}, which '
        'cannot hold the rest of a MotionDriven chain.',
      );
      final holder = renderObject as RenderObjectWithChildMixin<RenderObject>;
      if (_levels.isNotEmpty) _levels.last.child = holder as RenderObject;
      _levels.add(holder);
    }
    return _levels.first as RenderObject;
  }

  void _apply() {
    final levels = _widgets(_chain.value);
    assert(
      levels.length == _levels.length,
      'A MotionDriven template changed its depth from ${_levels.length} to '
      '${levels.length}.',
    );
    for (var i = 0; i < levels.length; i++) {
      MotionDriven._update(levels[i], this, _levels[i] as RenderObject);
    }
  }

  static List<SingleChildRenderObjectWidget> _widgets(
    SingleChildRenderObjectWidget top,
  ) {
    final levels = <SingleChildRenderObjectWidget>[];
    Widget? level = top;
    while (level != null) {
      assert(
        level is SingleChildRenderObjectWidget,
        'A MotionDriven template holds a ${level.runtimeType}; it may only '
        'chain single-child render-object widgets.',
      );
      final widget = level as SingleChildRenderObjectWidget;
      levels.add(widget);
      level = widget.child;
    }
    return levels;
  }

  void _follow() {
    final following = TickerMode.valuesOf(this).enabled;
    if (following == _following) return;
    _following = following;
    if (following) {
      _chain.addRenderListener(_apply);
      _apply();
    } else {
      _chain.removeRenderListener(_apply);
    }
  }

  @override
  void mount(Element? parent, Object? newSlot) {
    super.mount(parent, newSlot);
    _follow();
    _child = updateChild(_child, (widget as MotionDriven).child, null);
  }

  @override
  void update(MotionDriven newWidget) {
    if (_following) _chain.removeRenderListener(_apply);
    _chain = MotionSelection(newWidget.template);
    if (_following) _chain.addRenderListener(_apply);
    super.update(newWidget);
    _child = updateChild(_child, newWidget.child, null);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _follow();
  }

  @override
  void unmount() {
    if (_following) _chain.removeRenderListener(_apply);
    _following = false;
    final inner = _levels.skip(1).toList();
    super.unmount();
    // The framework disposes the top of the chain, which has an element;
    // the levels below it have none.
    for (final level in inner) {
      (level as RenderObject).dispose();
    }
  }

  @override
  void visitChildren(ElementVisitor visitor) {
    final child = _child;
    if (child != null) visitor(child);
  }

  @override
  void forgetChild(Element child) {
    assert(child == _child, 'Only the child of a MotionDriven is forgotten.');
    _child = null;
    super.forgetChild(child);
  }

  @override
  void insertRenderObjectChild(RenderObject child, Object? slot) {
    _levels.last.child = child;
  }

  @override
  void moveRenderObjectChild(
    RenderObject child,
    Object? oldSlot,
    Object? newSlot,
  ) {
    assert(false, 'A MotionDriven child never moves.');
  }

  @override
  void removeRenderObjectChild(RenderObject child, Object? slot) {
    _levels.last.child = null;
  }
}

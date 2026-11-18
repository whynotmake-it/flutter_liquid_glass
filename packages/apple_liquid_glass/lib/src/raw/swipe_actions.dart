import 'package:apple_liquid_glass/motions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/widgets.dart';

/// Builds one action of a swiped row from [details]; it runs when the row
/// builds, not when the action's states change.
typedef GlassSwipeActionBuilder = Widget Function(
  BuildContext context,
  GlassSwipeActionDetails details,
);

/// What a [GlassSwipeActionBuilder] builds an action from.
@immutable
final class GlassSwipeActionDetails {
  /// Describes action [index].
  const GlassSwipeActionDetails({required this.index, required this.states});

  /// Which action this is: 0 is the first, outermost at the trailing edge.
  final int index;

  /// The action's states as they change: pressed, hovered and focused.
  /// A look hands it to what draws the focus ring and the hover response,
  /// which follow it without a rebuild.
  final ValueListenable<Set<WidgetState>> states;
}

/// A row that a finger swipes toward its trailing edge to show its
/// actions, with the behavior of iOS 27's swipe actions and no look of its
/// own: [actionBuilder] and [overswipe] decide how the actions look.
///
/// UIKit: `trailingSwipeActionsConfigurationForRowAt`. SwiftUI:
/// `swipeActions(edge: .trailing)`. Flutter: `Slidable` of
/// flutter_slidable.
///
/// The row follows the finger on a rubber band and settles open or closed
/// where the release projects; the actions sit against its trailing edge,
/// the first outermost, each as wide as [actionBuilder] lays it out, all
/// as tall as the row. With [fullSwipe] a swipe past
/// [SwipeActionsMotion.fullSwipeShare] of the row performs the first
/// action, as UIKit's `performsFirstActionWithFullSwipe`. In a
/// right-to-left context the row swipes the other way and the actions
/// open on the left.
///
/// A tap on the open row away from its actions closes it, and the row's
/// content does not hear it; so does a scroll of the scroll view around
/// the row, or a swipe of another row of the same `SwipeGroup`.
/// Accessibility offers the actions as custom actions of the row, as UIKit
/// does, which is also how iOS's Full Keyboard Access reaches them. A
/// closed row's actions take no input and are no Tab stops; an open row's
/// actions are buttons labelled [actionLabels], one Tab stop each, before
/// the row, and Space and Enter press the focused one.
class RawGlassSwipeActions extends StatefulWidget {
  /// Creates a row that shows its actions when swiped.
  const RawGlassSwipeActions({
    required this.actionLabels,
    required this.onAction,
    required this.actionBuilder,
    required this.child,
    this.overswipe,
    this.fullSwipe = true,
    this.statesController,
    super.key,
  });

  /// What each action is called, for accessibility; their count is the
  /// count of actions.
  final List<String> actionLabels;

  /// Called with the index of the action pressed, or performed by a full
  /// swipe or accessibility.
  final ValueChanged<int> onAction;

  /// Builds each action.
  final GlassSwipeActionBuilder actionBuilder;

  /// What shows between the actions and the row's trailing edge when the
  /// row is pulled further than its actions reach, or null for nothing.
  /// It is laid out as large as the row and clipped to that space.
  final Widget? overswipe;

  /// Whether a full swipe performs the first action.
  final bool fullSwipe;

  /// Where the row publishes its states (dragged), or null. The row is
  /// its only writer: what else writes to it is written over.
  final WidgetStatesController? statesController;

  /// The row.
  final Widget child;

  @override
  State<RawGlassSwipeActions> createState() => _RawGlassSwipeActionsState();
}

/// The swiped rows of one list section, of which one is open at a time: a
/// [RawGlassSwipeActions] in [child] that starts to open closes the one
/// open before it.
///
/// `GlassListSection` and `GlassSliverListSection` group their rows this
/// way; a list of an app's own groups its rows with one.
class SwipeGroup extends StatefulWidget {
  /// Groups the swiped rows in [child].
  const SwipeGroup({required this.child, super.key});

  /// The subtree holding the rows.
  final Widget child;

  @override
  State<SwipeGroup> createState() => _SwipeGroupState();
}

class _SwipeGroupState extends State<SwipeGroup> {
  final _open = _OpenRow();

  @override
  Widget build(BuildContext context) =>
      _OpenRowScope(open: _open, child: widget.child);
}

class _OpenRowScope extends InheritedWidget {
  const _OpenRowScope({required this.open, required super.child});

  final _OpenRow open;

  static _OpenRow? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_OpenRowScope>()?.open;

  @override
  bool updateShouldNotify(_OpenRowScope oldWidget) => false;
}

final class _OpenRow {
  _RawGlassSwipeActionsState? _row;

  void opened(_RawGlassSwipeActionsState row) {
    final open = _row;
    if (open != null && !identical(open, row)) open.close();
    _row = row;
  }

  void closed(_RawGlassSwipeActionsState row) {
    if (identical(_row, row)) _row = null;
  }
}

class _RawGlassSwipeActionsState extends State<RawGlassSwipeActions> {
  final _motion = SwipeActionsMotion();
  late final _offset = _motion.select((m) => m.offset.valueAt(m.now));
  late final DragInteraction _drag = DragInteraction(
    axis: Axis.horizontal,
    onStart: _start,
    onUpdate: _update,
    onEnd: _end,
    onCancel: _cancel,
  );
  late final List<Interaction> _interactions = [
    _drag,
    _CloseTap(closesAt: _closesAt, onTap: close),
  ];
  final List<List<Interaction>> _presses = [];
  final List<GlobalKey> _actionKeys = [];
  final _swipeKey = GlobalKey(debugLabel: 'swipe');
  final _zones = InputZonesController<int>();
  _OpenRow? _group;
  ScrollPosition? _scroll;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _group = _OpenRowScope.maybeOf(context);
    final scroll = Scrollable.maybeOf(context)?.position;
    if (!identical(scroll, _scroll)) {
      _scroll?.isScrollingNotifier.removeListener(_scrolled);
      _scroll = scroll;
      scroll?.isScrollingNotifier.addListener(_scrolled);
    }
  }

  @override
  void dispose() {
    _scroll?.isScrollingNotifier.removeListener(_scrolled);
    _group?.closed(this);
    _zones.dispose();
    super.dispose();
  }

  void _scrolled() {
    if (_scroll?.isScrollingNotifier.value ?? false) close();
  }

  /// Settles the row closed.
  void close() {
    _group?.closed(this);
    _motion.moveTo(_motion.clock.now, 0);
  }

  void _start(DragInteractionDetails details) {
    _group?.opened(this);
    _motion.grab(details.time);
    _update(details);
  }

  void _update(DragInteractionDetails details) =>
      _motion.drag(details.time, details.translation.dx);

  void _end(DragInteractionDetails details) {
    final choice = _motion.release(
      details.time,
      details.velocity.dx,
      canPerform: widget.actionLabels.isNotEmpty,
    );
    switch (choice) {
      case ProjectionExited():
        widget.onAction(0);
      case ProjectionStop(:final value):
        if (value == 0) _group?.closed(this);
    }
  }

  void _cancel(double t) => _motion.moveTo(t, 0);

  void _perform(int index) {
    close();
    widget.onAction(index);
  }

  bool _closesAt(Offset position) {
    final swipe = _swipeKey.currentContext?.findRenderObject();
    return swipe is _RenderSwipe && swipe.closesAt(position);
  }

  // A press on an action yields to the row's drag once the finger moves.
  List<Interaction> _pressOf(int index) {
    while (_presses.length <= index) {
      final i = _presses.length;
      _presses.add([
        PressInteraction(
          role: InteractionRole.content,
          onTap: (t) => _perform(i),
        ),
      ]);
    }
    return _presses[index];
  }

  GlobalKey _actionKey(int index) {
    while (_actionKeys.length <= index) {
      _actionKeys.add(GlobalKey(debugLabel: 'swipe action'));
    }
    return _actionKeys[index];
  }

  // Where action [index] is drawn now, cut to the row: nowhere while the
  // row is closed, so a closed row's actions take no input and no focus.
  InputZoneFrame? _frameOf(int index) {
    if (_offset.value == 0 || index >= _actionKeys.length) return null;
    final row = _swipeKey.currentContext?.findRenderObject();
    final action = _actionKeys[index].currentContext?.findRenderObject();
    if (row is! RenderBox ||
        action is! RenderBox ||
        !row.hasSize ||
        !action.hasSize ||
        !action.attached) {
      return null;
    }
    final rect = MatrixUtils.transformRect(
      action.getTransformTo(row),
      Offset.zero & action.size,
    );
    return InputZoneFrame(rect.intersect(Offset.zero & row.size));
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    _drag.mirrored = rtl;
    _motion.fullSwipe = widget.fullSwipe;
    final labels = widget.actionLabels;
    final overswipe = widget.overswipe;
    final swipe = _Swipe(
      key: _swipeKey,
      motion: _motion,
      offset: _offset,
      rtl: rtl,
      children: [
        widget.child,
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = labels.length - 1; i >= 0; i--)
              KeyedSubtree(
                key: _actionKey(i),
                child: ExcludeSemantics(
                  child: widget.actionBuilder(
                    context,
                    GlassSwipeActionDetails(
                      index: i,
                      states: _zones.states(i),
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (overswipe != null) overswipe,
      ],
    );
    // The row's region neither activates nor adjusts, so the actions'
    // zones inside it keep their Space and Enter.
    return MotionScope(
      motion: _motion,
      child: InputRegion(
        interactions: _interactions,
        statesController: widget.statesController,
        semantics: SemanticsProperties(
          customSemanticsActions: {
            for (final (i, label) in labels.indexed)
              CustomSemanticsAction(label: label): () => widget.onAction(i),
          },
        ),
        child: InputZones<int>(
          zones: [
            for (final (i, label) in labels.indexed)
              InputZone<int>(
                id: i,
                interactions: _pressOf(i),
                semantics: SemanticsProperties(label: label, button: true),
              ),
          ],
          frameOf: _frameOf,
          frames: _offset,
          controller: _zones,
          excludeChildSemantics: false,
          child: swipe,
        ),
      ),
    );
  }
}

/// A tap on an open row away from its actions: it closes the row. The row
/// takes such a touch from its content, which it does not hit-test while
/// open, so the content does not hear it.
final class _CloseTap extends Interaction {
  _CloseTap({required this.closesAt, required this.onTap})
    : super(role: InteractionRole.content);

  final bool Function(Offset position) closesAt;
  final VoidCallback onTap;

  int? _pointer;

  @override
  bool accepts(PointerDownInput down) =>
      super.accepts(down) && closesAt(down.position);

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput() when accepts(input):
        _pointer = input.pointer;
      case PointerUpInput() when input.pointer == _pointer:
        _pointer = null;
        onTap();
        return const InteractionUpdate(recognizes: true);
      case PointerCancelInput() when input.pointer == _pointer:
        _pointer = null;
        return const InteractionUpdate(fails: true);
      default:
    }
    return InteractionUpdate.none;
  }
}

/// The row and its actions: the row laid out in full and drawn moved by the
/// offset, the actions at their own width against its trailing edge, and
/// the overswipe, when there is one, in the space past them.
class _Swipe extends MultiChildRenderObjectWidget {
  const _Swipe({
    required this.motion,
    required this.offset,
    required this.rtl,
    required super.children,
    super.key,
  });

  final SwipeActionsMotion motion;
  final MotionSelection<double> offset;
  final bool rtl;

  @override
  MultiChildRenderObjectElement createElement() => _SwipeElement(this);

  @override
  _RenderSwipe createRenderObject(BuildContext context) =>
      _RenderSwipe(motion: motion, offset: offset, rtl: rtl);

  @override
  void updateRenderObject(BuildContext context, _RenderSwipe renderObject) {
    renderObject.motion = motion;
    renderObject.offset = offset;
    renderObject.rtl = rtl;
  }
}

// The actions of a closed row are not drawn; like an IndexedStack's
// hidden children, they are offstage to finders.
class _SwipeElement extends MultiChildRenderObjectElement {
  _SwipeElement(_Swipe super.widget);

  @override
  void debugVisitOnstageChildren(ElementVisitor visitor) {
    final open = (renderObject as _RenderSwipe)._open;
    var first = true;
    for (final child in children) {
      if (first || open) visitor(child);
      first = false;
    }
  }
}

class _SwipeParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderSwipe extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SwipeParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SwipeParentData> {
  _RenderSwipe({
    required this.motion,
    required this._offset,
    required this._rtl,
  });

  SwipeActionsMotion motion;

  MotionSelection<double> _offset;
  MotionSelection<double> get offset => _offset;
  set offset(MotionSelection<double> value) {
    if (identical(value, _offset)) return;
    if (attached) _offset.removeRenderListener(markNeedsPaint);
    _offset = value;
    if (attached) _offset.addRenderListener(markNeedsPaint);
    markNeedsPaint();
  }

  bool _rtl;
  bool get rtl => _rtl;
  set rtl(bool value) {
    if (value == _rtl) return;
    _rtl = value;
    markNeedsPaint();
  }

  RenderBox get _row => firstChild!;
  RenderBox get _actions => childAfter(_row)!;
  RenderBox? get _overswipe => childAfter(_actions);

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _offset.addRenderListener(markNeedsPaint);
  }

  @override
  void detach() {
    _offset.removeRenderListener(markNeedsPaint);
    super.detach();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SwipeParentData) {
      child.parentData = _SwipeParentData();
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _row.getMinIntrinsicWidth(height);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _row.getMaxIntrinsicWidth(height);

  @override
  double computeMinIntrinsicHeight(double width) =>
      _row.getMinIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _row.getMaxIntrinsicHeight(width);

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      _row.getDryLayout(constraints);

  @override
  void performLayout() {
    _row.layout(constraints, parentUsesSize: true);
    size = _row.size;
    _actions.layout(
      BoxConstraints.tightFor(height: size.height),
      parentUsesSize: true,
    );
    _overswipe?.layout(BoxConstraints.tight(size));
    motion.rowWidth = size.width;
    motion.actionsWidth = _actions.size.width;
  }

  /// Where the row is drawn along its width.
  double get _shift => _rtl ? -_offset.value : _offset.value;

  Rect get _actionsRect {
    final shift = _shift;
    final left = _rtl ? shift - _actions.size.width : size.width + shift;
    return Rect.fromLTWH(left, 0, _actions.size.width, size.height);
  }

  bool get _open => _offset.value != 0;

  /// Whether a touch at [position] is a tap that closes the row: the row is
  /// open and the touch is away from its actions.
  bool closesAt(Offset position) => _open && !_actionsRect.contains(position);

  @override
  bool hitTestSelf(Offset position) => _open;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (!_open) return _row.hitTest(result, position: position);
    final actions = _actionsRect;
    if (!actions.contains(position)) return false;
    return result.addWithPaintOffset(
      offset: actions.topLeft,
      position: position,
      hitTest: (result, local) => _actions.hitTest(result, position: local),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final shift = _shift;
    if (shift == 0) {
      context.paintChild(_row, offset);
      return;
    }
    context.pushClipRect(needsCompositing, offset, Offset.zero & size, (
      context,
      offset,
    ) {
      final actions = _actionsRect;
      final overswipe = _overswipe;
      if (overswipe != null) {
        final rest = _rtl
            ? Rect.fromLTRB(0, 0, actions.left, size.height)
            : Rect.fromLTRB(actions.right, 0, size.width, size.height);
        if (!rest.isEmpty) {
          context.pushClipRect(
            needsCompositing,
            offset,
            rest,
            (context, offset) => context.paintChild(overswipe, offset),
          );
        }
      }
      context.paintChild(_actions, offset + actions.topLeft);
      context.paintChild(_row, offset + Offset(shift, 0));
    });
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final at = identical(child, _row)
        ? Offset(_shift, 0)
        : identical(child, _actions)
        ? _actionsRect.topLeft
        : Offset.zero;
    transform.translateByDouble(at.dx, at.dy, 0, 1);
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) => visitor(_row);
}

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/src/widgets/control_states.dart';
import 'package:kinesis/src/widgets/haptics.dart';
import 'package:kinesis/src/widgets/input_intents.dart';
import 'package:kinesis/src/widgets/input_shared.dart';
import 'package:kinesis/src/widgets/input_target.dart';
import 'package:kinesis/src/widgets/keyboard_use.dart';
import 'package:kinesis/src/widgets/pointer_line.dart';
import 'package:kinesis/src/widgets/scope.dart';

/// Turns pointer, keyboard, hover and accessibility input into the input
/// of its [interactions].
///
/// UIKit: a control's touch tracking with its gesture recognizers. SwiftUI:
/// a view's gestures. Flutter: `RawGestureDetector` with `Focus`,
/// `MouseRegion` and `Semantics`.
///
/// Every event of a touch the region follows is stamped on the clock of the
/// nearest [MotionClockScope] at its own time stamp, the release included,
/// and the release carries the velocity of the base `VelocityTracker`
/// estimated with the release's own sample, so a live drag ends as its
/// replay does. The region joins the gesture arena only for touches an
/// interaction accepts, so one that takes nothing never blocks a scroll,
/// and it holds or gives up a touch as its [InteractionSession] decides,
/// including the scroll delay of a control inside a scroll view. When an
/// interaction [Interaction.activates] (a press, a tap), the accessibility
/// tap and the `ActivateIntent` and `ButtonActivateIntent` of the app's
/// shortcuts activate it: Space and Enter under a `WidgetsApp`, as for
/// Flutter's own buttons. An app remaps the keys with `Shortcuts` and
/// replaces what activation does with an `Actions` above the region, since
/// the region's actions are `Action.overridable`. A region activates only
/// while its own focus node has the primary focus: in a region inside
/// another (a switch in a pressable row), the focused inner region handles
/// Space and Enter, and the outer one only when it is focused itself; an
/// override above both hears the inner region's activation. When an
/// interaction [Interaction.adjusts] (a slider, a stepper), the region
/// binds the keys of [AdjustValueIntent.defaultShortcuts] around its focus
/// and gives accessibility increase and decrease; both arrive as
/// [AdjustInput]s, and only those its [adjustRange] allows are offered. A
/// region registers an action only for what one of its interactions takes,
/// so a region that neither activates nor adjusts (a drag region around a
/// row of focusable items) leaves Space, Enter and the value keys to the
/// focus below it.
///
/// The other interactions hear each event of a touch on the pointer's
/// route, where Flutter's gesture recognizers hear it, so a recognizer
/// inside the region (a scroll view in a sheet) that passes its slop on
/// the same event as a drag of the region takes the touch, as it would
/// from a recognizer around it. An interaction of the
/// [InteractionRole.observer] role hears every touch it accepts at once
/// and to its end, outside the gesture arena, as the event reaches the
/// region, as a `Listener` does: before the recognizers inside hear it. A
/// control that must follow a finger another gesture may win (a hold that
/// opens a menu over a button) observes it.
///
/// A region none of whose interactions [Interaction.takesPointers] is
/// transparent to pointers, its child included, as under `IgnorePointer`,
/// and keeps its focus, keys and semantics.
///
/// Presses of the secondary button reach the interactions that accept them
/// (`SecondaryClickInteraction`). When an interaction
/// [Interaction.opensContextMenu], the region binds
/// [ContextMenuIntent.defaultShortcuts] (the context menu key, Shift+F10)
/// around its focus and turns the intent into a [ContextMenuInput] at its
/// centre, under the same focus rule as activation. The scroll wheel
/// reaches them as [PointerScrollInput]s when one [Interaction.takesWheel],
/// and the region then keeps it from the scroll views around it.
///
/// With a [port] it also hears the touches another region hands on to it
/// (`InputPort.forward`), mapped into its own coordinates. It publishes its
/// states to [statesController]: the [states] its control says, disabled
/// while it is not [enabled], and while it is the states input keeps
/// (pressed, hovered, dragged, and focused while the focus should show:
/// when the keyboard was used last, as `InkWell` does, so a tap that
/// focuses lights no ring).
class InputRegion extends StatefulWidget {
  /// Creates a region whose [interactions] answer input on [child].
  const InputRegion({
    required this.interactions,
    required this.child,
    this.statesController,
    this.states = const {},
    this.focusShows,
    this.feedback,
    this.enabled = true,
    this.mouseCursor,
    this.focusNode,
    this.autofocus = false,
    this.semantics,
    this.port,
    this.reach = PressReach.box,
    this.adjustRange,
    super.key,
  });

  /// The interactions; when two recognize on one input, the first wins.
  /// Their owner makes them once.
  final List<Interaction> interactions;

  /// The widget the region covers.
  final Widget child;

  /// Where the region publishes its states, or null. The region is its
  /// only writer: what else writes to it is written over at the next
  /// change.
  final WidgetStatesController? statesController;

  /// What the region's control says of itself, such as selected: never
  /// disabled, which is [enabled], nor a state input keeps.
  final Set<WidgetState> states;

  /// Whether the focused state shows, for a control whose focus is not the
  /// region's, such as a text field's editor; null shows the region's own
  /// focus while the keyboard is in use.
  final bool? focusShows;

  /// The haptic for an event, or null for none.
  ///
  /// The region plays it as the event happens, never for a keyboard or
  /// accessibility input, and plays none under a [MotionHapticScope] that
  /// turns haptics off. A haptic for something that is not an event of the
  /// interactions goes through [MotionHapticPlay.play], under the same
  /// rules.
  final MotionHaptic? Function(InteractionEvent event)? feedback;

  /// Whether the region takes input; disabling it ends a touch.
  final bool enabled;

  /// The cursor over the region, or null for the default.
  ///
  /// A `WidgetStateMouseCursor` is resolved against the states the region
  /// publishes: its [states], disabled, and pressed, hovered, focused and
  /// dragged. The default is `WidgetStateMouseCursor.adaptiveClickable` when an
  /// interaction [Interaction.activates] or [Interaction.adjusts] (a
  /// button, a switch, a slider: the click cursor on the web, the basic
  /// arrow elsewhere, as native desktop controls keep it, and while
  /// disabled), `MouseCursor.defer` otherwise, which leaves the cursor to
  /// what lies under the region.
  final MouseCursor? mouseCursor;

  /// The region's focus node, or null for its own.
  ///
  /// The region's own node is skipped in focus traversal when no
  /// interaction activates or adjusts, since such a region takes no key:
  /// Tab never stops on it. A given node keeps its own
  /// `FocusNode.skipTraversal`.
  final FocusNode? focusNode;

  /// Whether the region takes focus when it first appears.
  final bool autofocus;

  /// What accessibility reads for the region, or null for a node with only
  /// what the region does: the properties of a `Semantics` widget, written
  /// on the region's own node, whose rectangle is the region's hit area.
  ///
  /// ```dart
  /// InputRegion(
  ///   interactions: [press],
  ///   semantics: const SemanticsProperties(label: 'Play', button: true),
  ///   child: icon,
  /// )
  /// ```
  ///
  /// What the region does is its own and is written over what this says:
  /// whether it is enabled and focused, the tap of a region whose
  /// interaction [Interaction.activates], increase and decrease of one that
  /// [Interaction.adjusts]. A `Semantics` below the region joins the same
  /// node; one around a region that activates or adjusts is a node of its
  /// own, so a label put there is read apart from the region's actions.
  /// `InputZone.semantics` is the same for a zone.
  final SemanticsProperties? semantics;

  /// Where touches handed on from another region arrive, or null.
  final InputPort? port;

  /// Where the region takes pointers and where a press on it holds the
  /// finger, stamped on every touch's [PointerDownInput.reach].
  ///
  /// A region smaller than the reach's [PressReach.minimumHit] takes
  /// pointers in a rectangle of that size centred on its box, without
  /// changing its layout or its paint: a 28 point switch with a 44 by 44
  /// minimum is pressed by a finger up to 8 points above or below it, as
  /// UIKit's is. A pointer in the extension reaches the region's
  /// interactions at its real position; the child is hit at the nearest
  /// point of the box. The accessibility rectangle grows the same way when
  /// the region owns its semantics node: a control that adds its own
  /// `Semantics` puts it below the region, so its flags join the region's
  /// node.
  ///
  /// Flutter delivers a pointer only through ancestors whose own hit test
  /// contains it: where a parent clips or stops at its box, as a `Row`
  /// sized to the region does, the extension beyond the parent takes
  /// nothing. Give such a parent room, as Material's buttons do with their
  /// tap target padding.
  final PressReach reach;

  /// Which ways the value of a region that adjusts can move now, or null
  /// when it always can.
  ///
  /// At the maximum the region offers no accessibility increase and takes
  /// none of the keys that raise the value (they reach what lies around
  /// the region), at the minimum the same for lowering it. The region
  /// follows the listenable without a rebuild, so a value that reaches its
  /// end by a drag or a glide updates its semantics in the same frame.
  final ValueListenable<AdjustRange>? adjustRange;

  @override
  State<InputRegion> createState() => _InputRegionState();
}

class _InputRegionState extends State<InputRegion> {
  FocusNode? _ownFocus;
  WidgetStatesController? _ownStates;
  MouseCursor? _builtCursor;
  NavigationMode? _navigation;
  _RenderRegion? _box;
  late final _RegionTarget _target = _RegionTarget(this);
  late final _RegionLine _line = _RegionLine(this);

  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  // The clock of the motions around the region, so a touch's stamps and
  // the motions it drives share one time.
  late MotionClock _clock;

  WidgetStatesController get _states =>
      widget.statesController ?? (_ownStates ??= WidgetStatesController());

  @override
  void initState() {
    super.initState();
    _publish();
    _states.addListener(_statesChanged);
    FocusManager.instance.addHighlightModeListener(_highlightModeChanged);
    KeyboardUse.changes.addListener(_publish);
    _line.port = widget.port;
    widget.adjustRange?.addListener(_rangeChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _clock = MotionClockScope.of(context);
    final navigation = MediaQuery.maybeNavigationModeOf(context);
    if (navigation == _navigation) return;
    _navigation = navigation;
    _publish();
  }

  @override
  void didUpdateWidget(InputRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    _target.interactions = widget.interactions;
    if (oldWidget.enabled != widget.enabled) {
      widget.enabled ? _target.enable() : _target.disable();
    }
    _line.port = widget.port;
    if (oldWidget.adjustRange != widget.adjustRange) {
      oldWidget.adjustRange?.removeListener(_rangeChanged);
      widget.adjustRange?.addListener(_rangeChanged);
      _rangeChanged();
    }
    if (oldWidget.statesController != widget.statesController) {
      (oldWidget.statesController ?? _ownStates)?.removeListener(
        _statesChanged,
      );
      if (widget.statesController != null) {
        _ownStates?.dispose();
        _ownStates = null;
      }
      _states.addListener(_statesChanged);
    }
    _publish();
  }

  @override
  void dispose() {
    _line.dispose();
    widget.adjustRange?.removeListener(_rangeChanged);
    _target.dispose();
    _states.removeListener(_statesChanged);
    FocusManager.instance.removeHighlightModeListener(_highlightModeChanged);
    KeyboardUse.changes.removeListener(_publish);
    _ownStates?.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  void _focusChanged(bool focused) {
    _target.hasFocus = focused;
    _box?.markNeedsSemanticsUpdate();
  }

  void _highlightModeChanged(FocusHighlightMode mode) => _publish();

  void _publish() => publishStates(
    _states,
    shownStates(
      said: widget.states,
      enabled: widget.enabled,
      live: _target.live,
      focusShows: widget.focusShows,
      navigation: _navigation,
    ),
  );

  MouseCursor get _cursor => resolveCursor(
    widget.mouseCursor,
    clickable: _target.acts,
    states: _states.value,
  );

  // Only a cursor that changes with the states rebuilds the region.
  void _statesChanged() {
    if (mounted && _builtCursor != null && _cursor != _builtCursor) {
      setState(() {});
    }
  }

  void _rangeChanged() => _box?.markNeedsSemanticsUpdate();

  @override
  Widget build(BuildContext context) {
    final target = _target;
    return _Region(
      state: this,
      described: (
        reach: widget.reach,
        takesPointers: target.takesPointers,
        enabled: widget.enabled,
        activates: target.activates,
        adjusts: target.adjusts,
      ),
      child: Actions(
        actions: target.actions,
        child: Shortcuts(
          shortcuts: target.shortcuts(
            Directionality.maybeOf(context) ?? TextDirection.ltr,
          ),
          child: Focus(
            focusNode: _focus,
            autofocus: widget.autofocus,
            canRequestFocus: widget.enabled,
            // The region's box says whether it is focusable, in the frame
            // that disables it: Focus learns it a frame later.
            includeSemantics: false,
            skipTraversal: widget.focusNode == null ? !target.acts : null,
            onFocusChange: _focusChanged,
            child: MouseRegion(
              cursor: _builtCursor = _cursor,
              onEnter: (event) =>
                  target.hover(event.localPosition, inside: true),
              onHover: (event) =>
                  target.hover(event.localPosition, inside: true),
              onExit: (event) =>
                  target.hover(event.localPosition, inside: false),
              child: ContestScope(
                contested:
                    ContestScope.of(context) || target.contendsWithControls,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _RegionTarget extends InputTarget {
  _RegionTarget(this.state) : super(state.widget.interactions);

  final _InputRegionState state;

  @override
  BuildContext get context => state.context;

  @override
  bool get mounted => state.mounted;

  @override
  MotionClock get clock => state._clock;

  @override
  PointerLine<InputTarget> get line => state._line;

  @override
  bool get enabled => state.widget.enabled;

  @override
  void publish() => state._publish();

  @override
  MotionHaptic? feedback(InteractionEvent event) =>
      state.widget.feedback?.call(event);

  @override
  AdjustRange get range => state.widget.adjustRange?.value ?? AdjustRange.open;

  @override
  FocusNode get focusNode => state._focus;

  @override
  bool get focusable => enabled;

  @override
  NavigationMode? get navigation => state._navigation;
}

final class _RegionLine extends PointerLine<InputTarget> {
  _RegionLine(this.state);

  final _InputRegionState state;

  @override
  RenderBox? get box => state._box;

  @override
  PressReach get reach => state.widget.reach;

  @override
  InputTarget get base => state._target;
}

typedef _Described = ({
  PressReach reach,
  bool takesPointers,
  bool enabled,
  bool activates,
  bool adjusts,
});

class _Region extends SingleChildRenderObjectWidget {
  const _Region({
    required this.state,
    required this.described,
    required super.child,
  });

  final _InputRegionState state;
  final _Described described;

  SemanticsProperties get _properties =>
      state.widget.semantics ?? const SemanticsProperties();

  @override
  _RenderRegion createRenderObject(BuildContext context) {
    final box = _RenderRegion(
      state,
      described,
      properties: _properties,
      textDirection: Directionality.maybeOf(context),
    );
    state._box = box;
    return box;
  }

  @override
  void updateRenderObject(BuildContext context, _RenderRegion renderObject) {
    renderObject.state = state;
    renderObject.described = described;
    renderObject.properties = _properties;
    renderObject.textDirection = Directionality.maybeOf(context);
    state._box = renderObject;
  }
}

class _RenderRegion extends RenderProxyBox with SemanticsAnnotationsMixin {
  _RenderRegion(
    this.state,
    this._described, {
    required SemanticsProperties properties,
    required TextDirection? textDirection,
  }) {
    initSemanticsAnnotations(
      properties: properties,
      container: _acts,
      explicitChildNodes: false,
      excludeSemantics: false,
      blockUserActions: false,
      localeForSubtree: null,
      textDirection: textDirection,
    );
  }

  _InputRegionState state;

  _Described _described;
  _Described get described => _described;
  set described(_Described value) {
    if (value == _described) return;
    // The accessibility rectangle is laid out with the box.
    if (value.reach != _described.reach) markNeedsLayout();
    _described = value;
    container = _acts;
    markNeedsSemanticsUpdate();
  }

  // A region that acts is one node of its own, as a button is, disabled
  // too: otherwise its label and actions merge into what is around it.
  bool get _acts => _described.activates || _described.adjusts;

  Rect get hitArea => _described.reach.takes(Offset.zero & size);

  @override
  Rect get semanticBounds => hitArea;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!_described.takesPointers) return false;
    if (size.contains(position)) {
      return super.hitTest(result, position: position);
    }
    if (!hitArea.contains(position)) {
      return false;
    }
    // The child is hit where the box is nearest; the events keep their real
    // position, since the transform to this box is unchanged.
    hitTestChildren(
      result,
      position: Offset(
        position.dx.clamp(0, _inside(size.width)),
        position.dy.clamp(0, _inside(size.height)),
      ),
    );
    result.add(BoxHitTestEntry(this, position));
    return true;
  }

  static double _inside(double extent) =>
      math.max(0, extent - precisionErrorTolerance);

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (_described.enabled) state._line.pointer(event);
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    state._target.describe(config);
  }
}

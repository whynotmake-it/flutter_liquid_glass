import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/src/widgets/haptics.dart';
import 'package:kinesis/src/widgets/input_intents.dart';
import 'package:kinesis/src/widgets/input_shared.dart';
import 'package:kinesis/src/widgets/keyboard_use.dart';
import 'package:kinesis/src/widgets/pointer_line.dart';

/// One thing a person acts on, as an input host keeps it: a session of
/// interactions with its keys, its states, its haptics and its timed
/// reactions.
///
/// `InputRegion` hosts one; each zone of an `InputZones` is one, and so is
/// the box of the zones itself. A host says where its target is and what it
/// may do now; what a target does with an input is the same in every host.
/// Its pointers reach it through its [line].
@internal
abstract class InputTarget {
  /// Creates a target over [interactions].
  InputTarget(List<Interaction> interactions)
    : _interactions = interactions,
      session = InteractionSession(interactions) {
    _bind();
  }

  /// The element the target belongs to: where its haptics find their scope
  /// and its actions their overrides.
  BuildContext get context;

  /// Whether [context] is still in the tree.
  bool get mounted;

  /// The clock that stamps the target's inputs.
  MotionClock get clock;

  /// The line that brings the target its pointers.
  PointerLine<InputTarget> get line;

  /// Whether the target takes input now.
  bool get enabled;

  /// A position of the target's own coordinates in global ones; by default
  /// the [line]'s box coordinates.
  Offset toGlobal(Offset local) => line.box?.localToGlobal(local) ?? local;

  /// [input], given in the coordinates of the [line]'s box, in the
  /// target's own.
  InteractionInput local(InteractionInput input) => input;

  /// Writes the target's states where its host keeps them: what the host
  /// says of it with its [live] states.
  void publish();

  /// The haptic for [event], or null.
  MotionHaptic? feedback(InteractionEvent event);

  /// Which ways a value the target adjusts can move now.
  AdjustRange get range => AdjustRange.open;

  /// The target's centre in the coordinates of the [line]'s box: where a
  /// context menu asked for by a key opens; by default the box's centre.
  Offset get centre => switch (line.box) {
    final box? when box.hasSize => box.size.center(Offset.zero),
    _ => Offset.zero,
  };

  /// The target's focus node, or null when it takes no focus.
  FocusNode? get focusNode => null;

  /// Whether [focusNode] may take focus now, the nodes around it aside.
  bool get focusable => false;

  /// How the device moves focus, when known.
  NavigationMode? get navigation => null;

  /// The actions the host adds to the target's own.
  Map<Type, Action<Intent>> get moreActions => const {};

  /// The interactions' session.
  InteractionSession session;

  List<Interaction> _interactions;

  /// The interactions. Other ones end the touches the target follows and
  /// start a new [session].
  List<Interaction> get interactions => _interactions;
  set interactions(List<Interaction> value) {
    if (listEquals(value, _interactions)) return;
    line.drop(this, PointerCancelReason.platform);
    _interactions = value;
    session = InteractionSession(value);
    _bind();
    _scheduleDue();
  }

  void _bind() {
    for (final interaction in _interactions) {
      interaction.bindRegion(toGlobal);
    }
  }

  /// Whether an interaction activates: Space, Enter and the accessibility
  /// tap reach the target.
  bool get activates => _interactions.any((i) => i.activates);

  /// Whether an interaction adjusts a value: the value keys and the
  /// accessibility increase and decrease reach the target.
  bool get adjusts => _interactions.any((i) => i.adjusts);

  /// Whether an interaction opens a context menu.
  bool get opensMenu => _interactions.any((i) => i.opensContextMenu);

  /// Whether an interaction takes the scroll wheel.
  bool get takesWheel => _interactions.any((i) => i.takesWheel);

  /// Whether an interaction takes pointers.
  bool get takesPointers => _interactions.any((i) => i.takesPointers);

  /// Whether an interaction contends with the controls inside the target.
  bool get contendsWithControls =>
      _interactions.any((i) => i.contendsWithControls);

  /// Whether the target takes a key: it [activates] or [adjusts].
  bool get acts => activates || adjusts;

  /// Carries out what the session made of an input: plays the events'
  /// haptics, publishes pressed and dragged, and waits for the next timed
  /// reaction.
  void answer(SessionOutput output) {
    for (final event in output.events) {
      play(event);
    }
    if (mounted) {
      _pressed = _interactions.any((i) => i.pressed);
      _dragged = _interactions.any((i) => i.dragged);
      publish();
    }
    _scheduleDue();
  }

  bool _pressed = false;
  bool _dragged = false;

  /// The states input keeps of the target.
  Set<WidgetState> get live => {
    if (_pressed) WidgetState.pressed,
    if (_dragged) WidgetState.dragged,
    if (_hovering) WidgetState.hovered,
    if (_hasFocus && KeyboardUse.inUse) WidgetState.focused,
  };

  /// Plays the haptic the host picks for [event]; an activation by a key
  /// or by accessibility plays none.
  void play(InteractionEvent event) {
    if (event is ActivationEvent && event.source != ActivationSource.pointer) {
      return;
    }
    if (!mounted) return;
    final haptic = feedback(event);
    if (haptic != null) playHaptic(context, haptic);
  }

  /// Hands the session an input that is no touch (a key, an accessibility
  /// action, hover, the wheel), given in the coordinates of the [line]'s
  /// box, and answers it.
  void input(InteractionInput input) {
    if (!enabled) return;
    dispatchInput(
      input,
      () => clock.input(
        input.time,
        () => answer(session.handle(local(input))),
      ),
    );
  }

  /// Activates the target for a key or an accessibility tap.
  void activate(ActivationSource source) =>
      input(ActivateInput(time: clock.now, source: source));

  /// Steps the target's value for a key or an accessibility action.
  void adjust(ValueCommand command, ActivationSource source) => input(
    AdjustInput(time: clock.now, command: command, source: source),
  );

  /// Asks for the target's context menu at its [centre].
  void openMenu() => input(ContextMenuInput(time: clock.now, position: centre));

  bool _hovering = false;

  Offset? _mouseAt;

  /// Whether the mouse is over the target while it takes input.
  bool get hovering => _hovering;

  /// The mouse is over the target at [position], or left it.
  void hover(Offset position, {required bool inside}) {
    _mouseAt = inside ? position : null;
    if (!enabled) return;
    _hovering = inside;
    if (!mounted) return;
    publish();
    input(
      PointerHoverInput(time: clock.now, position: position, inside: inside),
    );
  }

  /// The target takes input again: a mouse resting over it hovers it once
  /// the frame is done, as Flutter enters a region that a frame puts under a
  /// resting mouse.
  void enable() {
    if (_mouseAt == null) return;
    // After the frame: hover publishes states this frame's builds read, and
    // Flutter's mouse tracker enters a region a frame adds then too.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_mouseAt case final position? when !_hovering && enabled) {
        hover(position, inside: true);
      }
    });
  }

  /// The target stopped taking input: its touches end, and what waited on
  /// the mouse resting over it (a dwell) hears the mouse leave, since a
  /// disabled target hears no more hover.
  void disable() {
    line.drop(this, PointerCancelReason.disabled);
    if (!_hovering) return;
    _hovering = false;
    final time = clock.now;
    clock.input(
      time,
      () => answer(
        session.handle(
          PointerHoverInput(time: time, position: Offset.zero, inside: false),
        ),
      ),
    );
  }

  bool _hasFocus = false;

  /// Whether [focusNode] has the focus.
  bool get hasFocus => _hasFocus;
  set hasFocus(bool value) {
    _hasFocus = value;
    publish();
  }

  late final Action<ActivateIntent> _activateAction =
      Action<ActivateIntent>.overridable(
        defaultAction: _Activate<ActivateIntent>(this),
        context: context,
      );

  late final Action<ButtonActivateIntent> _buttonAction =
      Action<ButtonActivateIntent>.overridable(
        defaultAction: _Activate<ButtonActivateIntent>(this),
        context: context,
      );

  late final Action<AdjustValueIntent> _adjustAction =
      Action<AdjustValueIntent>.overridable(
        defaultAction: _Adjust(this),
        context: context,
      );

  late final Action<ContextMenuIntent> _menuAction =
      Action<ContextMenuIntent>.overridable(
        defaultAction: _ContextMenu(this),
        context: context,
      );

  ({bool activates, bool adjusts, bool opensMenu})? _actionsFor;
  late Map<Type, Action<Intent>> _actions;

  /// The actions around the target's focus, the same map until what the
  /// interactions take changes.
  ///
  /// There is an action only for what an interaction takes. A registered
  /// action, even a disabled one, answers its intent for the focus below
  /// and overrides the overridable actions there: a target that takes no
  /// key, around a row of focusable parts, would take theirs.
  Map<Type, Action<Intent>> get actions {
    final takes = (
      activates: activates,
      adjusts: adjusts,
      opensMenu: opensMenu,
    );
    if (takes == _actionsFor) return _actions;
    _actionsFor = takes;
    return _actions = {
      if (takes.activates) ...{
        ActivateIntent: _activateAction,
        ButtonActivateIntent: _buttonAction,
      },
      if (takes.adjusts) AdjustValueIntent: _adjustAction,
      if (takes.opensMenu) ContextMenuIntent: _menuAction,
      ...moreActions,
    };
  }

  /// The keys the target binds around its focus: the value keys when it
  /// [adjusts], the context menu keys when it [opensMenu].
  Map<ShortcutActivator, Intent> shortcuts(TextDirection direction) {
    final adjust = adjusts
        ? AdjustValueIntent.defaultShortcuts(
            direction,
            navigation ?? NavigationMode.traditional,
          )
        : const <ShortcutActivator, Intent>{};
    if (!opensMenu) return adjust;
    return {...ContextMenuIntent.defaultShortcuts, ...adjust};
  }

  /// Writes what the target can do into its semantics node: enabled,
  /// focus, the tap of one that [activates], increase and decrease of one
  /// that [adjusts], as far as its [range] allows.
  void describe(SemanticsConfiguration config) {
    config.isEnabled = enabled;
    final node = focusNode;
    // From the host's word, not the node's: a Focus sets its node only
    // after the box was described for the frame that disables it.
    if (node != null &&
        focusable &&
        node.ancestors.every((ancestor) => ancestor.descendantsAreFocusable)) {
      config.isFocused = node.hasPrimaryFocus;
      // As Focus does: iOS takes no focus action (flutter/flutter#150030).
      if (defaultTargetPlatform != TargetPlatform.iOS) {
        config.onFocus = node.requestFocus;
      }
    }
    if (!enabled) return;
    if (activates) {
      config.onTap = () => activate(ActivationSource.accessibility);
    }
    if (adjusts) {
      final range = this.range;
      if (range.canIncrease) {
        config.onIncrease = () =>
            adjust(ValueCommand.increase, ActivationSource.accessibility);
      }
      if (range.canDecrease) {
        config.onDecrease = () =>
            adjust(ValueCommand.decrease, ActivationSource.accessibility);
      }
    }
  }

  double? _scheduled;
  VoidCallback? _cancelDue;

  void _scheduleDue() {
    final due = session.nextDue;
    if (due == _scheduled) return;
    _cancelDue?.call();
    _cancelDue = null;
    _scheduled = due;
    if (due == null) return;
    _cancelDue = clock.schedule(due, (time) {
      _scheduled = null;
      _cancelDue = null;
      if (!mounted) return;
      clock.input(time, () => line.due(this, session.advance(time)));
    });
  }

  /// Ends the target's touches and its timed reactions.
  void dispose() {
    line.drop(this, PointerCancelReason.platform);
    _cancelDue?.call();
    _cancelDue = null;
  }
}

class _Activate<I extends Intent> extends _HostAction<I> {
  _Activate(this.target);

  final InputTarget target;

  @override
  bool takes(I intent) => target.enabled && target.activates;

  @override
  bool get focused => target.focusNode?.hasPrimaryFocus ?? false;

  @override
  void run(I intent) => target.activate(ActivationSource.keyboard);
}

class _Adjust extends _HostAction<AdjustValueIntent> {
  _Adjust(this.target);

  final InputTarget target;

  @override
  bool takes(AdjustValueIntent intent) =>
      target.enabled && target.adjusts && target.range.allows(intent.command);

  @override
  bool get focused => true;

  @override
  void run(AdjustValueIntent intent) =>
      target.adjust(intent.command, ActivationSource.keyboard);
}

class _ContextMenu extends _HostAction<ContextMenuIntent> {
  _ContextMenu(this.target);

  final InputTarget target;

  @override
  bool takes(ContextMenuIntent intent) => target.enabled && target.opensMenu;

  @override
  bool get focused => target.focusNode?.hasPrimaryFocus ?? false;

  @override
  void run(ContextMenuIntent intent) => target.openMenu();
}

/// An input host's own action for an intent of the focused host: a
/// region's or a zone's activation.
///
/// Hosts register their actions as `Action.overridable`, so the lookup of
/// an inner host's override finds the action of the host around it. Such an
/// action, reached as the override of another host's, hands the intent
/// back to that host; reached first, it answers only while its own focus
/// node has the primary focus. The focused, innermost host handles the
/// intent, and a host around it handles it only when it is focused itself.
abstract class _HostAction<I extends Intent> extends Action<I> {
  /// Whether the host takes the intent now: it is enabled and one of its
  /// interactions takes it.
  bool takes(I intent);

  /// Whether the host's own focus node has the primary focus.
  bool get focused;

  /// Runs the intent on the host.
  void run(I intent);

  _HostAction<I>? get _inner => switch (callingAction) {
    final _HostAction<I> inner => inner,
    _ => null,
  };

  @override
  bool isEnabled(I intent) {
    if (_inner case final inner?) return inner.isEnabled(intent);
    return focused && takes(intent);
  }

  @override
  Object? invoke(I intent) {
    if (_inner case final inner?) return inner.invoke(intent);
    run(intent);
    return null;
  }
}

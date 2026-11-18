import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/src/widgets/input_shared.dart';
import 'package:kinesis/src/widgets/input_target.dart';

final class _Touch<P extends InputTarget> {
  _Touch(this.down, this.tracker);

  // In the coordinates of the line's box.
  final PointerDownInput down;

  // Null for a touch another region handed on: its release brings its own
  // velocity.
  final VelocityTracker? tracker;

  // Null while only observers hear the touch, and for a touch handed on.
  _ArenaMember? member;

  // The input the pointer's route hands the targets for the event being
  // dispatched, made as the event reached the box.
  InteractionInput? routed;

  InputTarget? base;
  P? part;
  bool baseContends = false;
  bool partContends = false;

  int get pointer => down.pointer;

  bool get contended => baseContends || partContends;

  bool contends(InputTarget target) => identical(target, base)
      ? baseContends
      : identical(target, part) && partContends;

  // Whether target contended until now.
  bool gaveUp(InputTarget target) {
    if (identical(target, base) && baseContends) {
      baseContends = false;
      return true;
    }
    if (identical(target, part) && partContends) {
      partContends = false;
      return true;
    }
    return false;
  }
}

/// The pointers of one render box: turns its pointer events into stamped
/// inputs, keeps the box in the gesture arena, and hands every input to the
/// targets on the touch.
///
/// A touch has up to two targets: the [base], which hears every touch on
/// the box, and the part of type [P] under the finger ([partAt]).
/// `InputRegion` has only a base; in an `InputZones` the parts are the
/// zones and the base is the host's own interactions.
///
/// An interaction of the observer role hears an event as it reaches the
/// box, as a `Listener` does. The others hear it on the pointer's route,
/// where Flutter's recognizers hear it, after the recognizers inside the
/// box: a scroll view inside that passes its slop on the same event takes
/// the touch first, as it would from a recognizer around it. The box stays
/// in the arena for a pointer while a target contends for it, and takes it
/// when one claims.
///
/// The line and its targets do not own each other: the host's state holds
/// both, and each finds the other through it, a target its line through
/// `InputTarget.line` and the line its targets through [base] and
/// [partAt]. While a touch lasts, the line keeps the targets it found at
/// the down on that touch. The host hands every pointer event to the line
/// ([pointer]); the line asks each target's session and gives the answer
/// back to the target (`InputTarget.answer`), which plays the haptics and
/// writes the states. A target calls into the line only to end its touches
/// ([drop]) and to deliver a timed reaction that came due ([due]); keys,
/// hover, the wheel and accessibility reach a target without the line.
///
/// ```text
/// down: host -> pointer -> line: partAt, then for base and part
///         session.observe + session.track, the arena if one contends,
///         target.answer
/// move: host -> pointer -> line: observers hear it (session.observe)
///       arena route -> line: session.track, a sliding finger handed
///         over to the part under it, target.answer
/// up:   as a move, then the touch leaves the route and the line
/// timer or disable: target -> line.due / line.drop -> target.answer
/// ```
@internal
abstract class PointerLine<P extends InputTarget> {
  final Map<int, _Touch<P>> _touches = {};
  final _PointerSpeed _speed = _PointerSpeed();
  InputPort? _port;

  /// The box whose events these are.
  RenderBox? get box;

  /// Where the box takes pointers and where a press on it holds the finger.
  PressReach get reach => PressReach.box;

  /// The target that hears every touch on the box.
  InputTarget get base;

  /// The element of the box.
  BuildContext get context => base.context;

  /// Whether [context] is still in the tree.
  bool get mounted => base.mounted;

  /// The clock that stamps the events.
  MotionClock get clock => base.clock;

  /// The part that takes input at [position], or null.
  P? partAt(Offset position) => null;

  /// Whether a finger slides from part to part: the touch stays in the
  /// arena with no part under it, and moves on to the part it comes over.
  bool get slides => false;

  /// A sliding finger came onto [part], at the down or in a move.
  void slidOnto(P part, double time, {required bool atDown}) {}

  /// Where touches handed on from another region arrive, or null.
  ///
  /// The port attaches after the current frame. The line maps positions
  /// with its box, laid out in the frame that builds it, and the touches
  /// that waited run interactions that may rebuild or lay out, which that
  /// frame's layout and resolve phases do not allow; the clock's coming
  /// phases can run before that layout when the host is built outside a
  /// frame.
  InputPort? get port => _port;
  set port(InputPort? value) {
    if (identical(value, _port)) return;
    _port?.detach(_receive);
    _port = value;
    if (value == null) return;
    // After the frame: a port delivers in the box's coordinates, which the
    // frame's layout gives.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_port, value)) value.attach(_receive);
    });
  }

  /// Lets go of the port.
  void dispose() {
    _port?.detach(_receive);
    _port = null;
  }

  void _receive(PortEvent event) {
    final box = this.box;
    if (box == null || !box.hasSize) return;
    final input = event.input(
      box.globalToLocal,
      size: box.size,
      reach: reach,
      scrollAxes: event.handOff ? _scrollAxesAround(context) : const {},
      contested: ContestScope.of(context, listen: false),
      touchSlop: _touchSlop,
    );
    clock.input(input.time, () {
      switch (input) {
        case PointerDownInput():
          _begin(input, arena: false);
        case PointerMoveInput(:final pointer) ||
            PointerUpInput(:final pointer) ||
            PointerCancelInput(:final pointer):
          final touch = _touches[pointer];
          if (touch == null) return;
          _observe(touch, input);
          _track(touch, input);
        case PointerAcceptedInput() ||
            PointerHoverInput() ||
            PointerScrollInput() ||
            ActivateInput() ||
            AdjustInput() ||
            ContextMenuInput():
          break;
      }
    });
  }

  /// Takes a pointer event of the box: a down, an event of a touch the
  /// line follows, or the wheel.
  void pointer(PointerEvent event) {
    switch (event) {
      case PointerScrollEvent():
        _wheel(event);
      case PointerDownEvent():
      case _ when _touches.containsKey(event.pointer):
        final time = clock.stamp(event.timeStamp);
        clock.input(time, () => _heard(event, time));
      default:
        break;
    }
  }

  void _wheel(PointerScrollEvent event) {
    final base = this.base;
    final target = switch (partAt(event.localPosition)) {
      final part? when part.takesWheel => part,
      _ when base.enabled && base.takesWheel => base,
      _ => null,
    };
    if (target == null) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      if (!target.mounted || event is! PointerScrollEvent) return;
      target.input(
        PointerScrollInput(
          time: clock.stamp(event.timeStamp),
          position: event.localPosition,
          scrollDelta: event.scrollDelta,
          kind: event.kind,
        ),
      );
    });
  }

  /// Whether the line follows a touch.
  bool get touched => _touches.isNotEmpty;

  /// Whether the line follows the touch of [pointer].
  bool follows(int pointer) => _touches.containsKey(pointer);

  /// Takes an event of a touch that came to no box, in global coordinates
  /// on a [screen] of that size: a down starts a touch the line follows
  /// outside the gesture arena, as one handed on through a [port], and the
  /// later events of a touch it follows reach the targets as they happen.
  void captured(PointerEvent event, Size screen) {
    final time = clock.stamp(event.timeStamp);
    clock.input(time, () => _heard(event, time, screen: screen));
  }

  // A [screen] marks a captured event: the touch has no box, no scroll view
  // and no arena around it.
  void _heard(PointerEvent event, double time, {Size? screen}) {
    if (event is PointerDownEvent) {
      final Size size;
      if (screen != null) {
        size = screen;
      } else {
        final box = this.box;
        if (box == null || !box.hasSize) return;
        size = box.size;
      }
      _speed.touched(event.timeStamp);
      final tracker = VelocityTracker.withKind(event.kind);
      tracker.addPosition(event.timeStamp, event.localPosition);
      _begin(
        PointerDownInput(
          time: time,
          pointer: event.pointer,
          position: event.localPosition,
          regionSize: size,
          reach: reach,
          globalPosition: event.position,
          kind: event.kind,
          buttons: event.buttons,
          scrollAxes: screen == null ? _scrollAxesAround(context) : const {},
          contested: screen == null && ContestScope.of(context, listen: false),
          touchSlop: _touchSlop,
        ),
        arena: screen == null,
        tracker: tracker,
      );
      return;
    }
    final touch = _touches[event.pointer];
    if (touch == null) return;
    final InteractionInput input;
    switch (event) {
      case PointerMoveEvent():
        touch.tracker?.addPosition(event.timeStamp, event.localPosition);
        if (mounted) _speed.moved(event, View.of(context).devicePixelRatio);
        input = PointerMoveInput(
          time: time,
          pointer: event.pointer,
          position: event.localPosition,
          regionBox: _regionBox(event, touch, screen),
          globalPosition: event.position,
        );
      case PointerUpEvent():
        _speed.lifted();
        touch.tracker?.addPosition(event.timeStamp, event.localPosition);
        final velocity =
            touch.tracker?.getVelocity().pixelsPerSecond ?? Offset.zero;
        input = PointerUpInput(
          time: time,
          pointer: event.pointer,
          position: event.localPosition,
          regionBox: _regionBox(event, touch, screen),
          velocity: velocity,
          globalPosition: event.position,
          globalVelocity: _globalVector(
            event.transform,
            velocity,
            event.localPosition,
          ),
        );
      case PointerCancelEvent():
        input = PointerCancelInput(
          time: time,
          pointer: event.pointer,
          reason: PointerCancelReason.platform,
        );
      default:
        return;
    }
    _observe(touch, input);
    if (touch.member != null) {
      touch.routed = input;
    } else if (screen != null) {
      _track(touch, input);
    } else if (input is! PointerMoveInput) {
      _touches.remove(touch.pointer);
    }
  }

  double get _touchSlop =>
      MediaQuery.maybeGestureSettingsOf(context)?.touchSlop ?? kTouchSlop;

  // The box as it is now, in the coordinates of [event]'s local position,
  // which a tracked touch keeps from its down.
  Rect _regionBox(PointerEvent event, _Touch<P> touch, Size? screen) {
    if (screen != null) return Offset.zero & screen;
    final box = this.box;
    if (box == null || !box.attached || !box.hasSize) {
      return Offset.zero & touch.down.regionSize;
    }
    final global = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    final toLocal = event.transform;
    return toLocal == null
        ? global
        : MatrixUtils.transformRect(toLocal, global);
  }

  void _begin(
    PointerDownInput down, {
    required bool arena,
    VelocityTracker? tracker,
  }) {
    final pointer = down.pointer;
    if (_touches.containsKey(pointer)) return;
    final base = this.base.enabled ? this.base : null;
    final part = partAt(down.position);
    final touch = _Touch<P>(down, tracker);
    // Both hear the down before either is answered: a target that takes
    // nothing must not give up a touch the other takes.
    final baseAsked = base == null ? null : _ask(base, down);
    if (base != null && baseAsked != null) {
      touch.baseContends = !baseAsked.tracked.reject;
      if (touch.baseContends || base.session.observes(pointer)) {
        touch.base = base;
      }
    }
    final partAsked = part == null ? null : _ask(part, down);
    if (part != null && partAsked != null) {
      touch.partContends = !partAsked.tracked.reject;
      if (touch.partContends || part.session.observes(pointer)) {
        touch.part = part;
      }
    }
    if (touch.base != null || touch.part != null || slides) {
      _touches[pointer] = touch;
      if (arena && (touch.contended || slides)) {
        final member = _ArenaMember(_lost, _accepted);
        touch.member = member;
        member.entry = GestureBinding.instance.gestureArena.add(
          pointer,
          member,
        );
        GestureBinding.instance.pointerRouter.addRoute(pointer, _route);
      }
    }
    if (base != null && baseAsked != null) {
      base.answer(baseAsked.observed);
      _settle(touch, base, baseAsked.tracked);
    }
    if (part != null && partAsked != null) {
      part.answer(partAsked.observed);
      if (slides && touch.partContends) {
        slidOnto(part, down.time, atDown: true);
      }
      _settle(touch, part, partAsked.tracked);
    }
  }

  static ({SessionOutput observed, SessionOutput tracked}) _ask(
    InputTarget target,
    PointerDownInput down,
  ) {
    final at = target.local(down);
    return (
      observed: target.session.observe(at),
      tracked: target.session.track(at),
    );
  }

  void _observe(_Touch<P> touch, InteractionInput input) {
    final pointer = touch.pointer;
    if (touch.base case final base? when base.session.observes(pointer)) {
      base.answer(base.session.observe(base.local(input)));
    }
    if (touch.part case final part? when part.session.observes(pointer)) {
      part.answer(part.session.observe(part.local(input)));
    }
  }

  void _route(PointerEvent event) {
    final touch = _touches[event.pointer];
    final input = touch?.routed;
    if (touch == null || input == null) return;
    touch.routed = null;
    clock.input(input.time, () => _track(touch, input));
  }

  void _track(_Touch<P> touch, InteractionInput input) {
    switch (input) {
      case PointerMoveInput():
        if (touch.base case final base?) {
          _settle(touch, base, base.session.track(base.local(input)));
        }
        if (slides) {
          final under = partAt(input.position);
          if (under != null && !identical(under, touch.part)) {
            _handOver(touch, input, under);
            return;
          }
        }
        if (touch.part case final part?) {
          _settle(touch, part, part.session.track(part.local(input)));
        }
      case PointerUpInput() || PointerCancelInput():
        if (touch.base case final base?) {
          _settle(touch, base, base.session.track(base.local(input)));
        }
        if (touch.part case final part?) {
          _settle(touch, part, part.session.track(part.local(input)));
        }
        if (identical(_touches[touch.pointer], touch)) {
          _touches.remove(touch.pointer);
        }
        _leave(touch);
      case PointerDownInput() ||
          PointerAcceptedInput() ||
          PointerHoverInput() ||
          PointerScrollInput() ||
          ActivateInput() ||
          AdjustInput() ||
          ContextMenuInput():
        break;
    }
  }

  void _handOver(_Touch<P> touch, PointerMoveInput move, P to) {
    final from = touch.part;
    touch.part = null;
    touch.partContends = false;
    if (from != null) {
      from.answer(
        from.session.handle(
          PointerCancelInput(
            time: move.time,
            pointer: touch.pointer,
            reason: PointerCancelReason.taken,
          ),
        ),
      );
    }
    final down = touch.down;
    final output = to.session.handle(
      to.local(
        down.copyWith(
          time: move.time,
          position: move.position,
          globalPosition: move.globalPosition,
        ),
      ),
    );
    if (output.reject) {
      to.answer(output);
      return;
    }
    touch.part = to;
    touch.partContends = true;
    slidOnto(to, move.time, atDown: false);
    _settle(touch, to, output);
  }

  // Acts on what a target made of an input of the touch: a claim takes the
  // pointer in the arena, and the box leaves the arena when the last
  // target that contended gives the touch up.
  void _settle(_Touch<P> touch, InputTarget target, SessionOutput output) {
    if (output.claim) {
      touch.member?.entry?.resolve(GestureDisposition.accepted);
    }
    if (output.reject && touch.gaveUp(target) && !touch.contended && !slides) {
      touch.member?.entry?.resolve(GestureDisposition.rejected);
    }
    target.answer(output);
  }

  // The box is out of the gesture arena for the touch.
  void _leave(_Touch<P> touch) {
    if (touch.member == null) return;
    touch.member = null;
    touch.routed = null;
    GestureBinding.instance.pointerRouter.removeRoute(touch.pointer, _route);
  }

  void _accepted(int pointer) {
    final touch = _touches[pointer];
    if (touch == null || touch.member == null) return;
    final time = clock.now;
    final input = PointerAcceptedInput(time: time, pointer: pointer);
    clock.input(time, () {
      if (touch.base case final base?) {
        _settle(touch, base, base.session.handle(input));
      }
      if (touch.part case final part?) {
        _settle(touch, part, part.session.handle(input));
      }
    });
  }

  void _lost(int pointer) {
    final touch = _touches[pointer];
    if (touch == null || touch.member == null) return;
    _leave(touch);
    final base = touch.base;
    final part = touch.part;
    touch.baseContends = false;
    touch.partContends = false;
    // Observers keep hearing a touch another gesture took.
    if (base != null && !base.session.observes(pointer)) touch.base = null;
    if (part != null && !part.session.observes(pointer)) touch.part = null;
    if (touch.base == null && touch.part == null) _touches.remove(pointer);
    final time = clock.now;
    base?.answer(base.session.lost(pointer, time));
    part?.answer(part.session.lost(pointer, time));
  }

  /// Ends every touch [target] is on, for it alone: it hears a cancel for
  /// [reason], and the box leaves the arena for a touch nothing else
  /// contends for.
  void drop(InputTarget target, PointerCancelReason reason) {
    for (final touch in _touches.values.toList()) {
      if (identical(touch.base, target)) {
        touch.base = null;
        touch.baseContends = false;
      } else if (identical(touch.part, target)) {
        touch.part = null;
        touch.partContends = false;
      } else {
        continue;
      }
      if (!touch.contended && !slides) {
        final entry = touch.member?.entry;
        _leave(touch);
        entry?.resolve(GestureDisposition.rejected);
        if (touch.base == null && touch.part == null) {
          _touches.remove(touch.pointer);
        }
      }
      target.answer(
        target.session.handle(
          PointerCancelInput(
            time: clock.now,
            pointer: touch.pointer,
            reason: reason,
          ),
        ),
      );
    }
  }

  /// Acts on what a timed reaction of [target] made, for the touch it
  /// contends for when there is one: a hold that comes due claims the
  /// pointer.
  void due(InputTarget target, SessionOutput output) {
    for (final touch in _touches.values) {
      if (!touch.contends(target)) continue;
      _settle(touch, target, output);
      return;
    }
    target.answer(output);
  }
}

/// An input host's place in the gesture arena for one pointer: it waits for
/// the host to resolve it and tells the host when it won the pointer and
/// when another gesture took it.
final class _ArenaMember extends GestureArenaMember {
  /// Creates a member that calls [onRejected] when it loses its pointer and
  /// [onAccepted] when it wins it.
  _ArenaMember(this.onRejected, this.onAccepted);

  /// Called with the pointer another gesture took.
  final void Function(int pointer) onRejected;

  /// Called with the pointer the arena gave the host.
  final void Function(int pointer) onAccepted;

  /// The arena entry, once the member joined.
  GestureArenaEntry? entry;

  @override
  void acceptGesture(int pointer) => onAccepted(pointer);

  @override
  void rejectGesture(int pointer) => onRejected(pointer);
}

/// The vector [local] at [at] in an event's local coordinates, mapped to
/// global ones through the inverse of the event's [transform].
Offset _globalVector(Matrix4? transform, Offset local, Offset at) {
  if (transform == null) return local;
  final inverse = Matrix4.tryInvert(transform);
  if (inverse == null) return local;
  return MatrixUtils.transformPoint(inverse, at + local) -
      MatrixUtils.transformPoint(inverse, at);
}

/// The axes of the scroll views around [context].
Set<Axis> _scrollAxesAround(BuildContext context) {
  final axes = <Axis>{};
  context.visitAncestorElements((element) {
    if (element case StatefulElement(state: final ScrollableState state)) {
      axes.add(state.position.axis);
    }
    return true;
  });
  return axes;
}

/// Tells the frame cadence how fast a followed pointer moves.
final class _PointerSpeed {
  Duration? _movedAt;

  /// A pointer touched at [stamp].
  void touched(Duration stamp) {
    _movedAt = stamp;
    FrameCadence.instance.input(changed: true);
  }

  /// A followed pointer lifted.
  void lifted() => FrameCadence.instance.input(changed: true);

  /// A followed pointer moved; [devicePixelRatio] turns its travel into
  /// device pixels.
  void moved(PointerMoveEvent event, double devicePixelRatio) {
    final last = _movedAt;
    _movedAt = event.timeStamp;
    if (last == null) return;
    final seconds = (event.timeStamp - last).inMicroseconds / 1e6;
    if (seconds <= 0) return;
    FrameCadence.instance.input(
      pixelsPerSecond: event.delta.distance * devicePixelRatio / seconds,
    );
  }
}

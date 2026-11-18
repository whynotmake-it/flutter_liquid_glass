import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:kinesis/src/motion/clock.dart';
import 'package:kinesis/src/motion/frame_cadence.dart';
import 'package:kinesis/src/motion/loop.dart';
import 'package:kinesis/src/motion/part.dart';
import 'package:kinesis/src/motion/selection.dart';
import 'package:kinesis/src/motion/transaction.dart';

/// Drops a reaction scheduled with [Motion.at] before it runs.
typedef MotionCancel = void Function();

/// A tree of parts with one time cursor and one timeline of delayed
/// reactions: the shape of every measured motion.
///
/// Every command takes an explicit time and every read answers at [now], so
/// a motion built from commands is a pure function of its stamped inputs: a
/// test makes one, calls it at recorded times and reads it, with no clock
/// and no widget.
///
/// ```dart
/// class CardMotion extends Motion {
///   late final offset = own(MotionValue(Offset.zero));
///   late final opacity = own(
///     MotionValue(0.0),
///     rest: () => MotionRest.opacity,
///   );
///
///   void show(double t) {
///     opacity.retarget(t, 1);
///     at(t + 0.2, (t) => offset.retarget(t, const Offset(0, 40)));
///   }
/// }
/// ```
///
/// A part registers with [own] and rests within the tolerance given there,
/// its own otherwise. Rest is per part and declared, never a change:
/// [settle] declares each part that rests from its own rest time and leaves
/// the others moving.
///
/// On screen the clock steps the root of the tree while something looks at
/// it (a selection made with [MotionSelect.select] has listeners, or a
/// `MotionScope` holds it): every frame it advances the root to the frame's
/// time and, once the root [isSettled], settles it and stops stepping it
/// until a command or a reaction moves it again.
abstract class Motion extends MotionPart {
  /// Creates a motion stepped by [clock] when it is a root on screen
  /// ([MotionClock.instance] when null).
  Motion({this._clock});

  final MotionClock? _clock;
  final List<MotionPart> _parts = [];
  final List<double Function()?> _rests = [];
  final List<_Reaction> _reactions = [];
  late final _RootFollower _follower = _RootFollower(this);
  MotionTraits? _traits;
  int _retains = 0;
  double _now = 0;
  bool _advancing = false;

  Motion get _root {
    var motion = this;
    while (true) {
      final owner = motion.owner;
      if (owner == null) return motion;
      motion = owner;
    }
  }

  /// The clock that steps the root on screen; the ambient forms of its
  /// values read it too. Explicit-time commands never do.
  ///
  /// A widget that owns the motion takes the time of its commands from
  /// here (`clock.now`), not from [MotionClock.instance], so a motion made
  /// with a clock of its own is commanded on that clock; a `MotionLoop`
  /// without a rate of its own steps at this clock's frame rate.
  MotionClock get clock => _root._clock ?? MotionClock.instance;

  /// The motion preferences of the root: those of the `MotionScope` that
  /// holds it, [MotionTraits.platform] otherwise.
  MotionTraits get traits => _root._traits ?? MotionTraits.platform();

  /// Sets the root's preferences: `MotionScope` writes those of its
  /// context; a host that holds a motion without one, as a render object
  /// does, writes `MotionTraitsOverride.of` itself.
  set traits(MotionTraits? traits) => _root._traits = traits;

  /// Keeps the root on the clock while retained, as `MotionScope` does.
  @internal
  void retain() {
    final root = _root;
    root._retains++;
    root._wake();
  }

  /// Ends a [retain].
  @internal
  void unretain() {
    final root = _root;
    root._retains--;
    if (!root._attached) root.clock.unfollow(root._follower);
  }

  /// Tells the root that a part changed, so the clock steps it and its
  /// selections read the change from now on, before the next frame
  /// publishes it.
  @internal
  void partChanged() {
    final root = _root;
    root._wake();
    root._follower.invalidate();
  }

  /// Tells the root that state of this motion's own changed, such as a
  /// flag its reads answer from: a command that moves no part calls it, so
  /// the selections read the change.
  @override
  @protected
  void changed() => partChanged();

  bool get _attached => _retains > 0 || _follower.hasListeners;

  void _wake() {
    if (_attached) clock.follow(_follower);
  }

  /// The latest time the motion was advanced or commanded to; it never
  /// moves backwards. A smaller motion owned by another shares its cursor.
  double get now => _root._now;

  /// Registers [part] and returns it: `late final x = own(MotionValue(0.0))`.
  ///
  /// [rest] is the tolerance the part rests within, read whenever rest is
  /// asked; the part's own rest when it is null. A smaller motion joins
  /// this motion's cursor and timeline and rests within its own parts'
  /// tolerances. A `MotionLoop` steps its frames as the motion advances,
  /// each at its own time between the reactions. Joining is a change: the
  /// root's selections read the part from now on.
  @protected
  P own<P extends MotionPart>(P part, {double Function()? rest}) {
    assert(part.owner == null, 'A part has one owner.');
    assert(
      part is! Motion || part._reactions.isEmpty,
      'A motion joins its owner before it schedules a reaction.',
    );
    part.owner = this;
    _parts.add(part);
    _rests.add(rest);
    partChanged();
    return part;
  }

  /// Lets go of [part], which [own] registered: it no longer counts for
  /// rest or wakes the root, and a smaller motion's pending reactions are
  /// dropped. The place is [didAdvance], once a part has finished leaving.
  @protected
  void disown(MotionPart part) {
    final i = _parts.indexOf(part);
    assert(i >= 0, 'Only an owned part is disowned.');
    if (i < 0) return;
    _parts.removeAt(i);
    _rests.removeAt(i);
    part.owner = null;
    if (part is Motion) {
      _root._reactions.removeWhere((reaction) {
        for (Motion? m = reaction.motion; m != null; m = m.owner) {
          if (identical(m, part)) return true;
        }
        return false;
      });
    }
    partChanged();
  }

  /// Runs [action] at time [t] on the root's timeline: right away, at
  /// [now], when [t] is not later than [now], and as the motion advances
  /// past [t] otherwise, at [t] itself however coarse the steps.
  ///
  /// A reaction with a [slot] replaces a pending one this motion scheduled
  /// in the same slot, so re-issuing a command never stacks its reactions.
  /// Slots belong to the motion: equal slots of two motions on one timeline
  /// never meet. The slots of one motion must differ by `==`: a symbol per
  /// slot (`#rise`, `#fall`) does, where every `const Object()` is one and
  /// the same object. Reactions with equal times run in the order they
  /// were scheduled.
  @protected
  MotionCancel at(double t, void Function(double t) action, {Object? slot}) {
    final root = _root;
    if (slot != null) root._reactions.removeWhere((r) => r.fills(this, slot));
    if (t <= root._now) {
      action(root._now);
      return _noCancel;
    }
    final reaction = _Reaction(t, action, slot, this);
    var i = root._reactions.length;
    while (i > 0 && root._reactions[i - 1].time > t) {
      i--;
    }
    root._reactions.insert(i, reaction);
    root._wake();
    return () => root._reactions.remove(reaction);
  }

  static void _noCancel() {}

  /// Drops the pending reaction this motion scheduled in [slot], if any.
  @protected
  void unschedule(Object slot) =>
      _root._reactions.removeWhere((reaction) => reaction.fills(this, slot));

  /// Drops every pending reaction this motion scheduled, as a motion that
  /// starts over does; those of the motions it owns stay.
  @protected
  void unscheduleAll() => _root._reactions.removeWhere(
    (reaction) => identical(reaction.motion, this),
  );

  /// Whether a reaction this motion scheduled waits in [slot].
  @protected
  bool isScheduled(Object slot) =>
      _root._reactions.any((reaction) => reaction.fills(this, slot));

  /// Moves to [t]: runs every reaction due by [t] at its own time, then
  /// moves [now] to [t]. A [t] before [now] runs nothing and keeps [now].
  ///
  /// A command a reaction gives at the reaction's own time, which advances
  /// to that time first, runs nothing: the reactions due at the same time
  /// run after the one under way, in their order.
  void advance(double t) {
    final root = _root;
    if (root._advancing) {
      assert(
        t <= root._now,
        'A reaction advances its motion no further than its own time.',
      );
      return;
    }
    root._advancing = true;
    try {
      while (root._reactions.isNotEmpty && root._reactions.first.time <= t) {
        final reaction = root._reactions.removeAt(0);
        if (reaction.time > root._now) {
          root._runLoops(reaction.time, before: true);
          root._now = reaction.time;
        }
        reaction.action(reaction.time);
      }
      if (t > root._now) root._now = t;
      root._runLoops(root._now);
      root._didAdvance(root._now);
    } finally {
      root._advancing = false;
    }
  }

  // Index loops: a part owned lazily registers while its owner steps.
  void _runLoops(double t, {bool before = false}) {
    for (var i = 0; i < _parts.length; i++) {
      final part = _parts[i];
      if (part is MotionLoop) part.run(t, before: before);
      if (part is Motion) part._runLoops(t, before: before);
    }
  }

  void _didAdvance(double t) {
    didAdvance(t);
    for (var i = 0; i < _parts.length; i++) {
      final part = _parts[i];
      if (part is Motion) part._didAdvance(t);
    }
  }

  /// Called after every advance, on the root and every motion it owns: the
  /// place to drop parts that finished leaving.
  @protected
  void didAdvance(double t) {}

  /// The lowest frame rate this motion asks of a fast display while it moves,
  /// as UIKit's frame rate ranges do: above 60 the display draws every vsync
  /// (see `FrameCadence`).
  double get minFrameRate => 0;

  /// Whether something outside the parts keeps the motion awake: a finger
  /// still down, a hold that has not come due.
  @protected
  bool get holds => false;

  /// Whether nothing moves from [now] on: no reaction waits, nothing
  /// [holds] and every part rests at [now].
  bool get isSettled {
    if (_root._reactions.isNotEmpty || !restsAt(now)) return false;
    final rest = restTime();
    return rest != null && rest <= now;
  }

  /// Declares at rest every part whose rest time has come by [now], each
  /// from that time; parts still moving keep their courses.
  void settle() => restFrom(now);

  /// When the motion next changes while nothing visible moves now and a
  /// reaction or a part's own change waits, so its owner can doze until
  /// then; null when the next frame moves or nothing waits.
  double? get wakeTime {
    if (!restsAt(now)) return null;
    return nextDue;
  }

  @override
  double? restTime([double? tolerance]) {
    if (holds) return null;
    var latest = double.negativeInfinity;
    for (var i = 0; i < _parts.length; i++) {
      final rest = _parts[i].restTime(_rests[i]?.call());
      if (rest == null) return null;
      latest = math.max(latest, rest);
    }
    return latest;
  }

  @override
  bool restsAt(double t, [double? tolerance]) {
    if (holds) return false;
    for (var i = 0; i < _parts.length; i++) {
      if (!_parts[i].restsAt(t, _rests[i]?.call())) return false;
    }
    return true;
  }

  @override
  void restFrom(double t) {
    for (var i = 0; i < _parts.length; i++) {
      final part = _parts[i];
      if (part is Motion) {
        part.restFrom(t);
        continue;
      }
      final rest = part.restTime(_rests[i]?.call());
      if (rest != null && rest <= t) part.restFrom(rest);
    }
  }

  @override
  double? get nextDue {
    var due = owner == null && _reactions.isNotEmpty
        ? _reactions.first.time
        : null;
    for (final part in _parts) {
      final next = part.nextDue;
      if (next != null && (due == null || next < due)) due = next;
    }
    return due;
  }
}

final class _Reaction {
  _Reaction(this.time, this.action, this.slot, this.motion);

  final double time;
  final void Function(double t) action;
  final Object? slot;
  final Motion motion;

  bool fills(Motion owner, Object slot) =>
      identical(motion, owner) && slot == this.slot;
}

/// What a renderer, a transition or a widget reads of a motion.
extension MotionSelect<M extends Motion> on M {
  /// [read] of this motion, recomputed after each frame that stepped its
  /// root or a command that moved it, and heard only when the result
  /// changes (`equals`, `==` by default). A read right after a command,
  /// such as a paint in the frame whose layout commanded it, answers the
  /// change; its followers hear it in the next publish phase. It tracks no
  /// reads: it depends on the root alone. Bind it once, in a State field.
  MotionSelection<T> select<T>(
    T Function(M motion) read, {
    bool Function(T a, T b)? equals,
  }) => MotionSelection<T>.of(
    _root._follower,
    () => read(this),
    clock: clock,
    equals: equals,
  );
}

final class _RootFollower implements MotionFollowed, Listenable {
  _RootFollower(this.motion);

  final Motion motion;
  final List<VoidCallback> _listeners = [];

  bool get hasListeners => _listeners.isNotEmpty;

  @override
  void addListener(VoidCallback listener) {
    final first = _listeners.isEmpty;
    _listeners.add(listener);
    if (first) motion._wake();
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
    if (!motion._attached) motion.clock.unfollow(this);
  }

  @override
  bool stepTo(double time) {
    motion.advance(time);
    if (!motion.isSettled) {
      if (motion.minFrameRate > FrameCadence.fullFloor) {
        FrameCadence.instance.hold();
      }
      return true;
    }
    motion.settle();
    return false;
  }

  @override
  double? get wakeTime => motion.wakeTime;

  // Its listeners are selections, which publish to their own widget
  // followers.
  @override
  bool get hasWidgetFollowers => false;

  @override
  void publish({required bool widgets}) => invalidate();

  // A selection hears its root as an input: it recomputes on its next read
  // and publishes in the coming publish phase.
  void invalidate() {
    for (final listener in List<VoidCallback>.of(_listeners)) {
      guardMotion(listener, 'while notifying a selection of a Motion');
    }
  }
}

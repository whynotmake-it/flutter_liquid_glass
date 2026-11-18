import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/src/presentation/presentation.dart';

/// The part of a presentation's life that does not depend on where it
/// shows, shared by the route and the portal: the committed motion and the
/// source's lease, whether it leaves, whether it is modal, the result it
/// completes with, the dismissal policy, the scrollable it leaves with and
/// its single end.
@internal
final class PresentationSession {
  /// A session for the shell's `presentation`, read at each use, since a
  /// portal's can change while it shows; the motion runs on `scopeClock`
  /// until the commit makes one.
  ///
  /// A shell with hooks of its own hands them over: `leave` starts the
  /// motion's leave and `ended` hears the end with the result.
  PresentationSession({
    required this._presentation,
    required MotionClock Function() scopeClock,
    bool Function(DismissTrigger trigger)? leave,
    void Function(Object? result)? ended,
  }) : _scopeClockOf = scopeClock,
       _leaveHook = leave,
       _endedHook = ended;

  final Presentation<Object?, Presented> Function() _presentation;
  final MotionClock Function() _scopeClockOf;
  final bool Function(DismissTrigger trigger)? _leaveHook;
  final void Function(Object? result)? _endedHook;

  Presented? _motion;
  VoidCallback? _lease;
  MotionClock? _scopeClock;
  bool _leaving = false;
  bool _ended = false;
  bool _disposed = false;
  Object? _result;
  ScrollPosition? _scroll;
  VoidCallback? _onScroll;
  final ValueNotifier<bool> _inert = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _modal = ValueNotifier<bool>(true);

  /// The committed motion; null before the commit and after the end.
  Presented? get motion => _motion;

  /// The motion's clock, or before there is one the clock of the place the
  /// presentation shows in.
  MotionClock get clock => _motion?.clock ?? (_scopeClock ??= _scopeClockOf());

  /// Whether the presentation was dismissed and its motion leaves; read at
  /// each touch, as a leave can start in any phase of a frame.
  bool get isLeaving => _leaving;

  /// [isLeaving] for what only a rebuild changes.
  ValueListenable<bool> get inert => _inert;

  /// Whether the presentation is modal now; true before the commit.
  ValueListenable<bool> get modal => _modal;

  /// The result the presentation completes with.
  Object? get result => _result;

  /// Whether [end] has run since the last commit.
  bool get ended => _ended;

  /// Commits the presentation for [environment]: makes and opens its
  /// motion, leases its source and reads whether it is modal.
  void commit(PresentationEnvironment environment) {
    final (motion, lease) = commitPresentation(_presentation(), environment);
    _motion = motion;
    _lease = lease;
    _ended = false;
    _result = null;
    _setLeaving(false);
    _modal.value = _modalNow();
  }

  /// Whether the policy lets [trigger] through; a refusal calls the
  /// presentation's `onVeto`.
  bool admits(DismissTrigger trigger) {
    final presentation = _presentation();
    if (presentation.dismiss.allows(trigger)) return true;
    presentation.onVeto?.call(trigger);
    return false;
  }

  /// The result a dismissal with [popped] completes with: the
  /// presentation's mapping of it.
  Object? resultOf(Object? popped) => _presentation().resultOf(popped);

  /// Marks the presentation leaving, keeps [result], mapped by [resultOf]
  /// already, as what it completes with and starts the motion's leave for
  /// [trigger]; false when there is nothing to close, which ends the
  /// presentation at once.
  ///
  /// The mapping stays with the caller because a route hands the mapped
  /// result to the navigator before its leave may start.
  bool leave(DismissTrigger trigger, Object? result) {
    _setLeaving(true);
    _result = result;
    final hook = _leaveHook;
    if (hook != null) return hook(trigger);
    return _motion?.leave(clock.now, trigger) ?? false;
  }

  /// Brings a leaving presentation back: its motion opens again from where
  /// it is, at the clock's time.
  void reopen() {
    final motion = _motion;
    if (motion == null) return;
    _setLeaving(false);
    _result = null;
    motion.open(clock.now);
  }

  /// Applies a change of whether the presentation is modal; one reported
  /// while the frame builds, lays out or paints applies in the clock's
  /// coming publish phase, before the next frame builds.
  void modalityChanged() {
    if (_motion == null) return;
    final modal = _modalNow();
    if (modal == _modal.value) return;
    if (_building) {
      clock.schedulePublish(() {
        if (!_disposed) modalityChanged();
      });
      return;
    }
    _modal.value = modal;
  }

  /// Calls [onScroll] when [position] starts to scroll; a null [position]
  /// stops following.
  void followScroll(ScrollPosition? position, VoidCallback onScroll) {
    _onScroll = onScroll;
    if (identical(position, _scroll)) return;
    _scroll?.isScrollingNotifier.removeListener(_scrolled);
    _scroll = position;
    position?.isScrollingNotifier.addListener(_scrolled);
  }

  /// Ends the presentation once per commit: the source is released and the
  /// presentation hears the result. A later call does nothing.
  void end() {
    if (_ended) return;
    _ended = true;
    _lease?.call();
    _lease = null;
    _motion = null;
    final ended = _endedHook;
    if (ended != null) {
      ended(_result);
    } else {
      _presentation().dismissed(_result);
    }
  }

  /// Stops following the scrollable and releases the notifiers; the shell
  /// calls [end] first.
  void dispose() {
    _scroll?.isScrollingNotifier.removeListener(_scrolled);
    _scroll = null;
    _inert.dispose();
    _modal.dispose();
    _disposed = true;
  }

  void _scrolled() {
    if (_scroll?.isScrollingNotifier.value ?? false) _onScroll?.call();
  }

  bool _modalNow() {
    final motion = _motion;
    return motion == null || _presentation().modalOf(motion);
  }

  // A leave the content reports while it builds applies before the next
  // build: the touch gate already holds.
  void _setLeaving(bool leaving) {
    _leaving = leaving;
    if (_inert.value == leaving) return;
    if (_building) {
      clock.schedulePublish(() {
        if (!_disposed) _inert.value = _leaving;
      });
      return;
    }
    _inert.value = leaving;
  }

  static bool get _building =>
      SchedulerBinding.instance.schedulerPhase ==
      SchedulerPhase.persistentCallbacks;
}

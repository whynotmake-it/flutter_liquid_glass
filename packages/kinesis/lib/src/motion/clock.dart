import 'dart:async';
import 'dart:developer' show Timeline;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:kinesis/src/motion/frame_time.dart';
import 'package:kinesis/src/motion/pointer_clock_stub.dart'
    if (dart.library.ffi) 'package:kinesis/src/motion/pointer_clock_io.dart';
import 'package:kinesis/src/motion/timeline.dart';
import 'package:kinesis/src/motion/transaction.dart';

/// A value the clock steps and publishes while it moves and something
/// follows it.
@internal
abstract interface class MotionFollowed {
  /// Moves to [time] in the step phase; returns whether it needs another
  /// frame.
  bool stepTo(double time);

  /// The time before which it does not move, or null when it moves now.
  double? get wakeTime;

  /// Tells its render followers where it is, and its other followers too
  /// when [widgets]: in the resolve phase only render followers hear.
  void publish({required bool widgets});

  /// Whether it has followers that are not render followers.
  bool get hasWidgetFollowers;
}

/// A value derived from others and recomputed after the values publish.
@internal
abstract interface class MotionDerived {
  /// Recomputes and tells its render followers when the result changed,
  /// and its other followers too when [widgets].
  void recompute({required bool widgets});

  /// Whether it has followers that are not render followers.
  bool get hasWidgetFollowers;
}

/// Runs [body], reporting what it throws as the error of [context] in
/// kinesis, as `ChangeNotifier` does for its listeners, so one failing
/// listener does not stop the frame.
@internal
void guardMotion(VoidCallback body, String context) {
  try {
    body();
  } on Object catch (exception, stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: exception,
        stack: stack,
        library: 'kinesis',
        context: ErrorDescription(context),
      ),
    );
  }
}

/// Owns motion time and the frame: the one ordered step in which every
/// value of the app advances.
///
/// A frame runs in phases: scheduled actions (each at its own time), the
/// step (values and motions advance to the frame's time, running their due
/// reactions and delayed changes, and are declared at rest once they
/// rest), then publish (values tell their followers, derived values
/// recompute once each), all before build; then, after layout, resolve
/// (layouts place what they just laid out, and the values that change
/// tell their render followers before paint). Every read in a frame
/// answers at one time.
///
/// Times are seconds on one monotonic timeline. Every operation of a
/// `MotionValue` also has a form with an explicit time; a clock supplies
/// [now] for the ambient forms (`MotionValue.target`, `MotionValue.value`).
abstract class MotionClock {
  static MotionClock? _instance;

  /// The clock values use when none is given: the binding's frame clock,
  /// shared by every view, as Flutter frames all views in one pass.
  static MotionClock get instance => _instance ??= _BindingClock();

  /// Replaces [instance], for tests and apps that drive time themselves.
  static set instance(MotionClock clock) => _instance = clock;

  /// Replaces the engine clock the frame clock compares frame and input
  /// time stamps with, for tests that drive it like a device's.
  @visibleForTesting
  static Duration Function()? debugEngineNow;

  /// Replaces how far the engine clock runs ahead of pointer time stamps,
  /// or answers null for a platform that gives no usable time stamps.
  @visibleForTesting
  static Duration? Function()? debugPointerClockOffset;

  /// Drops [instance], so the next read creates a fresh frame clock.
  @visibleForTesting
  static void debugReset() {
    final clock = _instance;
    if (clock is _BindingClock) clock._stop();
    _instance = null;
    MotionTransaction.clearLayout();
  }

  final MotionTimeline _timeline = MotionTimeline();
  final Set<MotionFollowed> _followed = {};
  final Set<MotionDerived> _dirty = {};
  final Set<MotionFollowed> _owed = {};
  final Set<MotionDerived> _owedDerived = {};
  Set<MotionFollowed>? _resolved;

  // The resolve phase is the frame's, not one clock's: the clocks whose
  // values it changed, while it runs, and whether its steps still run.
  static final Set<MotionClock> _resolveClocks = {};
  static bool _resolving = false;
  static bool _resolveSteps = false;

  double? _inputTime;
  double _lastInput = double.negativeInfinity;

  /// The time the ambient forms read, in seconds: the stamp of the input
  /// being dispatched inside [input], the frame's time ([frameTime])
  /// otherwise.
  double get now => _inputTime ?? frameTime;

  /// The time of the current frame, or of the coming one between frames,
  /// in seconds.
  double get frameTime;

  /// Runs [body] as input stamped [time]: inside it [now] is that stamp,
  /// so `withSpring`, a `target` written and anything else that reads the
  /// clock's time starts where the input happened, often a frame or two
  /// before the frame that draws it.
  ///
  /// Inputs commit in the order they arrive: a stamp earlier than the
  /// previous input's takes that input's time.
  void input(double time, VoidCallback body) {
    final at = time < _lastInput ? _lastInput : time;
    _lastInput = at;
    final saved = _inputTime;
    _inputTime = at;
    try {
      body();
    } finally {
      _inputTime = saved;
    }
  }

  /// The display's frame period in seconds, or null before steady frames.
  double? get framePeriod;

  /// The frame rate the clock's frames come at: for the binding's clock, 60
  /// on a 60 Hz display and 120 otherwise.
  double get frameRate;

  /// The time of an input event whose time stamp is [timeStamp].
  ///
  /// It does not wake the clock: what the input changes does, so a finger
  /// moving where nothing answers it costs no frame.
  double stamp(Duration timeStamp);

  /// Makes sure the clock produces a frame for work that is now pending.
  void wake();

  /// Runs [action] at [time], in the scheduled-actions phase of the frame
  /// that reaches it, with that time; the returned callback cancels it.
  ///
  /// For an input host's timed reactions, such as a long press coming due
  /// or a scroll delay ending: the action runs at its own time however late
  /// the frame that reaches it, so a timed reaction replays exactly.
  VoidCallback schedule(double time, void Function(double time) action) {
    void run(double t) =>
        guardMotion(() => action(t), 'while running a scheduled action');
    _timeline.insert(time, run);
    wake();
    return () {
      _timeline.remove(run);
      _idleCheck();
    };
  }

  /// Runs [callback] once in the coming publish phase, after the frame's
  /// motion values stepped and published and before build, where a widget
  /// may rebuild; the returned callback cancels it.
  ///
  /// A frame is asked for when none is coming; asking from within a
  /// publish phase runs [callback] in that phase. Every call schedules a
  /// run of its own.
  VoidCallback schedulePublish(VoidCallback callback) {
    final publisher = _Publisher(callback);
    markDirty(publisher);
    return () {
      _dirty.remove(publisher);
      _owedDerived.remove(publisher);
      _idleCheck();
    };
  }

  /// Steps and publishes [value] every frame until it rests.
  @internal
  void follow(MotionFollowed value) {
    _followed.add(value);
    if (_resolveSteps) {
      (_resolved ??= {}).add(value);
      _resolveClocks.add(this);
    } else if (_commanded case final commanded?) {
      commanded.add(value);
    } else {
      wake();
    }
  }

  /// Stops stepping [value].
  @internal
  void unfollow(MotionFollowed value) {
    if (_followed.remove(value)) _idleCheck();
  }

  /// Recomputes [derived] in the coming publish phase, or in the current
  /// one when it runs.
  @internal
  void markDirty(MotionDerived derived) {
    if (!_dirty.add(derived)) return;
    if (_resolving) {
      _resolveClocks.add(this);
    } else if (_commanded == null) {
      wake();
    }
  }

  /// Runs [steps] in the frame's resolve phase, after layout and before
  /// paint, each reporting what it throws on its own as the error of
  /// [context], so one failing step does not stop the others.
  ///
  /// The values they change, on whichever clock each runs, are stepped and
  /// published to their render followers at once, so what draws them shows
  /// this frame's presentation; a render follower may mark paint,
  /// composited layers and layout there, and what it marks for layout is
  /// laid out again in the same frame. Their other followers, such as
  /// widgets that rebuild, hear them in their clock's next publish phase.
  @internal
  static void resolve(Iterable<VoidCallback> steps, String context) {
    assert(!_resolving, 'The resolve phase does not nest.');
    _resolving = true;
    // What layout dirtied on the app's clock outside a step is recomputed
    // for its render followers here too.
    if (_instance case final ambient?) _resolveClocks.add(ambient);
    try {
      _resolveSteps = true;
      try {
        for (final step in steps) {
          guardMotion(step, context);
        }
      } finally {
        _resolveSteps = false;
      }
      // Publishing one clock's values may dirty what another clock derives.
      while (_resolveClocks.isNotEmpty) {
        final clock = _resolveClocks.first;
        _resolveClocks.remove(clock);
        clock._publishResolved();
        if (clock.needsFrame) clock.wake();
      }
    } finally {
      _resolving = false;
      _resolveClocks.clear();
    }
  }

  void _publishResolved() {
    final resolved = _resolved;
    _resolved = null;
    if (resolved != null) {
      final time = frameTime;
      for (final value in resolved) {
        if (!value.stepTo(time)) _followed.remove(value);
      }
      for (final value in resolved) {
        value.publish(widgets: false);
      }
      _owed.addAll(resolved.where((value) => value.hasWidgetFollowers));
    }
    _drain(widgets: false);
  }

  void _drain({required bool widgets}) {
    if (widgets) {
      _dirty.addAll(_owedDerived);
      _owedDerived.clear();
    }
    while (_dirty.isNotEmpty) {
      final derived = _dirty.first;
      _dirty.remove(derived);
      derived.recompute(widgets: widgets);
      if (!widgets && derived.hasWidgetFollowers) _owedDerived.add(derived);
    }
  }

  /// Runs the phases of one frame at [time].
  @protected
  void runFrame(double time) {
    _timeline.runDue(time);
    final stepped = List.of(_followed);
    for (final value in stepped) {
      if (!value.stepTo(time)) _followed.remove(value);
    }
    for (final value in stepped) {
      value.publish(widgets: true);
    }
    final owed = List.of(_owed.difference(stepped.toSet()));
    _owed.clear();
    for (final value in owed) {
      value.publish(widgets: true);
    }
    _drainCommanded(time);
  }

  // The values a listener commands while the publish phase drains, which
  // that frame steps and publishes too.
  Set<MotionFollowed>? _commanded;

  // A listener that commands a value in the publish phase, such as a title
  // that fades in once a scroll passes it, has it drawn in this frame.
  void _drainCommanded(double time) {
    for (var pass = 0; ; pass++) {
      final commanded = _commanded = {};
      try {
        _drain(widgets: true);
      } finally {
        _commanded = null;
      }
      if (commanded.isEmpty) return;
      if (pass == _commandPasses) {
        wake();
        return;
      }
      for (final value in commanded) {
        if (!value.stepTo(time)) _followed.remove(value);
      }
      for (final value in commanded) {
        value.publish(widgets: true);
      }
    }
  }

  // Listeners that keep commanding each other finish in the next frame.
  static const _commandPasses = 8;

  /// Whether anything moves or is pending.
  @protected
  bool get needsFrame =>
      _followed.isNotEmpty ||
      _dirty.isNotEmpty ||
      _owed.isNotEmpty ||
      _owedDerived.isNotEmpty ||
      !_timeline.isEmpty;

  /// The time before which no frame would change anything, or null when
  /// the next frame would.
  @protected
  double? get wakeTime {
    if (_dirty.isNotEmpty || _owed.isNotEmpty || _owedDerived.isNotEmpty) {
      return null;
    }
    var wake = _timeline.nextDue ?? double.infinity;
    for (final value in _followed) {
      final at = value.wakeTime;
      if (at == null) return null;
      if (at < wake) wake = at;
    }
    return wake.isFinite ? wake : null;
  }

  void _idleCheck() {}
}

final class _Publisher implements MotionDerived {
  _Publisher(this.callback);

  final VoidCallback callback;

  @override
  bool get hasWidgetFollowers => true;

  @override
  void recompute({required bool widgets}) {
    if (widgets) guardMotion(callback, 'while running a publish callback');
  }
}

/// A clock that moves only when told to: for tests, replays and apps that
/// drive time themselves. [advanceTo] runs a frame's phases at once.
class ManualMotionClock extends MotionClock {
  /// Creates a clock at [start] seconds for a display at [frameRate].
  ManualMotionClock({double start = 0, this.frameRate = 120}) : _now = start;

  double _now;

  @override
  final double frameRate;

  @override
  double get frameTime => _now;

  @override
  double? get framePeriod => 1 / frameRate;

  @override
  double stamp(Duration timeStamp) => _now;

  @override
  void wake() {}

  /// Moves the clock to [t] and runs a frame there; time never runs
  /// backwards.
  void advanceTo(double t) {
    assert(t >= _now, 'time runs forward: $t is before $_now');
    _now = t;
    runFrame(t);
  }
}

/// The binding's frame clock.
///
/// Its time is its [FrameTime]'s, fed the scheduler's frame time stamps and
/// the input's. The clock asks for frames only while something is active.
/// With only a later change pending it dozes on a timer instead, and with
/// nothing pending it sleeps.
///
/// A frame's phases run in a microtask scheduled from the clock's frame
/// callback, so after every ticker of the frame and before build; a clock
/// woken by a ticker or by a microtask of a frame that has not built yet
/// runs them in that frame. The web engine flushes no microtasks between
/// beginning a frame and drawing it, so phases still queued when the frame
/// draws run first. The frame's time is computed once, by whichever
/// reads it first: a ticker that runs before the clock's callback reads the
/// time the frame steps at.
class _BindingClock extends MotionClock {
  late final FrameTime _frames = FrameTime(
    engineNow: _engineNow,
    pointerClockOffset: _pointerClockOffset,
    dilation: () => timeDilation,
    frameRate: () => frameRate,
  );
  bool _running = false;
  bool _phasesQueued = false;
  bool _phasesRan = false;
  int? _callbackId;
  Timer? _doze;

  @override
  double get frameTime {
    final scheduler = SchedulerBinding.instance;
    if (_callbackId != null &&
        scheduler.schedulerPhase == SchedulerPhase.transientCallbacks) {
      _frames.advance(
        scheduler.currentFrameTimeStamp,
        scheduler.currentSystemFrameTimeStamp,
      );
      return _frames.time;
    }
    return _frames.read(
      frameStamp: scheduler.schedulerPhase == SchedulerPhase.idle
          ? null
          : scheduler.currentFrameTimeStamp,
    );
  }

  @override
  double? get framePeriod => _frames.period;

  @override
  double get frameRate {
    final views = SchedulerBinding.instance.platformDispatcher.views;
    final rate = views.isEmpty ? null : views.first.display.refreshRate;
    return rate != null && rate.round() == 60 ? 60 : 120;
  }

  // The engine stamps frames on the Dart timeline clock: on iOS that is
  // CLOCK_MONOTONIC_RAW (iPhone 16 Pro, iOS 27.0.1, Flutter 3.47.2), while
  // touches count CLOCK_UPTIME_RAW (pointerClockOffset).
  static Duration _engineNow() =>
      MotionClock.debugEngineNow?.call() ??
      Duration(microseconds: Timeline.now);

  static Duration? _pointerClockOffset() {
    final hook = MotionClock.debugPointerClockOffset;
    return hook == null ? pointerClockOffset() : hook();
  }

  @override
  double stamp(Duration timeStamp) => _frames.stamp(timeStamp);

  @override
  void wake() {
    _endDozeTimer();
    final scheduler = SchedulerBinding.instance;
    final phase = scheduler.schedulerPhase;
    // What wakes the clock before build shows in the frame being made, not
    // the next, even after that frame's phases ran.
    final building =
        phase == SchedulerPhase.transientCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks;
    if (_running) {
      if (building && _phasesRan) _queuePhases();
      return;
    }
    _running = true;
    // As a Ticker started inside a frame does, count from that frame, so
    // the next frame already moves by a frame.
    _frames.origin =
        phase.index > SchedulerPhase.idle.index &&
            phase.index < SchedulerPhase.postFrameCallbacks.index
        ? scheduler.currentFrameTimeStamp
        : null;
    if (building) {
      _frames.advance(
        scheduler.currentFrameTimeStamp,
        scheduler.currentSystemFrameTimeStamp,
      );
      _queuePhases();
      return;
    }
    _request();
  }

  void _queuePhases() {
    if (_phasesQueued) return;
    _phasesQueued = true;
    _drawAfterPhases(SchedulerBinding.instance.platformDispatcher);
    scheduleMicrotask(_runQueued);
  }

  void _runQueued() {
    if (_phasesQueued) _phases();
  }

  static PlatformDispatcher? _drawWrapped;

  static void _drawAfterPhases(PlatformDispatcher dispatcher) {
    if (identical(_drawWrapped, dispatcher)) return;
    final draw = dispatcher.onDrawFrame;
    // Before the binding's first frame: wrapping now would keep it from
    // registering its own.
    if (draw == null) return;
    _drawWrapped = dispatcher;
    dispatcher.onDrawFrame = () {
      if (MotionClock._instance case final _BindingClock clock) {
        clock._runQueued();
      }
      draw();
    };
  }

  void _request() {
    if (_callbackId != null) return;
    _callbackId = SchedulerBinding.instance.scheduleFrameCallback(_onFrame);
  }

  void _cancel() {
    _running = false;
    final id = _callbackId;
    if (id == null) return;
    SchedulerBinding.instance.cancelFrameCallbackWithId(id);
    _callbackId = null;
  }

  void _endDozeTimer() {
    _doze?.cancel();
    _doze = null;
  }

  void _sleep() {
    _frames.sleep();
    _cancel();
    _endDozeTimer();
  }

  void _stop() {
    _cancel();
    _endDozeTimer();
    _frames.stop();
  }

  void _onFrame(Duration timeStamp) {
    _callbackId = null;
    _phasesRan = false;
    if (!_running) return;
    _frames.advance(
      timeStamp,
      SchedulerBinding.instance.currentSystemFrameTimeStamp,
    );
    _queuePhases();
  }

  void _phases() {
    _phasesQueued = false;
    if (!_running) return;
    _phasesRan = false;
    runFrame(_frames.time);
    _phasesRan = true;
    if (!needsFrame) {
      _sleep();
      return;
    }
    final until = wakeTime;
    // A wait of two frames or less keeps the frames: dozing saves nothing.
    if (until != null && until - _frames.time > 2 / frameRate) {
      _frames.dozed();
      // Half a frame early, so the frame that shows the change is never
      // missed.
      final delay = (until - _frames.time - 0.5 / frameRate) * timeDilation;
      _cancel();
      _doze = Timer(
        Duration(microseconds: (delay * 1e6).floor()),
        _endDoze,
      );
      return;
    }
    _request();
  }

  void _endDoze() {
    _doze = null;
    wake();
  }

  @override
  void _idleCheck() {
    if (!needsFrame) _sleep();
  }
}

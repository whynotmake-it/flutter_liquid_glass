import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Which of a fast display's vsyncs the app draws on.
///
/// On a display faster than 60 Hz the app draws every second vsync (about 60
/// frames a second) unless something fast moves: a scroll or a finger past
/// [fullSpeed], or a `Motion` with a higher floor, such as a sheet. Everything
/// on the screen moves in one frame, so glass never lags what lies under it.
/// A display at 90 Hz or less draws every vsync.
///
/// Nothing runs until [start]. It sees a scroll only when told through
/// [scrolled], and a scroll nobody reports stays at the lower rate, so whoever
/// calls [start] reports the scrolls of the app.
///
/// When the device cannot keep up with the full rate, it stays at the lower
/// one for a while, longer each time, as a phone that misses every other
/// frame looks worse than a phone at a steady 60.
///
/// Fidelity: NEAR. UIKit picks a scroll's rate from its speed in device
/// pixels: 48 Hz up to about 180 - 240 px/s, 60 up to 400 - 480, 80 up to 720
/// - 960, 120 up to 4560 - 4800 and 80 above (read from UIKit, notes
/// private), and its dynamic-spec channels, sheet bodies included, publish at
/// 60 Hz (iPhone 16 Pro, iOS 27.0.1). Skipping vsyncs reaches only 120 and
/// 60: slow motion runs at 60 rather than 48, and the two bands at 80 run at
/// 60 or 120, split at [fullSpeed] and left at 120 above 4800 px/s.
final class FrameCadence {
  FrameCadence._();

  /// The cadence of the running app.
  static final FrameCadence instance = FrameCadence._();

  /// The speed in device pixels a second from which a scroll or a finger
  /// draws every vsync: the bottom of UIKit's band of 720 - 960 px/s, whose
  /// 80 Hz skipping cannot reach.
  static const double fullSpeed = 720;

  /// The floor above which a `Motion` draws every vsync while it moves.
  static const double fullFloor = 60;

  final _policy = CadencePolicy();
  SchedulerBinding? _binding;
  bool _skipped = false;
  bool _timed = false;

  /// Starts deciding the app's frames from the end of the coming frame, when
  /// the binding's frame callbacks are in place.
  void start() {
    if (_binding != null) return;
    final binding = SchedulerBinding.instance;
    // After the frame: the binding's own frame callbacks are in place then.
    binding.addPostFrameCallback((_) => _attach(binding));
  }

  void _attach(SchedulerBinding binding) {
    if (identical(_binding, binding)) return;
    final dispatcher = binding.platformDispatcher;
    final begin = dispatcher.onBeginFrame;
    final draw = dispatcher.onDrawFrame;
    if (begin == null || draw == null) return;
    _binding = binding;
    dispatcher.onBeginFrame = (timeStamp) {
      _skipped = !_policy.draws(timeStamp);
      if (_skipped) {
        dispatcher.scheduleFrame();
        return;
      }
      if (!_timed && _policy.fast) {
        _timed = true;
        binding.addTimingsCallback(_onTimings);
      }
      begin(timeStamp);
    };
    dispatcher.onDrawFrame = () {
      if (!_skipped) draw();
    };
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      _policy.timed(
        vsync: Duration(
          microseconds: timing.timestampInMicroseconds(FramePhase.vsyncStart),
        ),
        build: timing.buildDuration,
        raster: timing.rasterDuration,
      );
    }
  }

  /// Tells the cadence that a finger moved at [pixelsPerSecond] device pixels
  /// a second, or that it came down or lifted with [changed], which the next
  /// vsync draws.
  void input({double? pixelsPerSecond, bool changed = false}) {
    if (pixelsPerSecond != null) _policy.speed(pixelsPerSecond);
    if (changed) _policy.drawNext();
  }

  /// Tells the cadence that a scroll view moved by [delta] logical pixels in
  /// this frame, on a screen with [devicePixelRatio].
  void scrolled(double delta, double devicePixelRatio) =>
      _policy.scrolled(delta * devicePixelRatio);

  /// Tells the cadence that a motion whose floor lies above [fullFloor]
  /// moved.
  void hold() => _policy.hold();
}

/// What [FrameCadence] decides, from the vsyncs and reports it is told.
@visibleForTesting
final class CadencePolicy {
  // UIKit's scroll stops asking 64 ms after movement ends (read from UIKit,
  // notes private): 8 vsyncs at 120 Hz.
  static const int _fullVsyncs = 8;

  // UIKit's scroll changes rate after 5 updates of hysteresis (read from
  // UIKit, notes private).
  static const int _slowUpdates = 5;

  // A frame every 16.67 ms with room for a vsync's jitter, which 90 Hz
  // (11.1 ms, half a period short) just misses, so it keeps every vsync.
  static const int _targetMicros = 15667;

  // A display whose vsyncs come at less than this is fast.
  static const int _fastMicros = 10000;

  // A frame that takes longer than its vsync gap misses it. A quarter of 30
  // frames doing so is more than a stray hitch.
  static const int _window = 30;
  static const int _missing = 8;

  static const Duration _firstCap = Duration(seconds: 30);

  Duration? _seen;
  Duration? _drawn;
  Duration? _timedAt;
  Duration? _cappedUntil;
  Duration _capFor = _firstCap;
  int _periodMicros = 16667;
  int _fast = 0;
  int _held = 0;
  int _slow = 0;
  int _frames = 0;
  int _misses = 0;
  bool _next = false;

  /// Whether the last vsync came fast enough for the cadence to matter.
  bool get fast => _periodMicros < _fastMicros;

  /// A scroll or a finger moved at [pixelsPerSecond].
  void speed(double pixelsPerSecond) {
    if (pixelsPerSecond >= FrameCadence.fullSpeed) {
      _fast = _fullVsyncs;
      _slow = 0;
    } else if (++_slow >= _slowUpdates) {
      _fast = 0;
    }
  }

  /// A scroll moved by [devicePixels] in the frame drawn last.
  void scrolled(double devicePixels) =>
      speed(devicePixels.abs() * 1e6 / _drawnGapMicros);

  int _drawnGapMicros = 16667;

  /// A motion with a floor above 60 Hz moved.
  void hold() => _held = _fullVsyncs;

  /// The next vsync draws, whatever it follows.
  void drawNext() => _next = true;

  /// Whether the vsync at [vsync] draws.
  bool draws(Duration vsync) {
    final seen = _seen;
    final drawn = _drawn;
    _seen = vsync;
    final full = _fast > 0 || _held > 0;
    if (_fast > 0) _fast--;
    if (_held > 0) _held--;
    if (seen == null || drawn == null) return _draw(vsync, null);
    final period = (vsync - seen).inMicroseconds;
    if (period < 50000) _periodMicros = period;
    final since = (vsync - drawn).inMicroseconds;
    final capped = _cappedUntil != null && vsync < _cappedUntil!;
    if ((full && !capped) || _next || since + period ~/ 2 >= _targetMicros) {
      return _draw(vsync, since);
    }
    return false;
  }

  bool _draw(Duration vsync, int? since) {
    _drawn = vsync;
    _next = false;
    if (since != null && since < 50000) _drawnGapMicros = since;
    return true;
  }

  /// A frame that began at [vsync] took [build] on the UI thread and [raster]
  /// on the raster thread.
  void timed({
    required Duration vsync,
    required Duration build,
    required Duration raster,
  }) {
    final last = _timedAt;
    _timedAt = vsync;
    if (last == null) return;
    final gap = vsync - last;
    if (gap.inMicroseconds >= _fastMicros) return;
    _frames++;
    if (build > gap || raster > gap) _misses++;
    if (_frames < _window) return;
    if (_misses >= _missing) {
      final seen = _seen;
      if (seen != null) _cappedUntil = seen + _capFor;
      _capFor *= 2;
    }
    _frames = 0;
    _misses = 0;
  }
}

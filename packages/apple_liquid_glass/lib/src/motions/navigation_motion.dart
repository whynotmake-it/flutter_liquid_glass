import 'dart:math' as math;

import 'package:apple_liquid_glass/src/motions/ui_frame_rate.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:kinesis/motion.dart';

/// The tuning of a page sliding onto and off a navigation stack.
///
/// Read from UIKit on iOS 27 (`UINavigationController`'s transition and
/// its interactive pop; notes private) where marked, else fitted to the
/// iPhone 16 Pro device recordings.
@internal
abstract final class NavigationTuning {
  /// The spring a page slides in and out on without a finger: critically
  /// damped, response 0.3 (read from UIKit).
  static const pushSpring = Spring.response(0.3);

  /// The spring a page settles on after a finger lets it go, popping or
  /// returning: damping 0.85, response 0.3 (read from UIKit; the recorded
  /// completion overshoots by the 0.6 percent it predicts).
  static const interactiveSpring = Spring.response(0.3, dampingRatio: 0.85);

  /// The speed a push or pop without a finger starts at, in page widths per
  /// second: the page leaves its start at full speed. UIKit gives the
  /// spring an impulse of 0.02 s (read), which makes 0.02 (2 pi / 0.3)^2 =
  /// 8.77 (fits the device push rows within 0.9 pt).
  static const double pushVelocity = 8.77;

  /// The drag progress, rubber banded past either end of its travel as
  /// UIKit does: at most half the page's width past an end, with the
  /// coefficient 0.55 (read from UIKit; the coefficient is UIKit's default
  /// for scrolling, assumed for touch).
  static const RubberBand band = RubberBand(0, 1, dimension: 0.5);

  /// The seconds a push or pop without a finger cross-fades for under
  /// Prefer Cross-Fade Transitions (`GlassTraits.prefersCrossFade`), on
  /// [crossFadeCurve], instead of sliding; an edge swipe still slides (read
  /// from UIKit).
  static const double crossFadeDuration = 0.5;

  /// The easing of the cross-fade: UIView's default animation curve.
  static const Curve crossFadeCurve = Curves.easeInOut;
}

/// Predicts whether an interactive back swipe completes.
///
/// Read from UIKit (notes private), then replayed from iPhone 16 Pro,
/// iOS 27.0.1 touches: pan speed mixes the last two movement speeds with
/// weights 0.2 / 0.8. The last three normalized speeds and accelerations
/// predict progress after 0.35 s. The page pops past the smaller of
/// 187.5 points and half its width. Holding a finger keeps its last pan
/// speed; a lift updates the statistics without adding a stationary move.
/// An uninterrupted fast flick also boosts the spring's starting speed
/// by [flickBoost] until its mean speed falls below [flickThreshold].
///
/// Supply positions before recognition with [addPosition], call [begin]
/// when the drag wins, then [update] after each page movement and at lift.
/// Times are monotonic seconds; positions increase toward the popping side.
/// The equations reproduce the recorded inputs; platform event timing and
/// gesture admission can differ (NEAR).
class NavigationPopMotion {
  /// Creates a predictor for a page [width] points wide.
  NavigationPopMotion(this.width) : assert(width > 0, 'a page has a width');

  /// The page width captured when the pointer starts.
  final double width;

  /// The native prediction interval, in seconds (read from UIKit).
  static const double predictionTime = 0.35;

  /// The maximum projected distance needed to pop, in points.
  static const double predictionDistance = 187.5;

  /// The projected fraction needed on narrower pages.
  static const double predictionFraction = 0.5;

  /// The mean speed below which the initial flick phase ends, in widths/s.
  /// Read from UIKit on iOS 27.0.1, notes private.
  static const double flickThreshold = 1.5;

  /// The settle-speed boost while the initial flick phase persists.
  /// Read from UIKit on iOS 27.0.1, notes private.
  static const double flickBoost = 4.25;

  /// The share of the page's width at its leading edge an interactive pop
  /// starts from: 13 points, or 9 percent of the portrait width on phones
  /// with thin bezels (read from UIKit; which branch an iPhone 16 Pro takes
  /// is not read, the port takes the thin-bezel one).
  static const double edgeShare = 0.09;

  /// How far a finger on the edge moves before the pop begins, in points
  /// (read from UIKit).
  static const double edgeHysteresis = 15;

  /// How far a finger away from the edge moves along the page before the
  /// pop begins, or the wrong way before it fails, in points (read from
  /// UIKit; the content swipe of `UINavigationController`).
  static const double contentHysteresis = 30;

  /// The most a finger away from the edge may move across the page, in
  /// points, before the pop begins, for a move [along] the page:
  /// min(25, 0.8 |tx| + 10), which a straight drag passes up to about 40
  /// degrees (read from UIKit). On a vertical list the list's own drag
  /// takes steeper ones first; the device cut-off there is 29 to 30
  /// degrees (device recordings).
  static double contentFunnel(double along) =>
      math.min(25, 0.8 * along.abs() + 10);

  final _velocities = List<double>.filled(3, 0);
  final _accelerations = List<double>.filled(3, 0);
  double? _positionTime;
  double _position = 0;
  double? _rawVelocity;
  double _panVelocity = 0;
  double _previousVelocity = 0;
  double _previousAcceleration = 0;
  double _previousDisplacement = 0;
  double _previousTime = 0;
  double _attemptTime = 0;
  bool _changed = false;
  bool _flick = true;
  int _sampleCount = 0;
  double _averageVelocity = 0;
  double _averageAcceleration = 0;

  /// The number of accepted statistics samples, including recognition.
  int get sampleCount => _sampleCount;

  double get _currentVelocity => _panVelocity / width;

  /// The last accepted pan speed in page widths per second.
  double get velocity => _previousVelocity;

  /// The initial settle speed, including an uninterrupted fast flick.
  double get settleVelocity => velocity * (_flick ? flickBoost : 1);

  /// The mean of the last three accepted speeds, in widths per second.
  double get averageVelocity => _averageVelocity;

  /// The mean of the last three limited accelerations, in widths/s^2.
  double get averageAcceleration => _averageAcceleration;

  /// Records a pointer position, including movement before recognition.
  /// A lift does not add a position: UIKit preserves the last move speed.
  void addPosition(double t, double x) {
    final previous = _positionTime;
    if (previous != null) {
      final dt = t - previous;
      if (dt > 0) {
        final raw = dt >= 0.001 ? (x - _position) / dt : 0.0;
        final old = _rawVelocity;
        _panVelocity = old == null ? raw : 0.2 * raw + 0.8 * old;
        _rawVelocity = raw;
      }
    }
    _positionTime = t;
    _position = x;
  }

  /// Starts statistics at recognition, with the current drag [progress].
  void begin(double t, {double progress = 0}) {
    _previousTime = t;
    _attemptTime = t;
    _previousDisplacement = progress;
    _previousVelocity = _currentVelocity;
    _previousAcceleration = 0;
    _averageVelocity = _currentVelocity;
    _averageAcceleration = 0;
    _velocities.fillRange(0, 3, 0);
    _accelerations.fillRange(0, 3, 0);
    _velocities[0] = _currentVelocity;
    _sampleCount = 1;
    _changed = false;
    _flick = true;
  }

  /// Samples movement or a lift at [t], with the actual page [progress].
  /// Set [ending] for a lift so a never-updated drag cannot complete.
  void update(double t, double progress, {bool ending = false}) {
    if (_sampleCount == 0) return;
    if (!ending && t > _attemptTime) _changed = true;
    final attempt = t - _attemptTime;
    _attemptTime = t;
    final displacement = progress < 0 ? 0.0 : progress;
    if (attempt < 0.01 &&
        (attempt <= 0.001 || displacement == _previousDisplacement)) {
      return;
    }
    final dt = t - _previousTime;
    if (dt <= 0) return;
    final v = _currentVelocity;
    final acceleration = (v - _previousVelocity) / dt;
    final limited =
        _previousAcceleration +
        (acceleration - _previousAcceleration).clamp(-5.0, 5.0);
    final slot = _sampleCount % 3;
    final count = math.min(3, _sampleCount);
    final divisor = math.min(3, _sampleCount + 1);
    _averageVelocity =
        (v +
            _averageVelocity * count -
            (_sampleCount >= 3 ? _velocities[slot] : 0)) /
        divisor;
    _averageAcceleration =
        (limited +
            _averageAcceleration * count -
            (_sampleCount >= 3 ? _accelerations[slot] : 0)) /
        divisor;
    if (_averageVelocity.abs() < flickThreshold) _flick = false;
    _velocities[slot] = v;
    _accelerations[slot] = limited;
    _previousVelocity = v;
    _previousAcceleration = limited;
    _previousDisplacement = displacement;
    _previousTime = t;
    _sampleCount++;
  }

  /// Whether the page released at [progress] completes its pop.
  bool shouldPop(double progress) {
    if (!_changed) return false;
    if (_sampleCount < 3) return _averageVelocity > 0;
    final projected =
        progress +
        predictionTime * _averageVelocity +
        0.5 * predictionTime * predictionTime * _averageAcceleration;
    return projected > math.min(predictionDistance / width, predictionFraction);
  }
}

/// The motion of a pushed page, which the navigator's shared bar and the
/// page below follow through [progress].
abstract class PageMotion extends Motion with Presented {
  @override
  double get minFrameRate => uikitMinFrameRate;

  /// How far the page has come in, 0 hidden to 1 shown: a slide's
  /// progress, a zoom's reach.
  double get progress;

  /// Whether the page cross-fades instead of sliding.
  bool get fades => false;

  /// Whether the page is shown or opening, not leaving.
  bool get isShown;

  /// The time a navigation transition counts from, shared by the page's
  /// slide and the bar: the push or pop [call], unless the first frame
  /// after it came more than a display period later, in which case the
  /// motion starts one period before that frame, so a slow first frame
  /// delays the motion and skips none of it (navigation pages passport).
  /// Without a frame period yet, the call.
  static double transitionOrigin({
    required double call,
    required double firstFrame,
    required double? framePeriod,
  }) => framePeriod == null ? call : math.max(call, firstFrame - framePeriod);

  /// Starts at [t] the open that [open] committed: the first frame after
  /// the push picks [t] ([transitionOrigin]).
  void start(double t);

  /// Shows the page in place at [t], without a transition, as a
  /// navigator's first page stands.
  void showInPlace(double t);
}

/// A page's slide on and off the stack, its cross-fade for Prefer
/// Cross-Fade Transitions and the finger of its interactive pop.
///
/// [open] waits for [start]. A finger takes the page with [hold], moves it
/// with [drag] and lets it go with [release]; a leave asked for while the
/// finger holds waits for the release, which then takes the page out.
/// Android's predictive back moves the page as the finger does, its
/// progress the travel: a commit lets the page go toward the pop at the
/// gesture's speed, a cancel sends it back as a refused pop does.
final class PageSlideMotion extends PageMotion with PredictiveBack {
  /// The page's width, which sets how close to its end the slide rests.
  double width = 400;

  /// Whether a push or pop without a finger cross-fades.
  bool crossFades = false;

  /// Called when a page a finger let go of has come back, or leaves
  /// before it did: the interaction the finger began ends.
  VoidCallback? onReturned;

  late final _slide = own(
    MotionValue<double>(0, spring: NavigationTuning.pushSpring),
    rest: () => MotionRest.length / width,
  );
  late final _fade = own(TimedValue(0));
  bool _fades = false;
  bool _shown = false;
  bool _started = false;
  bool _held = false;
  bool _returning = false;

  @override
  double get progress => _fades ? _fade.valueAt(now) : _slide.valueAt(now);

  @override
  bool get fades => _fades;

  @override
  bool get isShown => _shown;

  /// Whether a finger may take the page for an interactive pop now.
  bool get takesSwipe =>
      _shown && (_returning || presence == PresenceStatus.shown);

  @override
  bool get holds => _held || (_shown && !_started);

  @override
  PresenceStatus get presence {
    final arrived = _arrived;
    if (_shown) return arrived ? PresenceStatus.shown : PresenceStatus.opening;
    return arrived ? PresenceStatus.hidden : PresenceStatus.leaving;
  }

  // A slide ends where it first reaches its end, as the interactive
  // spring's overshoot does, or where it rests.
  bool get _arrived {
    if (holds) return false;
    final end = _shown ? 1.0 : 0.0;
    if (_fades) return _fade.target == end && _fade.restsAt(now);
    final p = _slide.valueAt(now);
    return (_shown ? p >= 1 : p <= 0) ||
        (_slide.target == end &&
            _slide.restsAt(now, MotionRest.length / width) &&
            _slide.nextDue == null);
  }

  @override
  void open(double t) {
    advance(t);
    _shown = true;
    _started = false;
    changed();
  }

  @override
  void start(double t) {
    advance(t);
    _started = true;
    _move(t, 1);
  }

  @override
  void showInPlace(double t) {
    advance(t);
    _started = true;
    _fades = false;
    _slide.snap(t, 1);
  }

  @override
  bool leave(double t, DismissTrigger trigger) {
    advance(t);
    _shown = false;
    _started = true;
    _endReturn();
    final heading = _fades ? _fade.target : _slide.target;
    if (!_held && heading != 0) {
      _move(t, 0);
    } else {
      changed();
    }
    return true;
  }

  void _move(double t, double to) {
    final from = _fades ? _fade.valueAt(t) : _slide.valueAt(t);
    if (crossFades) {
      _fades = true;
      _fade.snap(t, from);
      _fade.animate(
        t,
        to,
        duration: NavigationTuning.crossFadeDuration,
        curve: NavigationTuning.crossFadeCurve,
      );
      return;
    }
    if (_fades) {
      _fades = false;
      _slide.snap(t, from);
    }
    _slide.setVelocity(
      t,
      to > from
          ? NavigationTuning.pushVelocity
          : -NavigationTuning.pushVelocity,
    );
    _slide.retarget(t, to, spring: NavigationTuning.pushSpring);
  }

  /// A finger takes the page at [t].
  void hold(double t) {
    advance(t);
    if (_fades) {
      _slide.snap(t, _fade.valueAt(t));
      _fades = false;
    }
    _held = true;
    _returning = false;
    changed();
  }

  /// The finger has dragged the page [travel] widths toward the pop by
  /// [t]; past either end the page rubber bands.
  void drag(double t, double travel) {
    advance(t);
    _slide.snap(t, 1 - NavigationTuning.band.show(travel));
  }

  /// The finger lets go at [t], the page moving toward the pop at
  /// [velocity] widths a second: it heads out when [pops] or when a leave
  /// came while the finger held, back to full screen otherwise.
  void release(double t, {required bool pops, required double velocity}) {
    advance(t);
    _held = false;
    _slide.setVelocity(t, -velocity);
    if (pops || !_shown) {
      _slide.retarget(t, 0, spring: NavigationTuning.interactiveSpring);
      changed();
    } else {
      stay(t);
    }
  }

  /// Sends the page back to full screen at [t]: a pop the finger asked for
  /// was refused.
  void stay(double t) {
    advance(t);
    _slide.retarget(t, 1, spring: NavigationTuning.interactiveSpring);
    _returning = true;
  }

  @override
  void backStarted(double t) => hold(t);

  @override
  void backMoved(double t, double progress) => drag(t, progress);

  @override
  void backEnded(double t, {required bool commits, required double velocity}) {
    if (commits) {
      release(t, pops: true, velocity: velocity);
      return;
    }
    // The route ends the gesture once the page rests, as it does for any
    // presentation; the page returns without ending it a second time.
    advance(t);
    _held = false;
    _slide.setVelocity(t, -velocity);
    _slide.retarget(t, 1, spring: NavigationTuning.interactiveSpring);
    changed();
  }

  @override
  void didAdvance(double t) {
    if (_returning &&
        (_slide.valueAt(t) >= 1 ||
            _slide.restsAt(t, MotionRest.length / width))) {
      _endReturn();
    }
  }

  void _endReturn() {
    if (!_returning) return;
    _returning = false;
    onReturned?.call();
  }
}

import 'dart:math' as math;
import 'dart:ui';

import 'package:apple_liquid_glass/src/motions/flex_integrator.dart';
import 'package:apple_liquid_glass/src/motions/flex_interaction.dart';
import 'package:apple_liquid_glass/src/motions/flex_spec.dart';
import 'package:kinesis/motion.dart';
import 'package:meta/meta.dart';

/// The springs of the small liquid lens.
@internal
abstract final class SmallLensTuning {
  /// The spring that lifts the lens: UIKit's small lens lift tuning, which
  /// with [SmallLens.liftVelocity] fits the device knob and thumb
  /// recordings (peak 1.12).
  static const liftSpring = Spring.response(0.27, dampingRatio: 0.625);

  /// The spring that fades the glass back to solid on landing, fitted to
  /// device recordings.
  static const unliftSpring = Spring.response(0.4);

  /// The spring that shrinks the lens on landing, fitted to device
  /// recordings: underdamped, so the lens dips under its rest size.
  static const sizeUnliftSpring = Spring.response(0.48, dampingRatio: 0.7);

  /// The spring the stretch follows its target on: [FlexSpec.smallLoupe]'s
  /// tracking spring.
  static final stretchSpring = FlexSpec.smallLoupe.trackingSpring;
}

/// The small liquid lens of a switch knob or a slider thumb.
///
/// A touch lifts it on a slightly bouncy spring (it grows and turns from
/// its solid platter into clear glass); the landing waits at least [hangTime]
/// after the lift, fades the glass back on a critically damped spring and
/// shrinks the lens on its own underdamped spring, so it dips below its
/// rest size before it settles. While it moves, the lens deforms by
/// UIKit's flex movement law for a loupe of its size
/// ([FlexSpec.loupeForSize]): speeding up it stretches along its
/// motion, squashes across it and its trailing edge lags ([shift]), each
/// eased into the loupe's movement bounds. Read from UIKit, notes
/// private; fed UIKit's own filtered motion, the law reproduces the
/// deformation UIKit records on switch knobs and slider thumbs to 1e-4 -
/// 4e-3 rms (device recordings).
///
/// The owner gives the lens position as a function of time and calls
/// [follow] whenever that course changes; the stretch filter steps once
/// per frame of [frameRate] in motion time, at the position of each
/// frame, until the lens is undeformed and the position still. UIKit's
/// filters weigh each frame the same whatever the frame rate, so the
/// stretch reacts twice as fast at 120 Hz as at 60 Hz. The outputs can be
/// read at any time.
///
/// Under Reduce Motion (the motion's [Motion.traits]) the lens never lifts,
/// as UIKit's does (read from UIKit, notes private), and never stretches,
/// an approximation that is not measured.
///
/// The lift and size rest within a visible step; the deformation rests
/// once its filter is still, and comes to rest undeformed with the filter
/// primed at the position.
final class SmallLens extends Motion {
  /// Creates a lens that rests at [restSize] and lifts to [liftedSize],
  /// filtering its motion at [frameRate] frames per second, or at the
  /// frame rate of the clock that steps it when [frameRate] is null, at
  /// [position].
  SmallLens({
    required this.restSize,
    required this.liftedSize,
    this.frameRate = 120,
    double Function(double t)? position,
  }) : _position = position ?? _resting {
    _loop = own(_LensLoop(this, rate: frameRate));
  }

  static double _resting(double t) => 0;

  /// The resting size of the lens.
  final Size restSize;

  /// The size of the fully lifted lens.
  final Size liftedSize;

  /// The frames per second of motion time the stretch filter steps at:
  /// 120 for a ProMotion display, 60 for a 60 Hz one; null for the rate of
  /// the clock that steps the lens.
  final double? frameRate;

  /// The lift's starting speed, in progress per second, fitted to device
  /// recordings; it applies only to a lens at rest.
  static const double liftVelocity = 18;

  /// The shortest time, in seconds, a lifted lens stays lifted: UIKit's
  /// lens tuning (read from UIKit, notes private).
  static const double hangTime = 0.22;

  late final _progress = own(
    MotionValue<double>(0, spring: SmallLensTuning.liftSpring),
    rest: _opacity,
  );
  late final _size = own(
    MotionValue<double>(0, spring: SmallLensTuning.liftSpring),
    rest: _sizeRest,
  );
  late final _scaleX = own(
    MotionValue<double>(1, spring: SmallLensTuning.stretchSpring),
    rest: _scaleRest,
  );
  late final _scaleY = own(
    MotionValue<double>(1, spring: SmallLensTuning.stretchSpring),
    rest: _scaleRest,
  );
  late final _drift = own(
    MotionValue<double>(0, spring: SmallLensTuning.stretchSpring),
    rest: _length,
  );
  late final _LensLoop _loop;
  Size? _loupeSize;
  FlexSpec _loupe = FlexSpec.smallLoupe;

  final double Function(double t) _position;
  final FlexIntegrator _flex = FlexIntegrator();
  double _liftStart = -double.infinity;
  double? _previous;
  static const _landing = #landing;

  static double _opacity() => MotionRest.opacity;
  static double _length() => MotionRest.length;
  double _scaleRest() => MotionRest.scale(liftedSize.width);

  /// Seconds the size trails the lift progress by: one frame.
  double get sizeLag => _loop.frame;

  /// The rest of the lift's size progress: a swing that grows the lens by
  /// less than [MotionRest.length].
  double _sizeRest() =>
      MotionRest.length /
      math.max(
        math.max(
          liftedSize.width - restSize.width,
          liftedSize.height - restSize.height,
        ),
        1,
      );

  /// Whether the lens is lifted or lifting.
  bool get isLifted => _progress.target == 1;

  /// Lifts the lens at time [t], carrying its current value and velocity.
  /// The measured initial velocity applies only to a spring at rest.
  void lift(double t) {
    unschedule(_landing);
    if (isLifted || traits.reduceMotion) return;
    _liftStart = t;
    follow(t);
    final progressResting =
        _progress.restsAt(t, MotionRest.opacity) && _progress.nextDue == null;
    _progress.retarget(t, 1, spring: SmallLensTuning.liftSpring);
    if (progressResting) _progress.setVelocity(t, liftVelocity);
    final at = t + sizeLag;
    final sizeResting = _size.restsAt(at, _sizeRest()) && _size.nextDue == null;
    _size.retarget(at, 1, spring: SmallLensTuning.liftSpring);
    if (sizeResting) _size.setVelocity(at, liftVelocity);
  }

  /// Lands the lens at time [t], or once it has hung for [hangTime].
  void unlift(double t) {
    if (!isLifted) return;
    final due = math.max(t, _liftStart + hangTime);
    if (due <= t) {
      _land(t);
    } else if (due <= now) {
      // A release stamped before the cursor lands at its own time.
      _land(due);
    } else {
      at(due, _land, slot: _landing);
    }
  }

  void _land(double t) {
    unschedule(_landing);
    follow(t);
    _progress.retarget(t, 0, spring: SmallLensTuning.unliftSpring);
    _size.retarget(t, 0, spring: SmallLensTuning.sizeUnliftSpring);
  }

  /// Tells the lens that its position's course changed at [t], so the
  /// stretch filter follows it again.
  void follow(double t) => _loop.wake(t);

  void _sample(double t, double position) {
    final previous = _previous ?? position;
    final af = _flex.step(previous, _loop.frame);
    if (traits.reduceMotion) {
      _scaleX.retarget(t, 1);
      _scaleY.retarget(t, 1);
      _drift.retarget(t, 0);
    } else {
      final lens = size(t);
      if (lens != _loupeSize) {
        _loupeSize = lens;
        _loupe = FlexSpec.loupeForSize(lens);
      }
      final v = FlexInteraction.withMovement(
        FlexInteraction.rest,
        spec: _loupe,
        size: lens,
        acceleration: Offset(af, 0),
        velocity: Offset(_flex.vf, 0),
      );
      _scaleX.retarget(t, v.scaleX);
      _scaleY.retarget(t, v.scaleY);
      _drift.retarget(t, v.driftX);
    }
    _previous = position + shift(t);
  }

  /// Primes the deformation loop at [position] after a discontinuous
  /// programmatic move or a relayout, restoring an undeformed lens.
  void resetFlex(double t, double position) {
    _previous = position;
    _flex.reset(position);
    _scaleX.snap(t, 1);
    _scaleY.snap(t, 1);
    _drift.snap(t, 0);
  }

  /// The lift progress at time [t]: 0 solid and resting, 1 clear and
  /// lifted; it may overshoot slightly.
  double progress(double t) => _progress.valueAt(t);

  /// The lens size at time [t], stretch excluded.
  Size size(double t) {
    final q = _size.valueAt(t);
    return Size(
      restSize.width + (liftedSize.width - restSize.width) * q,
      restSize.height + (liftedSize.height - restSize.height) * q,
    );
  }

  /// The stretch along the track at time [t].
  double scaleX(double t) => _scaleX.valueAt(t);

  /// The squash across the track at time [t].
  double scaleY(double t) => math.max(1e-6, _scaleY.valueAt(t));

  /// How far the lens shows shifted along the track at time [t]: its
  /// trailing edge lags while it speeds up. The drift times the scale, as
  /// UIKit scales the drifted lens.
  double shift(double t) => _drift.valueAt(t) * _scaleX.valueAt(t);

  // Whether the deformation is still at [t], with nothing left to follow:
  // undeformed, its targets at rest, and the position no further than a
  // visible step from where the next frame samples it.
  bool _still(double t) {
    final scale = _scaleRest();
    const length = MotionRest.length;
    return (_scaleX.target - 1).abs() < scale &&
        (_scaleY.target - 1).abs() < scale &&
        _drift.target.abs() < length &&
        _scaleX.restsAt(t, scale) &&
        _scaleY.restsAt(t, scale) &&
        _drift.restsAt(t, length) &&
        (_position(t + _loop.frame) - _position(t)).abs() < length;
  }
}

/// Steps the lens's stretch filter at its frame rate while the lens
/// deforms or its position moves; at rest it primes the filter at the
/// position, undeformed.
final class _LensLoop extends MotionLoop {
  _LensLoop(this._lens, {required super.rate});

  final SmallLens _lens;

  @override
  bool step(double t) {
    _lens._sample(t, _lens._position(t));
    return !_lens._still(t);
  }

  @override
  void restFrom(double t) {
    super.restFrom(t);
    final now = _lens.now;
    _lens.resetFlex(now, _lens._position(now));
  }
}

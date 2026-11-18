import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:meta/meta.dart';

/// How a value travels to its target: a damped spring.
///
/// UIKit: `UISpringTimingParameters`. SwiftUI: `Spring`. Flutter:
/// [SpringDescription].
///
/// A spring has two equivalent forms with an exact mapping between them:
/// SwiftUI's perceptual [duration] and [bounce] ([Spring.new]) and UIKit's
/// [response] and [dampingRatio] ([Spring.response]). A bounce of 0 is
/// critically damped, above 0 overshoots, below 0 is overdamped; the damping
/// ratio is `1 - bounce` for a bounce of 0 or more and `1 / (1 + bounce)`
/// below it.
///
/// Besides the physics a spring carries what UIKit keeps beside it: the
/// [tracking] spring used while a finger drives the value, the retarget
/// [impulse], the release [projection] and a [reduced] alternative for
/// Reduce Motion.
@immutable
class Spring {
  /// Creates a spring from SwiftUI's perceptual [duration] and [bounce].
  const Spring({
    Duration this._duration = const Duration(milliseconds: 500),
    double this._bounce = 0,
    this.tracking,
    this.impulse = 0,
    this.projection = normalProjection,
    this.reduced,
  }) : _response = null,
       _dampingRatio = null,
       isImmediate = false;

  /// Creates a spring from UIKit's [response], the undamped period in
  /// seconds, and [dampingRatio], where 1 is critically damped and below 1
  /// overshoots.
  const Spring.response(
    double this._response, {
    double this._dampingRatio = 1,
    this.tracking,
    this.impulse = 0,
    this.projection = normalProjection,
    this.reduced,
  }) : _duration = null,
       _bounce = null,
       isImmediate = false;

  const Spring._immediate()
    : _response = 0,
      _dampingRatio = 1,
      _duration = null,
      _bounce = null,
      tracking = null,
      impulse = 0,
      projection = 0,
      reduced = null,
      isImmediate = true;

  /// Linearly interpolates response and damping ratio between [a] and [b].
  ///
  /// The result carries the physics only: no tracking spring, impulse or
  /// Reduce Motion alternative, and the default [projection].
  factory Spring.lerp(Spring a, Spring b, double t) => Spring.response(
    a.response + (b.response - a.response) * t,
    dampingRatio: a.dampingRatio + (b.dampingRatio - a.dampingRatio) * t,
  );

  /// The [projection] of `UIScrollView.DecelerationRate.normal`: a rate of
  /// 0.998 per millisecond projects `0.998 / (1000 * 0.002)` seconds ahead.
  static const double normalProjection = 0.499;

  /// A change that takes no time: the value jumps to its target.
  static const Spring immediate = Spring._immediate();

  /// SwiftUI's `.smooth`: 0.5 s, no bounce.
  static const Spring smooth = Spring();

  /// SwiftUI's `.snappy`: 0.5 s, bounce 0.15.
  static const Spring snappy = Spring(bounce: 0.15);

  /// SwiftUI's `.bouncy`: 0.5 s, bounce 0.3.
  static const Spring bouncy = Spring(bounce: 0.3);

  /// SwiftUI's `.interactiveSpring`: 0.15 s, bounce 0.15, for a value that
  /// follows a finger.
  static const Spring interactive = Spring(
    duration: Duration(milliseconds: 150),
    bounce: 0.15,
  );

  final Duration? _duration;
  final double? _bounce;
  final double? _response;
  final double? _dampingRatio;

  /// Whether the spring takes no time ([immediate]).
  final bool isImmediate;

  /// The spring a value follows while a finger drives it, or null to use
  /// this spring.
  final Spring? tracking;

  /// The duration, in seconds, of the push a changed target gives the
  /// value: its velocity grows by this times the change of target times
  /// the stiffness of the spring it moves on, the [tracking] spring while a
  /// finger drives it. UIKit's retarget impulse; 0 for none. A tracking
  /// spring's own impulse is not used.
  final double impulse;

  /// How far ahead, in seconds at the current velocity, a released value
  /// is projected to land (`Projection.of`), as UIKit projects a
  /// flick through a deceleration rate `r` per millisecond:
  /// `r / (1000 * (1 - r))` seconds.
  final double projection;

  /// The spring to use under Reduce Motion, or null to use this spring.
  final Spring? reduced;

  /// The undamped period, in seconds.
  double get response =>
      _response ?? _duration!.inMicroseconds / Duration.microsecondsPerSecond;

  /// The damping ratio; 1 is critically damped.
  double get dampingRatio {
    final ratio = _dampingRatio;
    if (ratio != null) return ratio;
    final bounce = _bounce!;
    return bounce >= 0 ? 1 - bounce : 1 / (1 + bounce);
  }

  /// SwiftUI's perceptual duration: the [response].
  Duration get duration =>
      _duration ?? Duration(microseconds: (response * 1e6).round());

  /// SwiftUI's bounce: `1 - dampingRatio` up to critical damping and
  /// `1 / dampingRatio - 1` beyond it.
  double get bounce {
    final bounce = _bounce;
    if (bounce != null) return bounce;
    final ratio = dampingRatio;
    return ratio <= 1 ? 1 - ratio : 1 / ratio - 1;
  }

  /// The angular frequency of the undamped spring, in radians per second.
  double get omega => 2 * math.pi / response;

  /// The stiffness for a unit mass.
  double get stiffness => omega * omega;

  /// The damping coefficient for a unit mass.
  double get damping => 2 * dampingRatio * omega;

  /// The spring used while a finger drives the value.
  Spring get trackingSpring => tracking ?? this;

  /// The physical description of this spring for a unit mass.
  ///
  /// A damping ratio within 1e-9 of 1 is described as exactly critical: the
  /// SDK picks its solution by the sign of the discriminant, and next to
  /// critical damping its overdamped form loses about 1e-8 of the distance
  /// to cancellation.
  SpringDescription get description {
    final ratio = (dampingRatio - 1).abs() <= 1e-9 ? 1.0 : dampingRatio;
    return SpringDescription(
      mass: 1,
      stiffness: stiffness,
      damping: 2 * ratio * omega,
    );
  }

  /// This spring, or its [reduced] alternative when [reduceMotion] holds.
  Spring resolve({required bool reduceMotion}) =>
      reduceMotion ? (reduced ?? this) : this;

  /// A copy of this spring with the given [tracking], [impulse],
  /// [projection] and [reduced] replaced; [Spring.immediate] returns
  /// itself.
  Spring copyWith({
    Spring? tracking,
    double? impulse,
    double? projection,
    Spring? reduced,
  }) {
    if (isImmediate) return this;
    return Spring.response(
      response,
      dampingRatio: dampingRatio,
      tracking: tracking ?? this.tracking,
      impulse: impulse ?? this.impulse,
      projection: projection ?? this.projection,
      reduced: reduced ?? this.reduced,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Spring &&
      other.isImmediate == isImmediate &&
      other.response == response &&
      other.dampingRatio == dampingRatio &&
      other.tracking == tracking &&
      other.impulse == impulse &&
      other.projection == projection &&
      other.reduced == reduced;

  @override
  int get hashCode => Object.hash(
    isImmediate,
    response,
    dampingRatio,
    tracking,
    impulse,
    projection,
    reduced,
  );

  @override
  String toString() => isImmediate
      ? 'Spring.immediate'
      : 'Spring.response($response, dampingRatio: $dampingRatio)';
}

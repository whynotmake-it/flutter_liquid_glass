import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:kinesis/src/motion/part.dart';
import 'package:kinesis/src/motion/spring.dart';
import 'package:kinesis/src/motion/value.dart';

/// The springs of a rect, per axis: the center on one, the width and the
/// height on their own (a bar's capsule pulse, a zoomed page's measured
/// height spring).
@immutable
final class RectSprings {
  /// Creates springs for the [center], the [width] and the [height]; an
  /// axis without a spring moves on the center's.
  const RectSprings({
    required this.center,
    this._width,
    this._height,
  });

  /// One [spring] for every axis.
  const RectSprings.all(Spring spring) : this(center: spring);

  /// The spring of the center.
  final Spring center;

  final Spring? _width;
  final Spring? _height;

  /// The spring of the width.
  Spring get width => _width ?? center;

  /// The spring of the height.
  Spring get height => _height ?? center;

  @override
  bool operator ==(Object other) =>
      other is RectSprings &&
      other.center == center &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(center, width, height);
}

/// A rect on [RectSprings]: its center, width and height each on their own
/// spring. With one spring for all three it moves as a `MotionValue<Rect>`
/// would.
///
/// ```dart
/// late final frame = own(MotionRect(Rect.zero, springs: .all(.snappy)));
/// frame.retarget(t, measured);
/// ```
final class MotionRect extends MotionPart {
  /// Creates a rect resting at [value] on [springs].
  MotionRect(Rect value, {required this.springs})
    : _center = MotionValue<Offset>(value.center, spring: springs.center),
      _width = MotionValue<double>(value.width, spring: springs.width),
      _height = MotionValue<double>(value.height, spring: springs.height);

  /// The springs a retarget without its own moves on.
  final RectSprings springs;

  final MotionValue<Offset> _center;
  final MotionValue<double> _width;
  final MotionValue<double> _height;

  /// Where the rect is heading.
  Rect get target => Rect.fromCenter(
    center: _center.target,
    width: _width.target,
    height: _height.target,
  );

  /// Sends the rect toward [to] from its state at [t], on [springs] when
  /// given, at `t + delay`.
  void retarget(
    double t,
    Rect to, {
    RectSprings? springs,
    bool tracking = false,
    double delay = 0,
  }) {
    final s = springs ?? this.springs;
    _center.retarget(
      t,
      to.center,
      spring: s.center,
      tracking: tracking,
      delay: delay,
    );
    _width.retarget(
      t,
      to.width,
      spring: s.width,
      tracking: tracking,
      delay: delay,
    );
    _height.retarget(
      t,
      to.height,
      spring: s.height,
      tracking: tracking,
      delay: delay,
    );
    changed();
  }

  /// Moves the whole course by the change from [from] to [to], keeping the
  /// velocities and the time left: a rect in flight whose layout moved
  /// under it.
  @internal
  void shift(Rect from, Rect to) {
    _center.shift(from.center, to.center);
    _width.shift(from.width, to.width);
    _height.shift(from.height, to.height);
    changed();
  }

  /// Puts the rect at [value] at [t], keeping its target and the velocity
  /// each axis had there: a drawn offset baked into the springs.
  void setPresentation(double t, Rect value) {
    _center.setPresentation(t, value.center, velocity: _center.velocityAt(t));
    _width.setPresentation(t, value.width, velocity: _width.velocityAt(t));
    _height.setPresentation(t, value.height, velocity: _height.velocityAt(t));
    changed();
  }

  /// Puts the rect at rest on [value] at [t].
  void snap(double t, Rect value) {
    _center.snap(t, value.center);
    _width.snap(t, value.width);
    _height.snap(t, value.height);
    changed();
  }

  /// The rect at [t].
  Rect valueAt(double t) => Rect.fromCenter(
    center: _center.valueAt(t),
    width: _width.valueAt(t),
    height: _height.valueAt(t),
  );

  /// A bound on how far any edge still swings from the target from [t] on.
  double reach(double t) => math.max(
    _center.reach(t),
    math.max(_width.reach(t), _height.reach(t)) / 2,
  );

  @override
  double? restTime([double? tolerance]) {
    final c = _center.restTime(tolerance);
    final w = _width.restTime(tolerance);
    final h = _height.restTime(tolerance);
    if (c == null || w == null || h == null) return null;
    return math.max(c, math.max(w, h));
  }

  @override
  bool restsAt(double t, [double? tolerance]) =>
      _center.restsAt(t, tolerance) &&
      _width.restsAt(t, tolerance) &&
      _height.restsAt(t, tolerance);

  @override
  void restFrom(double t) {
    _center.restFrom(t);
    _width.restFrom(t);
    _height.restFrom(t);
  }

  @override
  double? get nextDue {
    final c = _center.nextDue;
    final w = _width.nextDue;
    final h = _height.nextDue;
    double? due;
    if (c != null) due = c;
    if (w != null && (due == null || w < due)) due = w;
    if (h != null && (due == null || h < due)) due = h;
    return due;
  }
}

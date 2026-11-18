import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:kinesis/src/motion/part.dart';

/// A value on timed curves, as Core Animation runs a `CABasicAnimation`:
/// a duration and a curve rather than a spring.
///
/// A plain value turns from where it stands when the next curve starts. An
/// [additive] one jumps its model to the new target and adds a curve from
/// the old target's offset to none, so curves started on top of each other
/// sum, as UIKit's additive animations do.
///
/// ```dart
/// late final fade = own(TimedValue(1));
/// fade.animate(t, 0, duration: 0.5, curve: Curves.easeInOut);
/// ```
final class TimedValue extends MotionPart {
  /// Creates a value resting at [value].
  TimedValue(double value, {this.additive = false})
    : _base = value,
      _target = value;

  /// Whether curves add up instead of replacing each other.
  final bool additive;

  double _base;
  double _target;
  final List<_Curve> _curves = [];

  /// Where the value is heading: the last curve's end.
  double get target => _target;

  /// Runs the value to [to] over [duration] seconds on [curve], starting
  /// at [t] plus [delay].
  ///
  /// A plain value keeps its course until then and turns from where that
  /// course has it; a curve that started at or after that time is dropped.
  void animate(
    double t,
    double to, {
    required double duration,
    Curve curve = Curves.linear,
    double delay = 0,
  }) {
    final start = t + delay;
    if (additive) {
      _curves.removeWhere((c) => c.start + c.duration <= t);
      _curves.add(_Curve(start, duration, curve, _target, to));
    } else {
      final from = valueAt(start);
      _curves.removeWhere((c) => c.start >= start);
      if (_curves.isNotEmpty) {
        final last = _curves.last;
        _curves.clear();
        _curves.add(last);
        _base = last.from;
      }
      _curves.add(_Curve(start, duration, curve, from, to));
    }
    _target = to;
    changed();
  }

  /// Puts the value at rest on [value] at time [t], dropping every curve.
  void snap(double t, double value) {
    _curves.clear();
    _base = value;
    _target = value;
    changed();
  }

  /// The value at [t].
  double valueAt(double t) {
    if (additive) {
      var value = _target;
      for (final c in _curves) {
        value -= (c.to - c.from) * (1 - c.progress(t));
      }
      return value;
    }
    for (var i = _curves.length - 1; i >= 0; i--) {
      final c = _curves[i];
      if (c.start <= t) return c.from + (c.to - c.from) * c.progress(t);
    }
    return _base;
  }

  /// The time the last curve ends: from then on the value sits on [target].
  @override
  double? restTime([double? tolerance]) {
    var end = double.negativeInfinity;
    for (final c in _curves) {
      end = math.max(end, c.start + c.duration);
    }
    return end;
  }

  /// Whether no curve runs at [t]: before a delayed curve starts, the value
  /// holds still until [nextDue].
  @override
  bool restsAt(double t, [double? tolerance]) {
    for (final c in _curves) {
      if (t >= c.start && t < c.start + c.duration) return false;
    }
    return true;
  }

  @override
  void restFrom(double t) {
    if (_curves.any((c) => c.start + c.duration > t)) return;
    _curves.clear();
    _base = _target;
  }

  @override
  double? get nextDue {
    final now = owner?.now ?? double.negativeInfinity;
    double? due;
    for (final c in _curves) {
      if (c.start > now && (due == null || c.start < due)) due = c.start;
    }
    return due;
  }
}

final class _Curve {
  _Curve(this.start, this.duration, this.curve, this.from, this.to);

  final double start;
  final double duration;
  final Curve curve;
  final double from;
  final double to;

  double progress(double t) {
    if (t < start) return 0;
    if (duration <= 0 || t >= start + duration) return 1;
    return curve.transform((t - start) / duration);
  }
}

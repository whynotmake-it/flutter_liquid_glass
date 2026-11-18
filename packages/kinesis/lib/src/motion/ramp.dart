import 'package:flutter/foundation.dart';

/// A piecewise-linear map of a progress: [from] up to [start], [to] from
/// [end] on, a straight line between. A fade that runs over part of a
/// presentation's progress.
///
/// ```dart
/// const rows = Ramp(from: 0, to: 1, start: 0.4, end: 0.9);
/// final opacity = rows.at(presence.progress);
/// ```
@immutable
final class Ramp {
  /// Creates a ramp from [from] at [start] to [to] at [end]. [start] may be
  /// past [end]: the ramp then runs backwards in progress.
  const Ramp({this.from = 0, this.to = 1, this.start = 0, this.end = 1});

  /// The value at and before [start].
  final double from;

  /// The value at and after [end].
  final double to;

  /// The progress where the ramp leaves [from].
  final double start;

  /// The progress where the ramp reaches [to].
  final double end;

  /// The value at [progress]; [from] for a ramp with no span.
  double at(double progress) {
    final span = end - start;
    if (span.abs() < 1e-6) return from;
    final f = ((progress - start) / span).clamp(0.0, 1.0);
    return from + (to - from) * f;
  }

  @override
  bool operator ==(Object other) =>
      other is Ramp &&
      other.from == from &&
      other.to == to &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(from, to, start, end);
}

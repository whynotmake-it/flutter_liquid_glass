import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// A range that resists past its ends: a raw position drawn beyond [min] or
/// [max] shows only part of the way, `x * d * c / (d + c * x)` past the
/// edge for an overshoot `x`.
///
/// UIKit's rubber band: monotonic, approaching [dimension] past the edge
/// asymptotically, with slope [coefficient] at the edge. 0.55 is the classic
/// iOS coefficient. An infinite end never resists.
///
/// ```dart
/// final band = RubberBand(0, travel, dimension: 12);
/// knob.retarget(t, band.show(grab + finger), tracking: true);
/// ```
@immutable
final class RubberBand {
  /// Creates a band from [min] to [max] that resists over [dimension]
  /// pixels past either end.
  const RubberBand(
    this.min,
    this.max, {
    required this.dimension,
    this.coefficient = 0.55,
  }) : assert(min <= max, 'a band runs from min to max');

  /// The lower end; `double.negativeInfinity` for none.
  final double min;

  /// The upper end; `double.infinity` for none.
  final double max;

  /// How far past an end a raw position can ever show.
  final double dimension;

  /// The slope at the edge.
  final double coefficient;

  /// Where [raw] shows: itself inside the range, on the band past it.
  double show(double raw) {
    if (raw < min) return min - _resist(min - raw);
    if (raw > max) return max + _resist(raw - max);
    return raw;
  }

  /// How far past the range [raw] shows, signed: negative below [min],
  /// positive above [max], 0 inside.
  double stretch(double raw) {
    if (raw < min) return -_resist(min - raw);
    if (raw > max) return _resist(raw - max);
    return 0;
  }

  /// The raw position that [show] maps to [shown]: the inverse, for a
  /// finger that grabs a value already out on the band. A shown value at or
  /// past the asymptote maps to the raw position that shows 0.1% short of
  /// it.
  double unshow(double shown) {
    if (shown < min) return min - _unresist(min - shown);
    if (shown > max) return max + _unresist(shown - max);
    return shown;
  }

  double _resist(double over) =>
      over * dimension * coefficient / (dimension + coefficient * over);

  double _unresist(double shown) {
    if (dimension <= 0) return 0;
    final held = math.min(shown, dimension * 0.999);
    return held * dimension / (coefficient * (dimension - held));
  }

  @override
  bool operator ==(Object other) =>
      other is RubberBand &&
      other.min == min &&
      other.max == max &&
      other.dimension == dimension &&
      other.coefficient == coefficient;

  @override
  int get hashCode => Object.hash(min, max, dimension, coefficient);
}

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// Puts frame times on the display's frame grid.
///
/// A frame's time is the vsync time stamp, which jitters by tens of
/// microseconds around the display's period. A motion that computes its
/// coming frames ahead needs those frames' times exactly; on the grid they
/// are.
///
/// A grid starts at a frame and is spaced by the median step of the last
/// steady frames (steps of 4 - 50 ms), fixed for the grid's life; it
/// carries over to the next grid until new steps replace it, so a motion
/// after a pause predicts from its first frame. [snap] moves a time to the
/// nearest node within [reach], so a dropped frame lands on a node a
/// multiple of the period later; otherwise (a pause, a changed or variable
/// rate, a drift, a test's arbitrary pump) the time stays as it is and
/// starts a new grid.
///
/// Fidelity: NEAR. A frame is sampled up to [reach] (1 ms) from its vsync
/// time stamp, typically tens of microseconds, and shown at the same vsync.
@internal
class FrameGrid {
  /// How far, in seconds, a time may move onto the grid.
  static const double reach = 0.001;

  final Float64List _steps = Float64List(8);
  int _count = 0;
  double? _raw;
  double? _anchor;
  double? _period;
  double _last = 0;

  /// The grid's spacing in seconds, or null before three steady steps.
  double? get period => _period;

  /// [t] on the frame grid, or [t] itself when no node is within [reach].
  double snap(double t) {
    final raw = _raw;
    _raw = t;
    if (raw != null) {
      final step = t - raw;
      if (step > 0.004 && step < 0.05) {
        _steps[_count % _steps.length] = step;
        _count++;
      } else if (step != 0) {
        _count = 0;
      }
    }
    final anchor = _anchor;
    final period = _period;
    if (anchor == null || period == null) return _restart(t);
    final k = ((t - anchor) / period).round();
    final node = anchor + k * period;
    if (k < 1 || (node - t).abs() >= reach || node < _last) return _restart(t);
    return _last = (node - t).abs() < 1e-9 ? t : node;
  }

  double _restart(double t) {
    final n = math.min(_count, _steps.length);
    if (n >= 3) {
      final sorted = Float64List.fromList(
        Float64List.sublistView(_steps, 0, n),
      );
      sorted.sort();
      _period = sorted[n ~/ 2];
    }
    _anchor = t;
    return _last = t;
  }
}

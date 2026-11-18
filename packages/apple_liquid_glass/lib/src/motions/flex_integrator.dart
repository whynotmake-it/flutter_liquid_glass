import 'package:meta/meta.dart';

/// UIKit's deformation filter: three one-pole low-passes in a row over a
/// moving surface's position, its velocity and the rate of change of its
/// speed.
///
/// UIKit runs the filter once per rendered frame with a fixed weight of
/// [alpha], whatever the frame interval, so its response is a function of
/// frames rather than of time. Step it from a fixed-rate `MotionLoop` to
/// reproduce that on any host and under any time dilation.
@internal
class FlexIntegrator {
  /// The weight of each new sample in all three filters.
  static const double alpha = 0.3;

  /// The filtered position, or null until the filter is primed by
  /// [reset] or by its first [step].
  double? pf;

  /// The filtered velocity.
  double vf = 0;

  /// The filtered rate of change of the speed `|v|`.
  double af = 0;

  /// Primes the filter at rest on [position].
  void reset(double position) {
    pf = position;
    vf = 0;
    af = 0;
  }

  /// Feeds the visible position of the previous frame, [dt] seconds per
  /// frame, and returns the new filtered acceleration [af].
  ///
  /// An unprimed filter starts at rest on [previousVisiblePosition].
  double step(double previousVisiblePosition, double dt) {
    final p = pf ?? previousVisiblePosition;
    final np = (1 - alpha) * p + alpha * previousVisiblePosition;
    final nv = (1 - alpha) * vf + alpha * (np - p) / dt;
    final na = (1 - alpha) * af + alpha * (nv.abs() - vf.abs()) / dt;
    pf = np;
    vf = nv;
    af = na;
    return na;
  }
}

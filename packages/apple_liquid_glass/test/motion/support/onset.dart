/// How the device replays meet UIKit's touch stamps.
///
/// A touch row's `t` is the touch's own time stamp (UITouch.timestamp,
/// CLOCK_UPTIME_RAW) and a frame row's `t` is the display link's time
/// stamp, at which the row shows the presentation state (spec/README.md,
/// "Clocks"). morph stamps a pointer at that same time stamp
/// (`MotionClockHost.stamp`), so a replay feeds every touch at its recorded
/// stamp and compares every row at its own: there is no offset to align.
/// A measured delay is therefore counted from the stamp and holds what
/// UIKit spends before it starts: delivery (10.2 - 24.8 ms on the iPhone 16
/// Pro, median ~15; sendEvent rows carry it as `delivered_t`), the work on
/// the main thread that the touch starts, and the frame its animation
/// begins one after.
library;

import 'dart:math' as math;

import 'package:apple_liquid_glass/src/motions/lens_motion.dart';
import 'package:apple_liquid_glass/src/motions/lens_tuning.dart';
import 'package:flutter/physics.dart';
import 'package:kinesis/motion.dart';

import 'trace.dart';

/// One frame of the iPhone 16 Pro's 120 Hz display, in seconds.
const double deviceFrame = 1 / 120;

/// How far apart UIKit delivers two touches after their stamps, in
/// seconds: 10.2 - 24.8 ms on the iPhone 16 Pro (spec/README.md,
/// "Clocks"). A device response fitted from one recording lands within
/// this of the median of its kind.
const double deliverySpread = 0.0146;

/// How much longer UIKit can take to set a lens's lift up on the main
/// thread after one touch than after another, in seconds: the display
/// link's frame after a lifting touch comes 19.5 - 41.7 ms after the one
/// before (tab bar and segmented taps, presses on the selected item; one
/// press 64.9) instead of 8.3. A lens's lift starts within
/// [deliverySpread] plus this of the median of its kind.
const double setupSpread = 0.0222;

/// The time a recorded lens starts lifting after [after]: the start of the
/// lens lift spring fitted by least squares to the lift progress (`lpp`)
/// of [rows] over the next 0.2 s, rows that repeat the previous value
/// skipped (UIKit refreshes the lens about every other 120 Hz frame).
double lensLiftStart(List<TraceFrame> rows, double after) {
  final rising = <TraceFrame>[];
  double? previous;
  for (final f in rows) {
    final lpp = f.opt('lpp');
    if (f.t > after &&
        f.t < after + 0.2 &&
        lpp != null &&
        lpp != previous &&
        lpp < 0.999) {
      rising.add(f);
    }
    previous = lpp;
  }
  final w = LensTuning.tabBar.liftSpring.omega;
  double lift(double t) => t <= 0 ? 0 : 1 - (1 + w * t) * math.exp(-w * t);
  var best = after;
  var bestError = double.infinity;
  for (var start = after; start < after + 0.15; start += 0.0005) {
    var error = 0.0;
    for (final f in rising) {
      error += math.pow(lift(f.t - start) - f.opt('lpp')!, 2);
    }
    if (error < bestError) {
      bestError = error;
      best = start;
    }
  }
  return best;
}

/// The seconds from a touch's stamps [down] and [up] to the start and the
/// return of a recorded press growth: the step of [spring] to [amplitude]
/// and the return from where it stands on [release] (or [spring]) fitted
/// by least squares to the growth [rows] (time, growth, 0 at rest) from
/// just before the touch to 0.6 s after its release. The return never
/// comes before the start, as in [LensMotion].
({double press, double release}) pressOnsets(
  List<(double, double)> rows,
  double down,
  double up, {
  required Spring spring,
  required double amplitude,
  Spring? release,
}) {
  final window = [
    for (final row in rows)
      if (row.$1 >= down - 0.03 && row.$1 <= up + 0.6) row,
  ];
  final rise = SpringSimulation(spring.description, 0, amplitude, 0);
  final back = release ?? spring;
  double error(double press, double releaseLag) {
    final start = down + press;
    final end = math.max(up + releaseLag, start);
    final fall = SpringSimulation(
      back.description,
      rise.x(end - start),
      0,
      rise.dx(end - start),
    );
    var sum = 0.0;
    for (final (t, growth) in window) {
      final model = t <= start
          ? 0.0
          : t <= end
          ? rise.x(t - start)
          : fall.x(t - end);
      sum += (model - growth) * (model - growth);
    }
    return sum;
  }

  var best = (press: 0.0, release: 0.0);
  var bestError = double.infinity;
  void search(double press0, double release0, double span, double grid) {
    for (var p = press0; p <= press0 + span + 1e-9; p += grid) {
      for (var r = release0; r <= release0 + span + 1e-9; r += grid) {
        final e = error(p, r);
        if (e < bestError) {
          bestError = e;
          best = (press: p, release: r);
        }
      }
    }
  }

  search(0, 0, 0.1, 0.001);
  search(best.press - 0.001, best.release - 0.001, 0.002, 0.00025);
  return best;
}

/// The seconds from a release's stamp [up] to the return of a recorded
/// growth held still at [from]: the step of [spring] from [from] to rest
/// fitted by least squares to the growth [rows] (time, growth) from 0.03 s
/// before the release to 0.6 s after it.
double releaseOnset(
  List<(double, double)> rows,
  double up, {
  required Spring spring,
  required double from,
}) {
  final window = [
    for (final row in rows)
      if (row.$1 >= up - 0.03 && row.$1 <= up + 0.6) row,
  ];
  final fall = SpringSimulation(spring.description, from, 0, 0);
  var best = 0.0;
  var bestError = double.infinity;
  for (var r = 0.0; r <= 0.1 + 1e-9; r += 0.00025) {
    var sum = 0.0;
    for (final (t, growth) in window) {
      final model = t <= up + r ? from : fall.x(t - up - r);
      sum += (model - growth) * (model - growth);
    }
    if (sum < bestError) {
      bestError = sum;
      best = r;
    }
  }
  return best;
}

/// The seconds after its start at which a response [value] of the time
/// since its start first reaches [target], searched within [span].
double timeToReach(
  double Function(double dt) value,
  double target, {
  double span = 0.2,
}) {
  final rising = value(span) > value(0);
  var lo = 0.0;
  var hi = span;
  for (var i = 0; i < 60; i++) {
    final mid = (lo + hi) / 2;
    if ((value(mid) < target) == rising) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return lo;
}

/// The median of [values].
double median(Iterable<double> values) {
  final sorted = values.toList();
  sorted.sort();
  final n = sorted.length;
  return n.isOdd ? sorted[n ~/ 2] : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
}

/// The root mean square of [errors], NaN when there are none.
double rms(Iterable<double> errors) {
  var sum = 0.0;
  var n = 0;
  for (final e in errors) {
    sum += e * e;
    n++;
  }
  return n == 0 ? double.nan : math.sqrt(sum / n);
}

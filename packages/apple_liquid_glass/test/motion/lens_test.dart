import 'dart:math' as math;

import 'package:apple_liquid_glass/src/motions/lens_motion.dart';
import 'package:apple_liquid_glass/src/motions/lens_tuning.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/trace.dart';

const _dir = 'test/fixtures/ios27/lens';

/// One recorded tap on a segmented control and the lens it moved.
class _Tap {
  _Tap(this.down, this.up, this.frames);

  final double down;
  final double up;
  final List<TraceFrame> frames;
}

/// Splits a recording into taps on [control], keeping the lens frames of
/// each tap until the next touch-down.
List<_Tap> _taps(Trace trace, String control) {
  final downs = [
    for (final touch in trace.touches)
      if (touch.phase == 0) touch,
  ];
  final taps = <_Tap>[];
  for (var i = 0; i < downs.length; i++) {
    final start = downs[i].t;
    final end = i + 1 < downs.length ? downs[i + 1].t : double.infinity;
    final up = trace.touches.firstWhere(
      (t) => t.t >= start && t.phase == 3,
      orElse: () => downs[i],
    );
    final frames = [
      for (final f in trace.frames)
        if (f.raw['ctl'] == control &&
            f.cls == '_UILiquidLensView' &&
            f.t >= start - 0.05 &&
            f.t < end)
          f,
    ];
    if (frames.length > 20 && (frames.first.x - frames.last.x).abs() > 5) {
      taps.add(_Tap(start, up.t, frames));
    }
  }
  return taps;
}

/// Replays [tap] through the model and returns the errors per frame.
({double center, double width, double height, double sx, double sy}) _replay(
  _Tap tap, [
  LensTuning tuning = LensTuning.segmented,
  double frameRate = 60,
]) {
  final clean = [
    for (final f in tap.frames)
      if ((f.y - tap.frames.first.y).abs() < 10) f,
  ];
  final rest = clean.first;
  final settled = clean.last;
  // The simulator delivers touches 4 to 36 ms before the motion, and the
  // recorder logs only changed frames, so the start is solved from the
  // first moving frame: the travel step response must reach its offset.
  final moved = clean.firstWhere((f) => (f.x - rest.x).abs() > 0.05);
  final progress = (moved.x - rest.x) / (settled.x - rest.x);
  final start = moved.t - _timeToReach(progress);
  // Anchor the model on the real touch: the delay to the first moving
  // frame is input latency, and the landing counts from the touch.
  final touch = tuning.selectsOnPointerDown ? tap.down : tap.up;
  final delay = math.max<double>(0, start - touch);
  final trigger = start - delay;
  final motion = LensMotion(
    tuning: tuning,
    frameRate: frameRate,
    startDelay: delay,
    slots: [
      (center: rest.x, width: rest.bw),
      (center: settled.x, width: settled.bw),
    ],
    selected: 0,
    height: rest.bh,
  );
  final release = tuning.selectsOnPointerDown
      ? trigger + (tap.up - tap.down)
      : trigger;
  motion.advance(trigger - 0.2);
  motion.pointerDown(
    tuning.selectsOnPointerDown ? trigger : trigger - 0.05,
    settled.x,
  );
  motion.pointerUp(release, settled.x);
  final frames = clean;
  var center = 0.0;
  var width = 0.0;
  var height = 0.0;
  var sx = 0.0;
  var sy = 0.0;
  var n = 0;
  TraceFrame? previous;
  for (final f in frames) {
    final stale = previous != null && previous.x == f.x && previous.bw == f.bw;
    previous = f;
    if (f.t < trigger || f.t > trigger + 1.5) continue;
    motion.advance(f.t);
    // On a 120 Hz iPhone UIKit refreshes the lens geometry about every
    // other frame; a repeated sample is that hold, not motion to match.
    if (stale) continue;
    final size = motion.size;
    center += math.pow(motion.center - f.x, 2);
    width += math.pow(size.width * motion.scaleX - f.w, 2);
    height += math.pow(size.height * motion.scaleY - f.h, 2);
    sx += math.pow(motion.scaleX - f.sx, 2);
    sy += math.pow(motion.scaleY - f.sy, 2);
    n++;
  }
  return (
    center: math.sqrt(center / n),
    width: math.sqrt(width / n),
    height: math.sqrt(height / n),
    sx: math.sqrt(sx / n),
    sy: math.sqrt(sy / n),
  );
}

/// Seconds the travel step response needs to reach [progress].
double _timeToReach(double progress) {
  const spring = LensTuning.segmented;
  final w0 = spring.travelSpring.omega;
  final zeta = spring.travelSpring.dampingRatio;
  final wd = w0 * math.sqrt(1 - zeta * zeta);
  double step(double t) =>
      1 -
      math.exp(-zeta * w0 * t) *
          (math.cos(wd * t) + zeta * w0 / wd * math.sin(wd * t));
  var lo = 0.0;
  var hi = 0.2;
  for (var i = 0; i < 50; i++) {
    final mid = (lo + hi) / 2;
    if (step(mid) < progress) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return lo;
}

/// Replays [tap] and returns rms errors of the undeformed frame: the
/// travel center against the native center minus its drift, and the
/// lifted bounds.
({double center, double width, double height}) _replayFrame(
  _Tap tap,
  LensTuning tuning,
) {
  final clean = _deglitch(tap.frames);
  final rest = clean.first;
  final settled = clean.last;
  double base(TraceFrame f) => f.x - (f.opt('p_driftX') ?? 0);
  final motion = LensMotion(
    tuning: tuning,
    frameRate: 60,
    slots: [
      (center: base(rest), width: rest.bw),
      (center: base(settled), width: settled.bw),
    ],
    selected: 0,
    height: rest.bh,
  );
  final from = base(rest);
  final to = base(settled);
  final moved = clean.firstWhere((f) => (base(f) - from).abs() > 0.3);
  final progress = (base(moved) - from) / (to - from);
  final trigger = moved.t - _timeToReach(progress) - tuning.startDelay;
  motion.advance(trigger - 0.2);
  motion.pointerDown(trigger, to);
  final release = trigger + (tap.up - tap.down);
  var released = false;
  var center = 0.0;
  var width = 0.0;
  var height = 0.0;
  var n = 0;
  for (final f in clean) {
    if (f.t < trigger || f.t > trigger + 1.5) continue;
    if (!released && f.t >= release) {
      motion.pointerUp(release, to);
      released = true;
    }
    motion.advance(f.t);
    center += math.pow(motion.travelCenter - base(f), 2);
    width += math.pow(motion.size.width - f.bw, 2);
    height += math.pow(motion.size.height - f.bh, 2);
    n++;
  }
  return (
    center: math.sqrt(center / n),
    width: math.sqrt(width / n),
    height: math.sqrt(height / n),
  );
}

/// Drops UIKit's tab bar glitch frames: rows reported in bar-local
/// coordinates, either far above the bar or isolated horizontal jumps.
List<TraceFrame> _deglitch(List<TraceFrame> frames) {
  final ys = [for (final f in frames) f.y];
  ys.sort();
  final y = ys[ys.length ~/ 2];
  final level = [
    for (final f in frames)
      if ((f.y - y).abs() < 10) f,
  ];
  return [
    for (var i = 0; i < level.length; i++)
      if (i == 0 ||
          i == level.length - 1 ||
          (level[i].x - (level[i - 1].x + level[i + 1].x) / 2).abs() < 15 ||
          (level[i - 1].x - level[i + 1].x).abs() >= 15)
        level[i],
  ];
}

void main() {
  const cases = {
    'segmented-seg2-tap01.jsonl': ['seg2'],
    'segmented-seg3-taps-AB-BC-CA.jsonl': ['seg3'],
    'segmented-seg5seg4-taps.jsonl': ['seg5', 'seg4'],
    'segmented-narrow-content-content4-taps.jsonl': [
      'segNarrow',
      'segContent',
      'segContent4',
    ],
  };

  test('tab bar taps travel, lift and land like the native lens', () {
    // UIKit's tab bar feeds one frame of bar-local coordinates into its own
    // deformation loop at each lift, which kicks the native drift and
    // scale; that glitch is deliberately not reproduced, so the tab bar is
    // checked on the undeformed frame: travel center and lifted bounds.
    const files = [
      'tabbar2-taps-01-10.jsonl',
      'tabbar3-taps-02-20-01.jsonl',
      'tabbar4-taps-01-13-30-hold2.jsonl',
      'tabbar5-taps-04-41-12.jsonl',
    ];
    var count = 0;
    final failures = <String>[];
    for (final file in files) {
      final trace = Trace.load('$_dir/$file');
      for (final tap in _taps(trace, 'tabbar')) {
        final e = _replayFrame(tap, LensTuning.tabBar);
        count++;
        final label =
            '$file @${tap.down.toStringAsFixed(2)}: center '
            '${e.center.toStringAsFixed(2)} w ${e.width.toStringAsFixed(2)} '
            'h ${e.height.toStringAsFixed(2)}';
        if (e.center > 1.5 || e.width > 2.5 || e.height > 2.5) {
          failures.add(label);
        }
      }
    }
    expect(count, greaterThan(8));
    expect(failures, isEmpty);
  });

  test('segmented taps follow the native lens on a 120 Hz iPhone', () {
    const device = 'test/fixtures/ios27-device/lens';
    const cases = {
      'segmented-seg2-taps.jsonl': ['seg2'],
      'segmented-seg3-taps.jsonl': ['seg3'],
      'segmented-seg5seg4-taps.jsonl': ['seg5', 'seg4'],
      'segmented-narrow-content-content4-taps.jsonl': [
        'segNarrow',
        'segContent',
        'segContent4',
      ],
    };
    var count = 0;
    final failures = <String>[];
    for (final MapEntry(key: file, value: controls) in cases.entries) {
      final trace = Trace.load('$device/$file');
      for (final control in controls) {
        for (final tap in _taps(trace, control)) {
          final e = _replay(tap, LensTuning.segmented, 120);
          count++;
          final label =
              '$file $control @${tap.up.toStringAsFixed(2)}: '
              'center ${e.center.toStringAsFixed(2)} '
              'w ${e.width.toStringAsFixed(2)} '
              'h ${e.height.toStringAsFixed(2)} '
              'sx ${e.sx.toStringAsFixed(4)} sy ${e.sy.toStringAsFixed(4)}';
          if (e.center > 1.6 ||
              e.width > 1.8 ||
              e.height > 0.85 ||
              e.sx > 0.012 ||
              e.sy > 0.009) {
            failures.add(label);
          }
        }
      }
    }
    expect(count, greaterThan(20));
    expect(failures, isEmpty);
  });

  test('segmented taps follow the recorded native lens', () {
    var count = 0;
    final failures = <String>[];
    for (final MapEntry(key: file, value: controls) in cases.entries) {
      final trace = Trace.load('$_dir/$file');
      for (final control in controls) {
        for (final tap in _taps(trace, control)) {
          final e = _replay(tap);
          count++;
          final label =
              '$file $control @${tap.up.toStringAsFixed(2)}: '
              'center ${e.center.toStringAsFixed(2)} '
              'w ${e.width.toStringAsFixed(2)} '
              'h ${e.height.toStringAsFixed(2)} '
              'sx ${e.sx.toStringAsFixed(4)} sy ${e.sy.toStringAsFixed(4)}';
          if (e.center > 1.0 ||
              e.width > 1.6 ||
              e.height > 0.6 ||
              e.sx > 0.01 ||
              e.sy > 0.011) {
            failures.add(label);
          }
        }
      }
    }
    expect(count, 21);
    expect(failures, isEmpty);
  });
}

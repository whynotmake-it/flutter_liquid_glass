import 'dart:math' as math;

import 'package:apple_liquid_glass/src/motions/lens_motion.dart';
import 'package:apple_liquid_glass/src/motions/lens_tuning.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/trace.dart';

const _dir = 'test/fixtures/ios27-device/lens';

/// The center of the recorded tab bars, which swell around it while
/// pressed.
const double _barCenter = 201;

/// The tab centers and resting lens width of the recorded tab bars.
const Map<int, (List<double>, double)> _tabBars = {
  3: ([115, 201, 287], 94),
  5: ([63.5, 132.25, 201, 269.75, 338.5], 77),
};

double _rms(List<double> errors) => errors.isEmpty
    ? double.nan
    : math.sqrt(
        errors.fold<double>(0, (sum, e) => sum + e * e) / errors.length,
      );

/// The errors of one replayed recording.
class _Errors {
  final List<double> scrub = [];
  final List<double> release = [];
  final List<double> lift = [];
  int selected = -1;
  int expected = -1;
}

/// Replays the touches of a file through a lens of a tuning resting in
/// slot 0 of its slots and compares it with the recorded lens of a control.
///
/// The tab bar's lens sits inside the bar, which flexes about
/// [_barCenter] while pressed: it scales and shifts after the finger. The
/// recorded window position is taken back into the bar's own coordinates
/// by the bar's scale the lens bounds show and by the bar's shift, which
/// is UIKit's drift of a bar [barWidth] wide: the width times half the
/// difference of its two scales, in the finger's direction (its flex
/// moves both scales by the same stretch and the drift by that stretch
/// times the width, on one spring; read from UIKit, notes private). The
/// drift of the lens's own deformation is removed too, leaving the travel
/// center. Isolated frames that jump into the bar's own coordinates are a
/// recording glitch of UIKit's tab bar and are dropped.
_Errors _replay(
  String file,
  String control,
  LensTuning tuning,
  List<double> centers,
  double width,
  double height, {
  double barWidth = 0,
}) {
  final trace = Trace.load('$_dir/$file');
  final down = trace.touches.first;
  final up = trace.touches.lastWhere((t) => t.phase == 3);
  final motion = LensMotion(
    tuning: tuning,
    slots: [for (final c in centers) (center: c, width: width)],
    selected: 0,
    height: height,
  );
  motion.advance(down.t - 0.5);
  final ys = [
    for (final f in trace.frames)
      if (f.raw['ctl'] == control) f.y,
  ];
  ys.sort();
  final rest = ys[ys.length ~/ 2];
  final level = [
    for (final f in trace.frames)
      if (f.raw['ctl'] == control &&
          (f.y - rest).abs() < 10 &&
          f.t >= down.t &&
          f.t <= up.t + 0.8)
        f,
  ];
  final frames = [
    for (var i = 0; i < level.length; i++)
      if (i == 0 ||
          i == level.length - 1 ||
          (level[i].x - level[i - 1].x).abs() < 15 ||
          (level[i].x - level[i + 1].x).abs() < 15)
        level[i],
  ];
  final errors = _Errors();
  var travel = 0.0;
  var next = 0;
  double? previous;
  double? previousHeight;
  for (final f in frames) {
    while (next < trace.touches.length && trace.touches[next].t <= f.t) {
      final touch = trace.touches[next++];
      travel = touch.x - down.x;
      switch (touch.phase) {
        case 0:
          motion.pointerDown(touch.t, touch.x);
        case 3:
          motion.pointerUp(touch.t, touch.x);
        case _:
          motion.pointerMove(touch.t, touch.x);
      }
    }
    motion.advance(f.t);
    final stale = previous == f.x;
    previous = f.x;
    if (previousHeight != f.bh) errors.lift.add(motion.size.height - f.bh);
    previousHeight = f.bh;
    if (stale) continue;
    final swell = f.w / (f.bw * f.sx);
    final across = f.h / (f.bh * f.sy);
    final shift = travel.sign * barWidth * (swell - across) / 2;
    final local =
        _barCenter +
        (f.x - _barCenter) / swell -
        shift -
        (f.opt('p_driftX') ?? 0);
    final error = motion.travelCenter - local;
    (f.t < up.t ? errors.scrub : errors.release).add(error);
  }
  errors.selected = motion.selected;
  final last = frames.last.x;
  var best = 0;
  for (var i = 1; i < centers.length; i++) {
    if ((centers[i] - last).abs() < (centers[best] - last).abs()) best = i;
  }
  errors.expected = best;
  return errors;
}

_Errors _tabBar(String file) {
  final count = int.parse(file.substring(6, 7));
  final (centers, width) = _tabBars[count]!;
  return _replay(
    file,
    'tabbar',
    LensTuning.tabBar,
    centers,
    width,
    54,
    barWidth: (centers[1] - centers[0]) * count + 16,
  );
}

void main() {
  test('a scrubbed tab bar lens follows the recorded lens', () {
    // With the bar's shift taken out the releases replay to 0.03 - 0.2 pt
    // (0.11 - 0.3 when the shift was read as the lens's own drag gain).
    const files = {
      'tabbar3-scrub-mid.jsonl': (1.0, 0.25),
      'tabbar3-scrub-pastright.jsonl': (1.3, 0.1),
      'tabbar3-scrub-pastleft.jsonl': (1.35, 0.05),
      'tabbar5-scrub-mid.jsonl': (0.75, 0.15),
      'tabbar5-scrub-pastright.jsonl': (0.8, 0.07),
      'tabbar5-scrub-pastleft.jsonl': (1.35, 0.05),
    };
    final all = <double>[];
    for (final MapEntry(key: file, value: (scrub, release)) in files.entries) {
      final e = _tabBar(file);
      all.addAll(e.scrub);
      expect(e.scrub.length, greaterThan(100), reason: file);
      expect(_rms(e.scrub), lessThan(scrub), reason: '$file scrub');
      expect(_rms(e.release), lessThan(release), reason: '$file release');
      expect(_rms(e.lift), lessThan(0.8), reason: '$file lift');
      expect(e.selected, e.expected, reason: '$file selection');
    }
    expect(_rms(all), lessThan(1.05));
  });

  test('the release picks the tab nearest the finger, not the lens', () {
    for (final file in ['tabbar3-scrub-mid.jsonl', 'tabbar5-scrub-mid.jsonl']) {
      final e = _tabBar(file);
      expect(e.selected, 2, reason: file);
    }
  });

  test('a tap on the selected item lifts it in place', () {
    final cases = {
      'tabbar3-tap-selected.jsonl': _tabBar('tabbar3-tap-selected.jsonl'),
      'tabbar5-tap-selected.jsonl': _tabBar('tabbar5-tap-selected.jsonl'),
      'segmented-seg3-tap-selected.jsonl': _replay(
        'segmented-seg3-tap-selected.jsonl',
        'seg3',
        LensTuning.segmented,
        [80, 200, 320],
        116,
        28,
      ),
    };
    for (final MapEntry(key: file, value: e) in cases.entries) {
      expect(e.lift.length, greaterThan(80), reason: file);
      expect(_rms(e.lift), lessThan(0.6), reason: '$file lift');
      final moved = [...e.scrub, ...e.release];
      expect(_rms(moved), lessThan(0.1), reason: '$file center');
      expect(e.selected, 0, reason: file);
    }
  });
}

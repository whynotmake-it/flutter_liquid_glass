import 'dart:convert';
import 'dart:math' as math;

import 'package:apple_liquid_glass/src/motions/sheet_detent.dart';
import 'package:apple_liquid_glass/src/motions/sheet_motion.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

const _dir = 'test/fixtures/ios27/sheet-drag';
const _deviceDir = 'test/fixtures/ios27-device/sheet-drag';

/// The probe screen: an iPhone 16 Pro (simulator and device), 402 x 874
/// points with a
/// 62 point top and a 34 point bottom safe area.
const double _w = 402;
const double _h = 874;
const double _maximum = _h - 62 - 34;

/// The distance UIKit's sheet pan waits for before the sheet moves; the
/// sheet does not catch up with the finger afterwards.
const double _slop = SheetMotion.dragSlop;

/// One display frame of the 60 Hz simulator recordings: presentation
/// layers are sampled for the frame being prepared.
const double _frame = 1 / 60;

/// The shift of the 120 Hz device recordings: their rows line up with the
/// model as stamped (a shift of one 120 Hz frame doubles the error of the
/// grabber tap and the hold, two frames that of every flick).
const double _deviceFrame = 0;

final _heights = [
  GlassSheetDetent.medium.resolve(_maximum) + 34,
  GlassSheetDetent.large.resolve(_maximum) + 34,
];

class _Capture {
  _Capture(String name, {String dir = _dir, double frame = _frame}) {
    for (final line in Fixtures.lines('$dir/$name.jsonl')) {
      if (line.trim().isEmpty) continue;
      final r = (jsonDecode(line) as Map).cast<String, Object?>();
      double d(String k) => (r[k]! as num).toDouble();
      switch (r['k']) {
        case 'touch':
          touches.add((d('t'), r['phase']! as int, d('y')));
        case 'evt':
          if (r['e'] == 'dismissed') dismissed = true;
        case 'V':
          if (!(d('bw') == _w && d('bh') == _h)) {
            sheet.add((
              t: d('t') + frame,
              top: d('y') - d('h') / 2,
              bottom: d('y') + d('h') / 2,
              w: d('w'),
              bh: d('bh'),
              ratio: (d('h') / d('bh')) / (d('w') / d('bw')),
              area: math.sqrt((d('h') / d('bh')) * (d('w') / d('bw'))),
            ));
          }
      }
    }
  }

  final List<(double, int, double)> touches = [];
  final List<
    ({
      double t,
      double top,
      double bottom,
      double w,
      double bh,
      double ratio,
      double area,
    })
  >
  sheet = [];
  bool dismissed = false;
}

/// Replays the last touch of a capture into a [SheetMotion] resting
/// where the sheet rested before it, and compares the visible top and
/// bottom edges from the touch on. Returns the rms and max error, the
/// detent the model settles on (-1 for dismissed), the recorded one, the
/// rms error of the ratio of the vertical to the horizontal scale and that
/// of the area scale (the floating scale times the touch swell).
({double rms, double max, int model, int recorded, double stretch, double area})
_replay(String name, {String dir = _dir, double frame = _frame}) {
  final cap = _Capture(name, dir: dir, frame: frame);
  final downAt = cap.touches.lastIndexWhere((t) => t.$2 == 0);
  final touches = cap.touches.sublist(downAt);
  final down = touches.first;
  final before = cap.sheet.lastWhere((r) => r.t <= down.$1);
  final largeOnly = name.startsWith('l-');
  final heights = largeOnly ? [_heights.last] : _heights;
  final start = largeOnly || before.bh < 800 ? 0 : 1;
  final motion = SheetMotion(
    heights: heights,
    width: _w,
    initial: start,
    dockedIndex: heights.length - 1,
  );
  motion.present(0);
  motion.advance(down.$1 - 2);
  final rect = motion.atTime(down.$1 - 2).visibleRect(_h);
  if ((rect.top - before.top).abs() > 1) {
    throw StateError('$name rests at ${before.top}, model ${rect.top}');
  }
  var dragging = false;
  var next = 0;
  final errors = <double>[];
  final stretchErrors = <double>[];
  final areaErrors = <double>[];
  void feed(double until) {
    while (next < touches.length && touches[next].$1 <= until) {
      final (t, phase, y) = touches[next];
      if (phase == 0) {
        motion.press(t);
      } else if (phase == 3) {
        if (dragging) {
          final recent = [
            for (final s in touches.sublist(0, next + 1))
              if (s.$1 >= t - 0.06) s,
          ];
          final v = recent.length < 2
              ? 0.0
              : (recent.last.$3 - recent.first.$3) /
                    (recent.last.$1 - recent.first.$1);
          motion.dragEnd(t, v);
        } else {
          motion.unpress(t);
          final top = motion.atTime(t).visibleRect(_h).top;
          if ((y - top) / motion.atTime(t).scale <
              SheetMotion.grabberHitHeight) {
            motion.tapGrabber(t);
          }
        }
      } else if (!dragging && (y - down.$3).abs() > _slop) {
        dragging = true;
        motion.dragStart(t, y);
      } else if (dragging) {
        motion.dragUpdate(t, y);
      }
      next++;
    }
  }

  for (final row in cap.sheet) {
    if (row.t < down.$1) continue;
    feed(row.t);
    motion.advance(row.t);
    final r = motion.atTime(row.t).visibleRect(_h);
    final e = [r.top - row.top, r.bottom - row.bottom];
    stretchErrors.add(motion.atTime(row.t).stretch - row.ratio);
    areaErrors.add(motion.atTime(row.t).scale - row.area);
    if (e.any((double v) => v.abs() > 60) && row.top <= 0.5) continue;
    if (row.top >= _h - 1 && r.top >= _h - 1) continue;
    errors.addAll(e);
  }
  feed(double.infinity);
  final model = motion.isDismissing ? -1 : motion.index;
  final last = cap.sheet.last;
  final recorded = cap.dismissed ? -1 : (last.bh > 800 && !largeOnly ? 1 : 0);
  double rms(List<double> e) =>
      math.sqrt(e.fold<double>(0, (a, b) => a + b * b) / e.length);
  return (
    rms: rms(errors),
    max: errors.fold<double>(0, (a, b) => math.max(a, b.abs())),
    model: model,
    recorded: recorded,
    stretch: rms(stretchErrors),
    area: rms(areaErrors),
  );
}

// Tolerances are the honest spread of what the model leaves out: a long
// drag down slides UIKit's sheet up to 17 points further than the finger's
// travel past the slop (drag-down-far; the stretch, replayed below, puts
// the top edge as far off as the bottom one), the start of a flick
// dismissal varies by up to 0.09 s from flick to flick (fd-1000,
// l-flick-down; the visible part of the slide), and a grabber tap starts
// within 0.045 - 0.065 s of the lift. lfd-800 is left out: its flick sits
// on the projection boundary both ways the bracketing flicks put it
// (0.143 s at 680 pt/s), and UIKit took it to medium.
extension on SheetMotion {
  // As the clock steps a root on screen: advance, then settle at rest.
  SheetMotion atTime(double t) {
    advance(t);
    if (isSettled) settle();
    return this;
  }
}

void main() {
  const cases = <(String, double)>[
    ('hold', 3),
    ('grab-tap', 10),
    ('drag-up-mid', 6),
    ('drag-up-slow', 9),
    ('large-drag-down', 6),
    ('large-drag-down-mid', 6),
    ('drag-down-small', 6),
    ('drag-down-far', 11),
    ('flick-up', 8),
    ('flick-down', 8),
    ('fu-800', 8),
    ('fu-1000', 12),
    ('fd-800', 8),
    ('fd-1000', 25),
    ('l-drag-down', 8),
    ('l-flick-down', 45),
  ];
  group('sheet drags replayed against the iOS 27 simulator', () {
    for (final (name, tolerance) in cases) {
      test(name, () {
        final r = _replay(name);
        expect(r.model, r.recorded, reason: 'settled detent');
        expect(r.rms, lessThan(tolerance));
      });
    }
  });

  // The same probe on the device. Two flicks sit on the decision boundary
  // and are left out: fd-1000 (887 pt/s, 95 pt below medium; the
  // projection lands 9 pt short of half the sheet by the 60 ms finger
  // velocity, yet the next flicks up, 964 and 983 pt/s, dismiss) and
  // lfd-800 (the simulator's boundary case again, which UIKit settled at
  // large on the device and at medium on the simulator).
  const deviceCases = <(String, double)>[
    ('hold', 5),
    ('grab-tap', 6),
    ('drag-up-mid', 6),
    ('drag-up-slow', 6),
    ('large-drag-down', 5),
    ('large-drag-down-mid', 3),
    ('drag-down-small', 5),
    ('drag-down-far', 10),
    ('flick-up', 4),
    ('flick-down', 6),
    ('fu-600', 4),
    ('fu-700', 5),
    ('fu-800', 8),
    ('fu-900', 6),
    ('fu-1000', 6),
    ('fd-600', 6),
    ('fd-800', 8),
    ('fd-900', 8),
    ('fd-1100', 20),
    ('fd-1300', 20),
    ('fd-lift-mid', 26),
    ('l-drag-down', 6),
    ('l-flick-down', 15),
    ('lfd-700', 5),
    ('lfd-900', 8),
    ('lfd-1000', 7),
  ];
  group('sheet drags replayed against an iPhone 16 Pro', () {
    for (final (name, tolerance) in deviceCases) {
      test(name, () {
        final r = _replay(name, dir: _deviceDir, frame: _deviceFrame);
        expect(r.model, r.recorded, reason: 'settled detent');
        expect(r.rms, lessThan(tolerance));
      });
    }
  });

  // The ratio of the vertical to the horizontal scale, 1 for a sheet that
  // keeps its shape: a drag of a floating sheet stretches it (1.027 at 320
  // points held, 1.043 in a 1300 pt/s flick), a sheet docked when the
  // drag began keeps 1. What is left is the ringing after the finger
  // starts and stops and UIKit's two to three frames of lag in a flick;
  // drag-up-slow carries a dropped probe frame.
  group('sheet stretch replayed', () {
    for (final (name, _) in cases) {
      test('simulator $name', () {
        expect(_replay(name).stretch, lessThan(0.0075));
      });
    }
    for (final (name, _) in deviceCases) {
      test('iPhone 16 Pro $name', () {
        final r = _replay(name, dir: _deviceDir, frame: _deviceFrame);
        expect(r.stretch, lessThan(0.007));
      });
    }
  });

  // The area scale, the floating scale times the touch swell: a floating
  // sheet keeps its swell through the drag (0.96837 = 0.9602 x 1.00854 on
  // the device while the finger holds it), fading as the drag docks it,
  // and lets it go with the settle; a sheet docked at the touch never
  // swells, even once the drag has undocked it.
  group('sheet swell replayed', () {
    for (final (name, _) in cases) {
      test('simulator $name', () {
        expect(_replay(name).area, lessThan(0.002));
      });
    }
    for (final (name, _) in deviceCases) {
      test('iPhone 16 Pro $name', () {
        final r = _replay(name, dir: _deviceDir, frame: _deviceFrame);
        expect(r.area, lessThan(0.002));
      });
    }
  });

  test('a drag catching a returning stretch carries it on', () {
    final motion = SheetMotion(
      heights: _heights,
      width: _w,
      initial: 0,
      dockedIndex: 1,
    );
    motion.present(0);
    motion.advance(2);
    const step = 1 / 120;
    var t = 2.0;
    var y = 600.0;
    motion.dragStart(t, y);
    for (var i = 0; i < 16; i++) {
      t += step;
      y -= 1300 * step;
      motion.dragUpdate(t, y);
    }
    motion.dragEnd(t, -1300);
    final peak = motion.atTime(t).stretch;
    expect(peak, greaterThan(1.02));
    final regrab = t + 0.1;
    motion.advance(regrab);
    final before = motion.atTime(regrab).stretch;
    expect(before, greaterThan(1.01));
    expect(motion.atTime(regrab).dock, lessThan(1));
    motion.dragStart(regrab, y);
    expect(motion.atTime(regrab).stretch, closeTo(before, 1e-9));
    var last = before;
    for (var i = 1; i <= 24; i++) {
      final s = regrab + i * step;
      motion.dragUpdate(s, y);
      final now = motion.atTime(s).stretch;
      expect((now - last).abs(), lessThan(0.003));
      last = now;
    }
    expect(last, lessThan(before));
  });
}

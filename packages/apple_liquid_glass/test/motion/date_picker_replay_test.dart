import 'dart:convert';
import 'dart:math' as math;

import 'package:apple_liquid_glass/src/motions/date_picker_motion.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/motion.dart';

import '../support/fixtures.dart';

const _dir = 'test/fixtures/ios27/date_picker';
const double _frame = 1 / 60;

List<Map<String, Object?>> _rows(String file) => [
  for (final line in Fixtures.lines('$_dir/$file'))
    if (line.trim().isNotEmpty)
      (jsonDecode(line) as Map).cast<String, Object?>(),
];

double _d(Map<String, Object?> r, String k) => (r[k]! as num).toDouble();

double _rms(List<double> e) =>
    math.sqrt(e.fold<double>(0, (a, b) => a + b * b) / math.max(1, e.length));

(double, double) _fit(
  double from,
  double window,
  List<double> Function(double) errors,
) {
  var best = from;
  var bestErr = double.infinity;
  for (var lag = 0.0; lag <= window; lag += 0.001) {
    final e = _rms(errors(from + lag));
    if (e < bestErr) {
      bestErr = e;
      best = from + lag;
    }
  }
  return (best, bestErr);
}

Rect _box(List<Object?> v) {
  final n = v.cast<num>();
  return Rect.fromLTWH(
    n[0].toDouble(),
    n[1].toDouble(),
    n[2].toDouble(),
    n[3].toDouble(),
  );
}

extension<M extends Motion> on M {
  M seenAt(double t) {
    advance(t);
    return this;
  }
}

void main() {
  group('compact date picker replays the simulator', () {
    test('the overlay opens and closes about its anchor', () {
      final rows = _rows('date-open.jsonl');
      final touches = [
        for (final r in rows)
          if (r['k'] == 'touch') r,
      ];
      final openUp = _d(touches[1], 't');
      final closeUp = _d(touches[3], 't');
      // The first frame of the close reads the platter's hidden state for
      // one frame (a presentation-layer artifact); it is skipped.
      final platter = [
        for (final r in rows)
          if (r['cls'] == '_UIDatePickerOverlayPlatterView' &&
              !(_d(r, 't') > closeUp &&
                  _d(r, 't') < closeUp + 0.03 &&
                  _d(r, 'a') == 0))
            r,
      ];
      List<double> errors(DatePickerMotion m, double from, double to) => [
        for (final r in platter)
          if (_d(r, 't') >= from && _d(r, 't') < to)
            ...() {
              final t = _d(r, 't') + _frame;
              return [
                m.seenAt(t).scale - _d(r, 'sx'),
                m.seenAt(t).opacity - _d(r, 'a').clamp(0.0, 1.0),
                (m.seenAt(t).height(332) - _d(r, 'bh')) / 332,
              ];
            }(),
      ];
      final (open, openRms) = _fit(openUp, 0.25, (start) {
        final m = DatePickerMotion();
        m.open(start);
        return errors(m, openUp, closeUp);
      });
      expect(openRms, lessThan(0.006));
      final (_, closeRms) = _fit(closeUp, 0.1, (start) {
        final m = DatePickerMotion();
        m.open(open);
        m.close(start);
        return errors(m, closeUp, double.infinity);
      });
      expect(closeRms, lessThan(0.006));
      final placement = placeDatePicker(
        size: const Size(320, 332),
        label: const Rect.fromLTWH(162.67, 283, 115, 34.33),
        screen: const Size(440, 956),
        padding: const EdgeInsets.only(top: 62, bottom: 34),
      );
      final m = DatePickerMotion();
      m.open(open);
      final anchorErrors = [
        for (final r in platter)
          if (_d(r, 't') >= openUp && _d(r, 't') < closeUp)
            ...() {
              final t = _d(r, 't') + _frame;
              final s = m.seenAt(t).scale;
              final a = placement.anchor;
              final left = a.dx + s * (placement.rect.left - a.dx);
              final top = a.dy + s * (placement.rect.top - a.dy);
              return [
                left - (_d(r, 'x') - _d(r, 'w') / 2),
                top - (_d(r, 'y') - _d(r, 'h') / 2),
              ];
            }(),
      ];
      expect(_rms(anchorErrors), lessThan(1.5));
    });

    test('above its label the overlay is anchored at its bottom', () {
      final rows = _rows('date-low.jsonl');
      final first = rows.firstWhere(
        (r) => r['cls'] == '_UIDatePickerOverlayPlatterView',
      );
      final placement = placeDatePicker(
        size: const Size(320, 332),
        label: const Rect.fromLTWH(162.67, 743, 115, 34.33),
        screen: const Size(440, 956),
        padding: const EdgeInsets.only(top: 62, bottom: 34),
      );
      expect(placement.below, isFalse);
      expect(
        _d(first, 'y') + _d(first, 'h') / 2,
        closeTo(placement.anchor.dy, 0.5),
      );
    });

    test('placement matches UIKit for every captured label', () {
      final data = (jsonDecode(
        Fixtures.read('$_dir/placements.json'),
      ) as Map).cast<String, Object?>();
      for (final c in (data['cases']! as List).cast<Map<String, Object?>>()) {
        final overlay = _box(c['overlay']! as List);
        final hidden = _box(c['hidden']! as List);
        final placement = placeDatePicker(
          size: overlay.size,
          label: _box(c['label']! as List),
          screen: const Size(440, 956),
          padding: const EdgeInsets.only(top: 62, bottom: 34),
        );
        expect(
          placement.rect.left,
          closeTo(overlay.left, 0.5),
          reason: '${c['name']}',
        );
        expect(
          placement.rect.top,
          closeTo(overlay.top, 0.5),
          reason: '${c['name']}',
        );
        const s = DatePickerTuning.hiddenScale;
        final a = placement.anchor;
        expect(
          a.dx + s * (placement.rect.left - a.dx),
          closeTo(hidden.left, 0.5),
          reason: '${c['name']} hidden',
        );
      }
    });

    test('a month turns on a sine ease over 0.3 s', () {
      final rows = _rows('date-page.jsonl');
      final touches = [
        for (final r in rows)
          if (r['k'] == 'touch') r,
      ];
      final up = _d(touches.last, 't');
      final first = rows.firstWhere(
        (r) => r['text'] == '15' && _d(r, 't') > up,
      );
      final day = [
        for (final r in rows)
          if (r['text'] == '15' && r['id'] == first['id'] && _d(r, 't') > up) r,
      ];
      final (_, rms) = _fit(up - 0.03, 0.08, (start) {
        final m = DatePickerCalendarMotion();
        m.turnPage(start, 1);
        return [
          for (final r in day)
            (222.33 - 320 * m.seenAt(_d(r, 't') + _frame).page) - _d(r, 'x'),
        ];
      });
      expect(rms, lessThan(2.5));
    });

    test('the label dims under the finger', () {
      final rows = _rows('date-open.jsonl');
      final touches = [
        for (final r in rows)
          if (r['k'] == 'touch') r,
      ];
      final down = _d(touches[0], 't');
      final up = _d(touches[1], 't');
      final label = [
        for (final r in rows)
          if (r['cls'] == '_UIDatePickerLinkedLabel' &&
              _d(r, 't') < down + 0.7 &&
              _d(r, 't') >= down)
            r,
      ];
      final (_, rms) = _fit(down - 0.02, 0.04, (at) {
        final m = DatePickerLabelMotion();
        m.press(at);
        m.release(at + up - down);
        return [
          for (final r in label)
            m.seenAt(_d(r, 't') + _frame).highlight - _d(r, 'a'),
        ];
      });
      expect(rms, lessThan(0.03));
    });
  });

  group('compact date picker replays an iPhone 16 Pro', () {
    const device = 'test/fixtures/ios27-device/date_picker';
    List<Map<String, Object?>> load(String file) => [
      for (final line in Fixtures.lines('$device/$file'))
        if (line.trim().isNotEmpty)
          (jsonDecode(line) as Map).cast<String, Object?>(),
    ];
    List<double> ups(List<Map<String, Object?>> rows) => [
      for (final r in rows)
        if (r['k'] == 'touch' && r['phase'] == 3) _d(r, 't'),
    ];

    test(
      'the overlay opens 0.14 s after the lift and closes 0.055 s after',
      () {
        final rows = load('vid-date.jsonl');
        final platter = [
          for (final r in rows)
            if (r['cls'] == '_UIDatePickerOverlayPlatterView') r,
        ];
        final lifts = ups(rows);
        // The press on the label lifts first and opens the overlay; the tap
        // outside at y 754 closes it.
        final openUp = lifts.first;
        final closeUp = [
          for (final r in rows)
            if (r['k'] == 'touch' && r['phase'] == 3 && _d(r, 'y') > 700)
              _d(r, 't'),
        ].first;
        final m = DatePickerMotion();
        m.open(openUp);
        final open = <double>[];
        final close = <double>[];
        for (final r in platter) {
          final t = _d(r, 't');
          if (t >= closeUp && m.isOpen) m.close(closeUp);
          // Before the animation's first frame the view reads its final
          // layout, and the close's first frame its hidden one (one row
          // each); the springs are compared from their start on.
          if (t < openUp + DatePickerTuning.openDelay ||
              t > closeUp + 0.8 ||
              (t > closeUp && _d(r, 'a') == 0)) {
            continue;
          }
          final e = m.seenAt(t).scale - _d(r, 'sx');
          if (t < closeUp) {
            open.add(e);
          } else {
            close.add(e);
          }
        }
        expect(open.length, greaterThan(40));
        expect(close.length, greaterThan(30));
        // Without the delays the same springs miss by 0.27 (open) and 0.16
        // (close); 0.03 s either way already costs 0.07.
        expect(_rms(open), lessThan(0.015));
        expect(_rms(close), lessThan(0.015));
      },
    );

    for (final gap in ['050', '150', '300']) {
      test('a tap outside while it opens turns it around (gap $gap)', () {
        final rows = load('tm-openclose-$gap.jsonl');
        final lifts = ups(rows);
        // UIKit's open latency varies by a frame from tap to tap (0.131 -
        // 0.146 s here); it is fitted, the close is not.
        List<double> errors(double openAt) {
          final m = DatePickerMotion();
          m.open(lifts.first, delay: openAt - lifts.first);
          final out = <double>[];
          for (final r in rows) {
            if (r['k'] != 'V') continue;
            final t = _d(r, 't');
            if (t >= lifts.last && m.isOpen) m.close(lifts.last);
            // One row per capture reads the platter's hidden state
            // mid-flight (a presentation-layer artifact).
            if (t < lifts.first + 0.1 ||
                (_d(r, 'sx') == 0.2 && t > lifts.first + 0.16)) {
              continue;
            }
            out.add(m.seenAt(t).scale - _d(r, 'sx'));
            out.add(m.seenAt(t).opacity - _d(r, 'a').clamp(0.0, 1.0));
          }
          return out;
        }

        final (openAt, rms) = _fit(lifts.first + 0.1, 0.07, errors);
        expect(errors(openAt).length, greaterThan(60));
        expect(openAt - lifts.first, closeTo(0.14, 0.012));
        expect(rms, lessThan(0.015));
      });

      test('a tap on the label while it closes opens a new one (gap $gap)', () {
        final rows = load('tm-closeopen-$gap.jsonl');
        final lifts = ups(rows);
        final closeUp = lifts[1];
        final reopenUp = lifts[lifts.length - 2];
        final ids = <int>[];
        for (final r in rows) {
          if (r['k'] == 'V' && !ids.contains(r['id'])) ids.add(r['id']! as int);
        }
        final old = DatePickerMotion();
        old.open(lifts.first);
        old.close(closeUp);
        final fresh = DatePickerMotion();
        fresh.open(reopenUp, delay: DatePickerTuning.reopenDelay);
        final closing = <double>[];
        final opening = <double>[];
        for (final r in rows) {
          if (r['k'] != 'V') continue;
          final t = _d(r, 't');
          if (t < closeUp + DatePickerTuning.closeDelay || t > reopenUp + 1) {
            continue;
          }
          if (r['id'] == ids.first) {
            if (t > closeUp + 0.04 && _d(r, 'sx') == 0.2) continue;
            closing.add(old.seenAt(t).scale - _d(r, 'sx'));
          } else {
            opening.add(fresh.seenAt(t).scale - _d(r, 'sx'));
            opening.add(fresh.seenAt(t).opacity - _d(r, 'a').clamp(0.0, 1.0));
          }
        }
        expect(closing.length, greaterThan(20));
        expect(opening.length, greaterThan(60));
        expect(_rms(closing), lessThan(0.02));
        expect(_rms(opening), lessThan(0.02));
      });
    }

    test('the other label turns the overlay on a 0.25 s spring', () {
      final rows = load('vid-both.jsonl');
      final lifts = ups(rows);
      final up = lifts[1];
      const from = Size(320, 332);
      const to = DatePickerMotion.timeSize;
      expect(DatePickerTuning.switchSpring.dampingRatio, 1);
      double p(double t) {
        final dt = t - up - DatePickerTuning.switchDelay;
        if (dt <= 0) return 0;
        final w = 2 * math.pi / DatePickerTuning.switchSpring.response;
        return 1 - math.exp(-w * dt) * (1 + w * dt);
      }

      final size = <double>[];
      final fade = <double>[];
      for (final r in rows) {
        final t = _d(r, 't');
        if (t < up || t > up + 0.6) continue;
        if (r['cls'] == '_UIDatePickerOverlayPlatterView') {
          size.add(_d(r, 'w') - (from.width + (to.width - from.width) * p(t)));
          size.add(
            _d(r, 'h') - (from.height + (to.height - from.height) * p(t)),
          );
        } else if (r['cls'] == '_UIDatePickerCalendarView') {
          fade.add(_d(r, 'ea') - (1 - p(t)));
        }
      }
      expect(size.length, greaterThan(40));
      expect(_rms(size), lessThan(0.6));
      expect(_rms(fade), lessThan(0.02));
    });
  });

  group('month and year wheels replay an iPhone 16 Pro', () {
    const device = 'test/fixtures/ios27-device/date_picker';
    List<Map<String, Object?>> load(String file) => [
      for (final line in Fixtures.lines('$device/$file'))
        if (line.trim().isNotEmpty)
          (jsonDecode(line) as Map).cast<String, Object?>(),
    ];

    // The title's chevron image is 10.33 x 14; its frame is the bounding
    // box of the turned image, so the turn is read back from the box.
    double turn(Map<String, Object?> r) {
      const a = 10.33;
      const b = 14.0;
      final w = _d(r, 'w');
      final h = _d(r, 'h');
      const det = a * a - b * b;
      final c = (a * w - b * h) / det;
      final s = (a * h - b * w) / det;
      return math.atan2(s, c) / (math.pi / 2);
    }

    for (final name in [
      'my-light',
      'my-dark',
      'myrev-030',
      'myrev-120',
      'my31',
      'mypage',
    ]) {
      test('the grid and the wheels cross-fade as UIKit does ($name)', () {
        final rows = load('$name.jsonl');
        final titleTaps = [
          for (final r in rows)
            if (r['k'] == 'touch' &&
                r['phase'] == 3 &&
                _d(r, 'x') < 200 &&
                (_d(r, 'y') - 341).abs() < 12)
              _d(r, 't'),
        ];
        final closeTap = [
          for (final r in rows)
            if (r['k'] == 'touch' &&
                r['phase'] == 3 &&
                _d(r, 'y') > 700 &&
                _d(r, 't') > titleTaps.first)
              _d(r, 't'),
        ].first;
        final m = DatePickerCalendarMotion();
        var show = true;
        var next = 0;
        final fade = <double>[];
        final chevron = <double>[];
        for (final r in rows) {
          if (r['k'] != 'V') continue;
          final t = _d(r, 't');
          while (next < titleTaps.length && titleTaps[next] <= t) {
            m.showYearPicker(titleTaps[next], show: show);
            show = !show;
            next++;
          }
          if (t <= titleTaps.first || t >= closeTap) continue;
          if (r['cls'] == '_UICalendarWeekdayView') {
            fade.add(m.seenAt(t).yearPicker - (1 - _d(r, 'a')));
          } else if (r['cls'] == 'chevron') {
            chevron.add(m.seenAt(t).yearPickerTurn - turn(r));
          }
        }
        expect(fade.length, greaterThan(50));
        expect(chevron.length, greaterThan(50));
        // UIKit's start varies by a frame or so from tap to tap (0.061 -
        // 0.077 s for the wheels, 0.018 - 0.022 s back); the mean delays
        // keep every capture within these.
        expect(_rms(fade), lessThan(0.035));
        expect(_rms(chevron), lessThan(0.035));
        expect(fade.map((e) => e.abs()).reduce(math.max), lessThan(0.09));
      });
    }

    test('the title turns accent at the tap, wheels turn the value', () {
      final rows = load('mypage.jsonl');
      final titles = [
        for (final r in rows)
          if (r['cls'] == 'title') r,
      ];
      // A page turn to November leaves the selected day alone; the wheels
      // open on the shown month; December on the wheel picks December 3.
      expect(titles.first['text'], 'November 2026');
      final changes = [
        for (final r in rows)
          if (r['k'] == 'evt')
            DateTime.fromMillisecondsSinceEpoch(
              (_d(r, 'v') * 1000).round(),
              isUtc: true,
            ),
      ];
      expect(changes, [DateTime.utc(2026, 12, 3, 7, 41)]);
      final clamp = [
        for (final r in load('my31.jsonl'))
          if (r['k'] == 'evt')
            DateTime.fromMillisecondsSinceEpoch(
              (_d(r, 'v') * 1000).round(),
              isUtc: true,
            ),
      ];
      expect(clamp, [
        DateTime.utc(2026, 11, 30, 8, 41),
        DateTime.utc(2026, 10, 30, 8, 41),
      ]);
    });
  });

  group('DatePickerMotion', () {
    test('opens from a fifth of its size and its 50 point box', () {
      final m = DatePickerMotion();
      m.open(0);
      expect(m.seenAt(0).scale, DatePickerTuning.hiddenScale);
      expect(m.seenAt(0).height(332), 50);
      m.advance(2);
      expect(m.seenAt(2).scale, closeTo(1, 1e-3));
      expect(m.seenAt(2).height(332), closeTo(332, 0.5));
      m.close(2);
      m.advance(4);
      expect(m.isClosed, isTrue);
    });

    test('the year picker eases in 0.25 s after its delay, both ways', () {
      final m = DatePickerCalendarMotion();
      m.showYearPicker(1, show: true);
      expect(m.showsYearPicker, isTrue);
      const show = DatePickerTuning.yearPickerShowDelay;
      expect(m.seenAt(1 + show).yearPicker, 0);
      expect(m.seenAt(1 + show + 0.125).yearPicker, closeTo(0.5, 1e-9));
      expect(m.seenAt(1 + show + 0.25).yearPicker, 1);
      m.showYearPicker(2, show: false);
      const hide = DatePickerTuning.yearPickerHideDelay;
      expect(m.seenAt(2 + hide).yearPicker, 1);
      expect(m.seenAt(2 + hide + 0.125).yearPicker, closeTo(0.5, 1e-9));
    });

    test('a reversal restarts from where the change stands', () {
      final m = DatePickerCalendarMotion();
      m.showYearPicker(0, show: true);
      m.showYearPicker(0.15, show: false);
      const hide = DatePickerTuning.yearPickerHideDelay;
      const at = 0.15 + hide;
      final before = m.seenAt(at - 1e-6).yearPicker;
      expect(before, greaterThan(0));
      expect(m.seenAt(at).yearPicker, closeTo(before, 1e-4));
      expect(m.seenAt(at + 0.25).yearPicker, 0);
      // A reversal scheduled to start before the change has started
      // leaves it where it was.
      final n = DatePickerCalendarMotion();
      n.showYearPicker(0, show: true);
      n.showYearPicker(0.01, show: false);
      for (var t = 0.0; t < 0.6; t += 0.01) {
        expect(n.seenAt(t).yearPicker, 0);
      }
    });
  });

  test('motion reads stay at the motion time', () {
    final motion = DatePickerMotion();
    motion.open(0);
    expect(motion.progress, 0);
    expect(motion.now, 0);
    expect(motion.isSettled, isFalse);
    expect(motion.isClosed, isFalse);
    expect(motion.seenAt(0.05).progress, 0);
    motion.close(0.06);
    expect(motion.progress, 0);
    motion.advance(1);
    expect(motion.isClosed, isTrue);
  });

  test('another page turn waits for the running slide, then runs', () {
    final motion = DatePickerCalendarMotion();
    final turns = <int>[];
    motion.onTurn = (direction) {
      turns.add(direction);
      return true;
    };
    motion.turnPage(0, 1);
    final before = motion.seenAt(0.15).page;
    motion.turnPage(0.15, -1);
    expect(motion.seenAt(0.15).page, before);
    expect(turns, [1]);
    expect(motion.seenAt(0.29).page, lessThan(1));
    expect(motion.seenAt(0.45).page, closeTo(0.5, 0.01));
    expect(turns, [1, -1]);
    expect(motion.pageDirection, -1);
    expect(motion.seenAt(0.6).page, 1);
    expect(motion.isSettled, isTrue);
  });

  test('reduced motion drops the label dim and fades the overlay', () {
    const start = DatePickerTuning.openDelay;
    const fade = DatePickerTuning.reducedMotionDuration;
    final regular = DatePickerMotion();
    regular.open(0);
    final pressed = DatePickerLabelMotion();
    pressed.press(0);
    expect(pressed.seenAt(0.2).highlight, lessThan(1));
    expect(regular.seenAt(start + fade / 2).scale, lessThan(1));
    MotionTraits.debugPlatformOverride = const MotionTraits(
      reduceMotion: true,
    );
    addTearDown(() => MotionTraits.debugPlatformOverride = null);
    final reduced = DatePickerMotion();
    reduced.open(0);
    final calm = DatePickerLabelMotion();
    calm.press(0);
    expect(calm.seenAt(0.2).highlight, 1);
    reduced.advance(start + fade / 2);
    expect(reduced.seenAt(start + fade / 2).opacity, closeTo(0.5, 1e-9));
    expect(reduced.seenAt(start + fade / 2).scale, 1);
    expect(reduced.seenAt(start + fade / 2).height(300), 300);
    reduced.advance(start + fade);
    expect(reduced.seenAt(start + fade).opacity, 1);
    reduced.close(1);
    reduced.advance(1 + DatePickerTuning.closeDelay + fade);
    expect(reduced.isClosed, isTrue);
  });
}

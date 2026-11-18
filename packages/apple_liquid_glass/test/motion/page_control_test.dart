import 'dart:convert';
import 'dart:math' as math;

import 'package:apple_liquid_glass/src/motions/page_control_motion.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

const _pages = 'test/fixtures/ios27/page_control';

List<Map<String, Object?>> _rows(String path) => [
  for (final line in Fixtures.lines(path))
    if (line.trim().isNotEmpty)
      (jsonDecode(line) as Map).cast<String, Object?>(),
];

double _d(Map<String, Object?> r, String k) => (r[k]! as num).toDouble();

void main() {
  group('PageControlMotion', () {
    test('replays the simulator: a timer page advance', () {
      final rows = _rows('$_pages/pc-timer.jsonl');
      final indicators = <int, List<Map<String, Object?>>>{};
      final fill = <Map<String, Object?>>[];
      for (final r in rows) {
        if (r['k'] != 'V') continue;
        if (r['cls'] == '_UIPageIndicatorView') {
          (indicators[r['id']! as int] ??= []).add(r);
        } else {
          fill.add(r);
        }
      }
      final ids = indicators.keys.toList()..sort();
      final first = indicators[ids[0]]!;
      final leave = first.firstWhere((r) => _d(r, 'w') < 27.2);
      double rms(List<double> e) =>
          math.sqrt(e.fold<double>(0, (a, b) => a + b * b) / e.length);
      ({double widths, double fade}) score(double start) {
        PageControlMotion started() {
          final m = PageControlMotion(
            count: 5,
            page: 0,
            showsProgress: true,
          );
          m.setPage(start, 1);
          return m;
        }

        final e = <double>[];
        for (final id in ids.take(2)) {
          final i = ids.indexOf(id);
          final m = started();
          for (final r in indicators[id]!) {
            final t = _d(r, 't') + 1 / 60;
            if (t < start - 0.1) continue;
            m.advance(t);
            e.add(m.width(i) - _d(r, 'w'));
          }
        }
        final f = started();
        final fade = <double>[];
        for (final r in fill) {
          final t = _d(r, 't') + 1 / 60;
          if (t < start - 0.1) continue;
          f.advance(t);
          fade.add(f.fillOpacity(0) - _d(r, 'a'));
        }
        return (widths: rms(e), fade: rms(fade));
      }

      ({double widths, double fade})? best;
      for (var lag = -0.08; lag <= 0.02; lag += 0.002) {
        final s = score(_d(leave, 't') + lag);
        if (best == null || s.widths < best.widths) best = s;
      }
      expect(best!.widths, lessThan(0.25));
      // The fill of the page it leaves fades out at the same moment.
      expect(best.fade, lessThan(0.02));
    });
  });

  // The platter timing is the device's (120 Hz rows resolve its 25 ms
  // fades); on the 60 Hz simulator it lands within a frame, which is up to
  // 0.3 of opacity on the two or three samples of each fade.
  for (final (source, dir, shift, holdTolerance, scrubTolerance) in [
    ('the simulator', _pages, 1 / 60, 0.12, 0.18),
    (
      'an iPhone 16 Pro',
      'test/fixtures/ios27-device/page_control',
      1 / 120,
      0.03,
      0.03,
    ),
  ]) {
    group('PageControlMotion touches, replayed against $source', () {
      /// The first dot's center in the probe's window, and the control's
      /// width (5 pages).
      const firstDot = 166.0;
      const width = 5 * 9.67 + 4 * 8 + 28;

      ({List<int> model, List<int> recorded, double platter}) replay(
        String name,
      ) {
        final rows = _rows('$dir/$name.jsonl');
        final model = <int>[];
        final motion = PageControlMotion(
          count: 5,
          page: 0,
          onEvent: (event) {
            if (event is PageControlPicked) model.add(event.page);
          },
        );

        final recorded = [
          for (final r in rows)
            if (r['k'] == 'evt' && r['e'] == 'valueChanged') r['v']! as int,
        ];
        final events = [
          for (final r in rows)
            if (r['k'] == 'touch' ||
                (r['k'] == 'V' && r['cls'] == 'UIVisualEffectView'))
              r,
        ];
        final errors = <double>[];
        for (final r in events) {
          final t = _d(r, 't');
          if (r['k'] == 'touch') {
            final x = _d(r, 'x') - firstDot + 9.67 / 2;
            switch (r['phase']) {
              case 0:
                motion.pointerDown(t, x);
              case 3:
                motion.pointerUp(t, x, width: width);
              default:
                motion.pointerMove(t, x);
            }
          } else if (t > _d(events.first, 't') + 1) {
            final shown = t + shift;
            motion.advance(shown);
            errors.add(motion.platter - _d(r, 'a'));
          }
        }
        return (
          model: model,
          recorded: recorded,
          platter: errors.isEmpty
              ? 0
              : math.sqrt(
                  errors.fold<double>(0, (a, b) => a + b * b) / errors.length,
                ),
        );
      }

      test('taps step to the side they land on', () {
        final r = replay('pc-tap-right');
        expect(r.model, r.recorded);
      });

      test(
        'a held touch shows the platter after 0.2 s and hides it on lift',
        () {
          final r = replay('pc-hold');
          expect(r.model, isEmpty);
          expect(r.platter, lessThan(holdTolerance));
        },
      );

      test('a scrub follows the nearest dot both ways', () {
        final r = replay('pc-scrub');
        expect(r.model, r.recorded);
        expect(r.platter, lessThan(scrubTolerance));
      });
    });
  }
}

import 'dart:convert';
import 'dart:math' as math;

import 'package:apple_liquid_glass/src/motions/alert_motion.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/motion.dart';

import '../support/fixtures.dart';

List<Map<String, Object?>> _rows(String dir, String file) => [
  for (final line in Fixtures.lines('$dir/$file'))
    if (line.trim().isNotEmpty)
      (jsonDecode(line) as Map).cast<String, Object?>(),
];

double _d(Map<String, Object?> r, String k) => (r[k]! as num).toDouble();

double _event(List<Map<String, Object?>> rows, String name) => _d(
  rows.firstWhere((r) => r['k'] == 'evt' && (r['e'] == name || r['a'] == name)),
  't',
);

double _rms(List<double> e) =>
    math.sqrt(e.fold<double>(0, (a, b) => a + b * b) / math.max(1, e.length));

/// Aligns the start of an animation to the recording: UIKit starts it a
/// frame or more after its call. Returns the best start within [maxLag]
/// of [call] and the rms error there.
(double, double) _align(
  double call,
  double maxLag,
  List<double> Function(double start) errors,
) {
  var best = call;
  var bestErr = double.infinity;
  for (var lag = 0.0; lag <= maxLag; lag += 0.001) {
    final e = _rms(errors(call + lag));
    if (e < bestErr) {
      bestErr = e;
      best = call + lag;
    }
  }
  return (best, bestErr);
}

AlertMotion _at(AlertMotion motion, double t) {
  motion.advance(t);
  return motion;
}

void main() {
  for (final (source, dir, frame) in [
    ('the simulator', 'test/fixtures/ios27/alert', 1 / 60),
    ('an iPhone 16 Pro', 'test/fixtures/ios27-device/alert', 1 / 120),
  ]) {
    group('alert motion replays $source', () {
      final rows = _rows(dir, 'alert-present-dismiss.jsonl');
      final present = _event(rows, 'present');
      final dismiss = _event(rows, 'dismiss');
      final alert = [
        for (final r in rows)
          if (r['cls'] == '_UIAlertControllerPhoneTVMacView' &&
              _d(r, 't') > present)
            r,
      ];
      final dim = [
        for (final r in rows)
          if (r['cls'] == 'UIView' && _d(r, 't') > present) r,
      ];

      test('present: the scale and the dimming on one spring', () {
        List<double> scaleErrors(double start) {
          final motion = AlertMotion();
          motion.open(start);
          return [
            for (final r in alert)
              if (_d(r, 't') < dismiss)
                _at(motion, _d(r, 't') + frame).scale -
                    _d(r, 'w') / _d(r, 'bw'),
          ];
        }

        final (start, scaleRms) = _align(present, 0.15, scaleErrors);
        final motion = AlertMotion();
        motion.open(start);
        final dimErr = [
          for (final r in dim)
            if (_d(r, 't') < dismiss)
              _at(motion, _d(r, 't') + frame).dimming - _d(r, 'a'),
        ];
        expect(scaleRms, lessThan(0.0015));
        expect(_rms(dimErr), lessThan(0.012));
      });

      test(
        'dismiss: the dimming fades on the same spring, the scale stays',
        () {
          List<double> errors(double start) {
            final motion = AlertMotion();
            motion.open(present);
            motion.leave(start, DismissTrigger.programmatic);
            return [
              for (final r in dim)
                if (_d(r, 't') > dismiss)
                  _at(motion, _d(r, 't') + frame).dimming - _d(r, 'a'),
            ];
          }

          final (start, rms) = _align(dismiss, 0.15, errors);
          expect(rms, lessThan(0.012));
          final motion = AlertMotion();
          motion.open(present);
          motion.leave(start, DismissTrigger.programmatic);
          expect(_at(motion, start + 0.2).scale, closeTo(1, 1e-3));
        },
      );
    });
  }

  group('AlertMotion', () {
    test('presents from the measured scale, transparent', () {
      final motion = AlertMotion();
      motion.open(0);
      expect(motion.scale, AlertTuning.presentScale);
      expect(motion.opacity, 0);
      _at(motion, 1);
      expect(motion.scale, closeTo(1, 1e-3));
      expect(motion.opacity, closeTo(1, 1e-3));
    });

    test('a dismissal mid-present reverses with the velocity', () {
      final motion = AlertMotion();
      motion.open(0);
      final before = _at(motion, 0.05).opacity;
      motion.leave(0.05, DismissTrigger.programmatic);
      expect(_at(motion, 0.06).opacity, greaterThan(before));
    });

    test('under Reduce Motion it presents at its size', () {
      final motion = AlertMotion();
      MotionTraits.debugPlatformOverride = const MotionTraits(
        reduceMotion: true,
      );
      addTearDown(() => MotionTraits.debugPlatformOverride = null);
      motion.open(0);
      expect(motion.scale, 1);
    });
  });

  group('predictive back', () {
    test('the gesture runs the dismissal by its progress', () {
      final motion = AlertMotion();
      motion.open(0);
      _at(motion, 2);
      final shownScale = motion.scale;
      motion.backStarted(2);
      motion.backMoved(2, 0);
      expect(motion.opacity, 1);
      motion.backMoved(2.1, 0.4);
      expect(_at(motion, 2.1).opacity, closeTo(0.6, 1e-9));
      expect(motion.scale, lessThanOrEqualTo(shownScale));
      expect(motion.presence, isNot(PresenceStatus.leaving));
    });

    test('a commit leaves from the gesture with its velocity', () {
      final motion = AlertMotion();
      motion.open(0);
      _at(motion, 2);
      motion.backStarted(2);
      motion.backMoved(2.1, 0.4);
      motion.backEnded(2.1, commits: true, velocity: 3);
      expect(motion.leave(2.1, DismissTrigger.back), isTrue);
      final early = _at(motion, 2.12).opacity;
      expect(early, lessThan(0.6 - 3 * 0.02 * 0.5));
      expect(_at(motion, 4).presence, PresenceStatus.hidden);
    });

    test('a cancel springs back to shown', () {
      final motion = AlertMotion();
      motion.open(0);
      _at(motion, 2);
      motion.backStarted(2);
      motion.backMoved(2.1, 0.5);
      motion.backEnded(2.1, commits: false, velocity: -1);
      expect(_at(motion, 2.15).opacity, greaterThan(0.5));
      expect(_at(motion, 4).presence, PresenceStatus.shown);
      expect(motion.opacity, closeTo(1, 1e-3));
    });
  });
}

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:apple_liquid_glass/src/motions/bar_frames.dart';
import 'package:apple_liquid_glass/src/motions/bar_motion.dart';
import 'package:apple_liquid_glass/src/motions/bar_transition_spec.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

List<Map<String, Object?>> _rows(String path) => [
  for (final line in Fixtures.lines(path))
    if (line.trim().isNotEmpty)
      (jsonDecode(line) as Map).cast<String, Object?>(),
];

double _d(Map<String, Object?> r, String k) => (r[k]! as num).toDouble();

double _rms(List<double> e) =>
    math.sqrt(e.fold<double>(0, (a, v) => a + v * v) / e.length);

const _leading = 'leading';
const _trailing = 'trailing';

GlassBarCapsuleLayout _capsule(
  Object id,
  String segment,
  double cx,
  double w,
  double cy,
  List<String> items, {
  double h = 44,
}) {
  final rect = Rect.fromCenter(center: Offset(cx, cy), width: w, height: h);
  final step = w / items.length;
  return GlassBarCapsuleLayout(id, rect, [
    for (var k = 0; k < items.length; k++)
      GlassBarItemLayout(
        items[k],
        Rect.fromLTWH(rect.left + k * step, rect.top, step, rect.height),
      ),
  ], segment: segment);
}

/// The navigation bar of each page of the probe's navseg scene at rest,
/// read from the recording (iPhone 16 Pro, 402 pt): groups without an id
/// are keyed by place from the bar's edge, as the bar keys them.
List<GlassBarCapsuleLayout> _navPage(int page) {
  const cy = 84.0;
  final back = _capsule(('leading', 0), _leading, 38, 44, cy, ['back']);
  return switch (page) {
    0 => [
      _capsule(('trailing', 0), _trailing, 364, 44, cy, ['plus']),
    ],
    1 => [
      back,
      _capsule(('trailing', 0), _trailing, 364, 44, cy, ['share']),
    ],
    2 => [
      _capsule(('leading', 0), _leading, 59, 86, cy, ['cancel']),
      _capsule(
        ('trailing', 0),
        _trailing,
        334.2,
        103.7,
        cy,
        ['share2', 'heart'],
      ),
    ],
    3 => [back],
    _ => [
      back,
      _capsule(('trailing', 0), _trailing, 349.2, 73.7, cy, ['done']),
      _capsule(('trailing', 1), _trailing, 278.3, 44, cy, ['heart4']),
    ],
  };
}

/// The toolbar sets of the navseg root page (48 pt capsules, 28 from the
/// sides of the 402 pt screen).
List<GlassBarCapsuleLayout> _toolbar(String set) {
  const cy = 822.0;
  final trash = _capsule(
    ('leading', 0),
    _leading,
    52,
    48,
    cy,
    ['trash'],
    h: 48,
  );
  final compose = _capsule(
    ('trailing', 0),
    _trailing,
    350,
    48,
    cy,
    ['compose'],
    h: 48,
  );
  return switch (set) {
    'B' => [trash, compose],
    'C' => [trash],
    _ => [compose],
  };
}

/// The glass of a bar replayed against the probe's rows: every capsule
/// element frame (center x, width, height) and every group that appears
/// or leaves in place (its scale per axis and opacity).
class _Replay {
  final dx = <double>[];
  final dw = <double>[];
  final dh = <double>[];
  final scale = <double>[];
  final opacity = <double>[];
  final _apartCenters = <double>{};

  void run(
    List<Map<String, Object?>> rows,
    List<(double, List<GlassBarCapsuleLayout>)> changes,
    List<GlassBarCapsuleLayout> initial,
    String bar, {
    GlassBarTransitionSpec spec = GlassBarTransitionSpec.standard,
  }) {
    final samples = [
      for (final r in rows)
        if ((r['cls'] == 'SDFElement' || r['cls'] == 'group') &&
            r['bar'] == bar)
          r,
    ];
    final motion = GlassBarMotion(spec: spec);
    motion.setLayout(changes.first.$1 - 1, initial);
    for (var k = 0; k < changes.length; k++) {
      final (t0, layout) = changes[k];
      final t1 = k + 1 < changes.length ? changes[k + 1].$1 : t0 + 1;
      motion.setLayout(t0, layout);
      final end = math.min(t1, t0 + 0.8);
      final window = [
        for (final r in samples)
          if (_d(r, 't') > t0 && _d(r, 't') < end) r,
      ];
      final swelling = {
        for (final r in window)
          if (r['cls'] == 'group' && _d(r, 'sx') > 1.1) r['lid'],
      };
      final seen = <(Object?, double, double)>{};
      for (final r in window) {
        motion.advance(_d(r, 't'));
        if (r['cls'] == 'SDFElement') {
          _element(motion, r);
        } else if (swelling.contains(r['lid'])) {
          if (!seen.add((r['lid'], _d(r, 'sx'), _d(r, 'a')))) continue;
          final home = [...layout, ..._previous(changes, k, initial)];
          _group(motion, r, home, _d(r, 't') - t0);
        }
      }
    }
  }

  /// Compares an element row with the nearest capsule drawn in the same
  /// container: UIKit hosts groups that appear or leave in place in a
  /// second SDF layer (`host` 1; a group leaving while another appears
  /// may stay in the first). Once such a group has faded out its element
  /// stays behind invisible; rows where only such a faded group stands
  /// are skipped.
  void _element(GlassBarMotion motion, Map<String, Object?> r) {
    final apart = r['host'] == 1;
    final frames = motion.capsules;
    final same = [
      for (final f in frames)
        if (f.apart == apart) f,
    ];
    for (final f in frames) {
      if (f.apart) _apartCenters.add(f.rect.center.dx);
    }
    final x = _d(r, 'x');
    final faded =
        _apartCenters.any((c) => (c - x).abs() < 1) &&
        !frames.any((f) => (f.rect.center.dx - x).abs() < 20);
    if (faded) return;
    GlassBarCapsuleFrame? best;
    var bestD = double.infinity;
    for (final f in same.isEmpty && !apart ? frames : same) {
      final d =
          (f.rect.center.dx - _d(r, 'x')).abs() +
          (f.rect.width - _d(r, 'w')).abs();
      if (d < bestD) {
        bestD = d;
        best = f;
      }
    }
    if (best == null) {
      expect(apart, isTrue, reason: 'no capsule for $r');
      return;
    }
    dx.add(best.rect.center.dx - _d(r, 'x'));
    dw.add(best.rect.width - _d(r, 'w'));
    dh.add(best.rect.height - _d(r, 'h'));
  }

  void _group(
    GlassBarMotion motion,
    Map<String, Object?> r,
    List<GlassBarCapsuleLayout> homes,
    double since,
  ) {
    final still = (_d(r, 'sx') - 1).abs() < 0.001 && _d(r, 'a') > 0.999;
    if (still) return;
    GlassBarCapsuleFrame? best;
    var bestD = double.infinity;
    for (final f in motion.capsules) {
      if (!f.apart) continue;
      final d = (f.rect.center.dx - _d(r, 'x')).abs();
      if (d < bestD) {
        bestD = d;
        best = f;
      }
    }
    if (best == null || bestD > 20) {
      final settled =
          (_d(r, 'sx') - 1).abs() < 0.01 && _d(r, 'a') > 0.99 ||
          _d(r, 'a') < 0.01;
      expect(settled, isTrue, reason: 'no apart capsule: $r at $since');
      return;
    }
    final center = best.rect.center.dx;
    final home = homes.firstWhere((c) => (c.rect.center.dx - center).abs() < 1);
    scale.add(best.rect.width / home.rect.width - _d(r, 'sx'));
    scale.add(best.rect.height / home.rect.height - _d(r, 'sy'));
    opacity.add(best.opacity - _d(r, 'a').clamp(0.0, 1.0));
  }

  static List<GlassBarCapsuleLayout> _previous(
    List<(double, List<GlassBarCapsuleLayout>)> changes,
    int k,
    List<GlassBarCapsuleLayout> initial,
  ) => k == 0 ? initial : changes[k - 1].$2;
}

/// The smallest gap between a capsule of one segment and a capsule of the
/// other that the glass container would fuse (neither drawn apart).
double _crossGap(List<GlassBarCapsuleFrame> capsules) {
  var gap = double.infinity;
  for (final a in capsules) {
    for (final b in capsules) {
      if (a.segment != _leading || b.segment != _trailing) continue;
      if (a.apart != b.apart) continue;
      final dxGap = math.max<double>(
        0,
        math.max(a.rect.left - b.rect.right, b.rect.left - a.rect.right),
      );
      gap = math.min(gap, dxGap);
    }
  }
  return gap;
}

void main() {
  group('navigation bar push / pop replay (iPhone 16 Pro, iOS 27.0.1)', () {
    final rows = _rows('test/fixtures/ios27-device/bars/navseg-push-pop.jsonl');
    final changes = [
      for (final r in rows)
        if (r['k'] == 'evt' && (r['e'] == 'push' || r['e'] == 'pop'))
          (_d(r, 't'), _navPage(r['to']! as int)),
    ];

    test('capsules morph within their side, groups come and go in place', () {
      final replay = _Replay();
      replay.run(
        rows,
        changes,
        _navPage(0),
        'nav',
        spec: GlassBarTransitionSpec.navigation,
      );
      expect(replay.dx.length, greaterThan(1000));
      expect(replay.scale.length, greaterThan(300));
      expect(_rms(replay.dx), lessThan(0.4), reason: 'center x rms');
      expect(_rms(replay.dw), lessThan(1.0), reason: 'width rms');
      expect(_rms(replay.dh), lessThan(0.7), reason: 'height rms');
      expect(_rms(replay.scale), lessThan(0.01), reason: 'group scale rms');
      expect(_rms(replay.opacity), lessThan(0.03), reason: 'opacity rms');
    });

    test('the leading group never fuses with the trailing one', () {
      final motion = GlassBarMotion(spec: GlassBarTransitionSpec.navigation);
      motion.setLayout(0, _navPage(0));
      var t = 1.0;
      for (final page in [1, 2, 3, 4, 3, 2, 1, 0, 1, 0, 4, 0]) {
        motion.setLayout(t, _navPage(page));
        for (var f = 0; f < 120; f++) {
          motion.advance(t + f / 120);
          expect(
            _crossGap(motion.capsules),
            greaterThanOrEqualTo(12),
            reason: 'page $page, frame $f',
          );
          for (final c in motion.capsules) {
            final left = c.rect.center.dx < 201;
            expect(left, c.segment == _leading, reason: '${c.id} at $f');
          }
        }
        t += 1;
      }
    });
  });

  group('toolbar side changes replay (iPhone 16 Pro, iOS 27.0.1)', () {
    test('a side that fills or empties does so in place', () {
      final rows = _rows(
        'test/fixtures/ios27-device/bars/navseg-toolbar.jsonl',
      );
      final changes = [
        for (final r in rows)
          if (r['k'] == 'evt' && r['e'] == 'setToolbarItems')
            (_d(r, 't'), _toolbar(r['set']! as String)),
      ];
      final replay = _Replay();
      replay.run(rows, changes, _toolbar('A'), 'tool');
      expect(replay.scale.length, greaterThan(150));
      expect(_rms(replay.dx), lessThan(0.1), reason: 'center x rms');
      expect(_rms(replay.dw), lessThan(0.2), reason: 'width rms');
      expect(_rms(replay.dh), lessThan(0.2), reason: 'height rms');
      expect(
        _rms(replay.scale),
        lessThan(0.025),
        reason:
            'group scale rms; the device starts these 0.020 - 0.044 s '
            'after the call, one delay cannot follow the spread',
      );
      expect(_rms(replay.opacity), lessThan(0.11), reason: 'opacity rms');
    });
  });

  group('segments', () {
    test('a group on an empty side appears in place, swollen and clear', () {
      final motion = GlassBarMotion();
      motion.setLayout(0, _navPage(0));
      motion.setLayout(1, _navPage(1));
      motion.advance(1.001);
      final back = motion.capsules.firstWhere((c) => c.segment == _leading);
      expect(back.apart, isTrue);
      expect(back.rect.center.dx, moreOrLessEquals(38, epsilon: 1e-6));
      expect(back.rect.width, moreOrLessEquals(44 * 1.2, epsilon: 1e-6));
      expect(back.opacity, 0);
      final item = motion.itemFrame('back')!;
      expect(item.presence, 0);
      expect(item.blur, moreOrLessEquals(10, epsilon: 1e-6));
      motion.advance(3);
      final settled = motion.capsules.firstWhere((c) => c.segment == _leading);
      expect(settled.apart, isFalse);
      expect(settled.rect.width, moreOrLessEquals(44, epsilon: 1e-6));
      expect(motion.isSettled, isTrue);
    });

    test('a group whose side empties swells and fades where it stands', () {
      final motion = GlassBarMotion();
      motion.setLayout(0, _navPage(2));
      motion.setLayout(1, _navPage(3));
      motion.advance(1.4);
      final leaving = motion.capsules.firstWhere((c) => c.segment == _trailing);
      expect(leaving.leaving, isTrue);
      expect(leaving.apart, isTrue);
      expect(leaving.rect.center.dx, moreOrLessEquals(334.2, epsilon: 1e-6));
      expect(leaving.rect.width, greaterThan(103.7));
      motion.advance(3);
      expect(motion.capsules.where((c) => c.segment == _trailing), isEmpty);
      expect(motion.itemFrame('heart'), isNull);
      expect(motion.isSettled, isTrue);
    });

    test('an id met on the other side is a new capsule', () {
      final motion = GlassBarMotion();
      motion.setLayout(0, [
        _capsule('g', _trailing, 364, 44, 84, ['a']),
      ]);
      motion.setLayout(1, [
        _capsule('g', _leading, 38, 44, 84, ['b']),
      ]);
      motion.advance(1.2);
      final frames = motion.capsules;
      expect(frames, hasLength(2));
      for (final c in frames) {
        final expected = c.segment == _leading ? 38.0 : 364.0;
        expect(c.rect.center.dx, moreOrLessEquals(expected, epsilon: 1e-6));
      }
    });

    test('a group that comes back while it leaves turns around', () {
      final motion = GlassBarMotion();
      motion.setLayout(0, _navPage(1));
      motion.setLayout(1, _navPage(0));
      motion.advance(1.15);
      final half = motion.capsules
          .firstWhere((c) => c.segment == _leading)
          .opacity;
      expect(half, inExclusiveRange(0, 1));
      motion.setLayout(1.15, _navPage(1));
      final revived = motion.capsules.where((c) => c.segment == _leading);
      expect(revived, hasLength(1));
      expect(revived.single.opacity, half);
      motion.advance(4);
      final back = motion.capsules.firstWhere((c) => c.segment == _leading);
      expect(back.apart, isFalse);
      expect(back.leaving, isFalse);
      expect(motion.isSettled, isTrue);
    });
  });
}

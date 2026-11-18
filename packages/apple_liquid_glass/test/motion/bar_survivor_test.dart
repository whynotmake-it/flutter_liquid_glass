import 'dart:convert';
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
  bool anonymous = true,
}) {
  final rect = Rect.fromCenter(center: Offset(cx, cy), width: w, height: h);
  final step = w / items.length;
  return GlassBarCapsuleLayout(
    id,
    rect,
    [
      for (var k = 0; k < items.length; k++)
        GlassBarItemLayout(
          items[k],
          Rect.fromLTWH(rect.left + k * step, rect.top, step, rect.height),
        ),
    ],
    segment: segment,
    anonymous: anonymous,
  );
}

/// The navigation bar of each page of the probe's navseg scene, set b, at
/// rest (iPhone 16 Pro, 402 pt): [1x]; back, [plus more] [1x]; back,
/// [Show Preferences]; back, [heart] [Show Preferences]. UIKit's groups
/// carry no identity, so none of them has an id.
List<GlassBarCapsuleLayout> _navB(int page) {
  const cy = 84.0;
  final back = _capsule(('leading', 0), _leading, 38, 44, cy, ['back']);
  return switch (page) {
    0 => [
      _capsule(('trailing', 0), _trailing, 355, 62, cy, ['x0']),
    ],
    1 => [
      back,
      _capsule(('trailing', 1), _trailing, 262.33, 99.33, cy, ['plus', 'more']),
      _capsule(('trailing', 0), _trailing, 355, 62, cy, ['x1']),
    ],
    2 => [
      back,
      _capsule(('trailing', 0), _trailing, 299.17, 173.67, cy, ['prefs2']),
    ],
    _ => [
      back,
      _capsule(('trailing', 1), _trailing, 178.33, 44, cy, ['heart3']),
      _capsule(('trailing', 0), _trailing, 299.17, 173.67, cy, ['prefs3']),
    ],
  };
}

/// The toolbar sets of the navseg scene's root page, set b (48 pt
/// capsules): D `[compose]`, E `[reply share folder] [compose]`, F
/// `[Show Preferences]`, G `[heart] [Show Preferences]`, H
/// `[heart] [compose]`, I `[reply share folder] [Show Preferences]`, J
/// `[reply share folder] [heart]`.
List<GlassBarCapsuleLayout> _toolbarB(String set) {
  GlassBarCapsuleLayout group(int place, double cx, double w, List<String> i) =>
      _capsule(('trailing', place), _trailing, cx, w, 822, i, h: 48);
  final three = ['reply', 'share', 'folder'];
  return switch (set) {
    'E' => [
      group(1, 230.17, 167.67, three),
      group(0, 350, 48, ['compose']),
    ],
    'F' => [
      group(0, 287.17, 173.67, ['prefs']),
    ],
    'G' => [
      group(1, 164.34, 48, ['heart']),
      group(0, 287.17, 173.67, ['prefs']),
    ],
    'H' => [
      group(1, 290, 48, ['heart']),
      group(0, 350, 48, ['compose']),
    ],
    'I' => [
      group(1, 108.17, 167.67, three),
      group(0, 290.84, 173.67, ['prefs']),
    ],
    'J' => [
      group(1, 230.17, 167.67, three),
      group(0, 350, 48, ['heart']),
    ],
    _ => [
      group(0, 350, 48, ['compose']),
    ],
  };
}

/// The list and detail bars of the probe's nav scene (push-pop.jsonl).
List<GlassBarCapsuleLayout> _listDetail(String page) {
  const cy = 84.0;
  return switch (page) {
    'list' => [
      _capsule(('leading', 0), _leading, 47.17, 62.33, cy, ['edit']),
      _capsule(('trailing', 0), _trailing, 336.33, 99.33, cy, ['add', 'more']),
    ],
    _ => [
      _capsule(('leading', 0), _leading, 63, 94, cy, ['back']),
      _capsule(('trailing', 1), _trailing, 248.5, 103.67, cy, ['a', 'b']),
      _capsule(('trailing', 0), _trailing, 349.17, 73.67, cy, ['done']),
    ],
  };
}

/// The toolbar sets of the nav scene (toolbar-swap.jsonl, 402 pt).
List<GlassBarCapsuleLayout> _toolbarSwap(String set) {
  GlassBarCapsuleLayout group(Object id, double cx, double w, String item) =>
      _capsule(
        id,
        id == 'R' ? _trailing : _leading,
        cx,
        w,
        822,
        [item],
        h: 48,
        anonymous: false,
      );
  return switch (set) {
    'B' => [group('L', 83.17, 110.33, 'tf'), group('R', 319.17, 109.67, 'rc')],
    'C' => [
      group('L', 52, 48, 'trash'),
      group('M', 112, 48, 'folder'),
      group('R', 350, 48, 'compose'),
    ],
    _ => [group('L', 63.83, 71.67, 'filter'), group('R', 350, 48, 'compose')],
  };
}

typedef _Change = (double, List<GlassBarCapsuleLayout>);

/// Replays [changes] and checks, for every change, where UIKit's glass
/// element of a group that comes or goes beside a survivor starts and
/// ends: the smallest element rows in the change's window (a fifth of the
/// fitted box) against the model's newborn at its birth and its dying
/// capsule at rest; and that a group the model shows in place is one
/// UIKit hosts in its second SDF layer.
({int births, int deaths, int inPlace}) _replay(
  List<Map<String, Object?>> rows,
  List<_Change> changes,
  List<GlassBarCapsuleLayout> initial, {
  required GlassBarTransitionSpec spec,
  String? bar,
  Set<int> skip = const {},
}) {
  final elements = [
    for (final r in rows)
      if (r['cls'] == 'SDFElement' && (bar == null || r['bar'] == bar)) r,
  ];
  var births = 0;
  var deaths = 0;
  var inPlace = 0;
  final motion = GlassBarMotion(spec: spec);
  motion.setLayout(changes.first.$1 - 1, initial);
  for (var k = 0; k < changes.length; k++) {
    final (t0, layout) = changes[k];
    motion.setLayout(t0, layout);
    if (skip.contains(k)) continue;
    final window = [
      for (final r in elements)
        if (_d(r, 't') > t0 - 0.05 && _d(r, 't') < t0 + 0.75) r,
    ];
    final tiny = [
      for (final r in window)
        if (_d(r, 'h') < 0.21 * 48 + 0.5) r,
    ];
    final host1 = window.any((r) => r['host'] == 1);
    final born = [
      for (final c in motion.capsules)
        if (!c.apart && !c.leaving && c.rect.height < 0.21 * 48) c,
    ];
    final apart = motion.capsules.any((c) => c.apart);
    if (bar != null) {
      expect(apart, host1, reason: 'change $k in place');
    }
    if (apart) inPlace++;
    for (final c in born) {
      expect(tiny, isNotEmpty, reason: 'change $k: no element born small');
      final first = tiny.first;
      expect(
        c.rect.center.dx,
        moreOrLessEquals(_d(first, 'x'), epsilon: 0.6),
        reason: 'change $k birth',
      );
      expect(c.rect.width, moreOrLessEquals(_d(first, 'w'), epsilon: 0.6));
      expect(c.rect.height, moreOrLessEquals(_d(first, 'h'), epsilon: 0.6));
      births++;
    }
    final dying = [
      for (final c in motion.capsules)
        if (c.leaving && !c.apart) c.id,
    ];
    if (dying.isEmpty) continue;
    final end = k + 1 < changes.length ? changes[k + 1].$1 : t0 + 2;
    final rest = <Object, Rect>{};
    for (var t = t0; t < end - 0.01; t += 1 / 120) {
      motion.advance(t);
      for (final c in motion.capsules) {
        if (dying.contains(c.id)) rest[c.id] = c.rect;
      }
    }
    expect(tiny, isNotEmpty, reason: 'change $k: no element died small');
    final last = tiny.last;
    for (final r in rest.values) {
      expect(
        r.center.dx,
        moreOrLessEquals(_d(last, 'x'), epsilon: 0.6),
        reason: 'change $k death',
      );
      expect(r.width, moreOrLessEquals(_d(last, 'w'), epsilon: 0.6));
      expect(r.height, moreOrLessEquals(_d(last, 'h'), epsilon: 0.6));
      deaths++;
    }
  }
  return (births: births, deaths: deaths, inPlace: inPlace);
}

void main() {
  group('births and deaths within a side (iPhone 16 Pro, iOS 27.0.1)', () {
    test('navigation bar push / pop, navseg set b', () {
      final rows = _rows(
        'test/fixtures/ios27-device/bars/navsegb-push-pop.jsonl',
      );
      final events = [
        for (final r in rows)
          if (r['k'] == 'evt' && (r['e'] == 'push' || r['e'] == 'pop')) r,
      ];
      final changes = [
        for (final r in events) (_d(r, 't'), _navB(r['to']! as int)),
      ];
      final result = _replay(
        rows,
        changes,
        _navB(0),
        spec: GlassBarTransitionSpec.navigation,
        bar: 'nav',
        skip: {
          for (var k = 0; k < events.length; k++)
            if (events[k]['from'] == 4 || events[k]['to'] == 4) k,
        },
      );
      expect(result.births, 3);
      expect(result.deaths, 3);
    });

    test('toolbar replacements, navseg set b', () {
      var births = 0;
      var deaths = 0;
      var inPlace = 0;
      for (final name in ['navsegb-toolbar', 'navsegb-toolbar2']) {
        final rows = _rows('test/fixtures/ios27-device/bars/$name.jsonl');
        final changes = [
          for (final r in rows)
            if (r['k'] == 'evt' && r['e'] == 'setToolbarItems')
              (_d(r, 't'), _toolbarB(r['set']! as String)),
        ];
        final result = _replay(
          rows,
          changes,
          _toolbarB('D'),
          spec: GlassBarTransitionSpec.standard,
          bar: 'tool',
        );
        births += result.births;
        deaths += result.deaths;
        inPlace += result.inPlace;
      }
      expect(births, 3);
      expect(deaths, 3);
      expect(inPlace, 4);
    });

    test('the nav scene: list to detail and back', () {
      final rows = _rows('test/fixtures/ios27-device/bars/push-pop.jsonl');
      final changes = [
        for (final r in rows)
          if (r['k'] == 'evt' && (r['e'] == 'push' || r['e'] == 'pop'))
            (_d(r, 't'), _listDetail(r['e'] == 'push' ? 'detail' : 'list')),
      ];
      final result = _replay(
        rows,
        changes,
        _listDetail('list'),
        spec: GlassBarTransitionSpec.navigation,
      );
      expect(result.births, 1);
      expect(result.deaths, 1);
    });

    test('the nav scene: toolbar item replacement', () {
      final rows = _rows('test/fixtures/ios27-device/bars/toolbar-swap.jsonl');
      final changes = [
        for (final r in rows)
          if (r['k'] == 'evt' && r['e'] == 'setToolbarItems')
            (_d(r, 't'), _toolbarSwap(r['set']! as String)),
      ];
      final result = _replay(
        rows,
        changes,
        _toolbarSwap('A'),
        spec: GlassBarTransitionSpec.standard,
      );
      expect(result.births, 1);
      expect(result.deaths, 1);
    });
  });

  group('which capsule survives', () {
    test('an anonymous group continues the nearest one of its side', () {
      final motion = GlassBarMotion(spec: GlassBarTransitionSpec.navigation);
      motion.setLayout(0, _navB(1));
      motion.setLayout(1, _navB(2));
      motion.advance(1.001);
      final trailing = [
        for (final c in motion.capsules)
          if (c.segment == _trailing) c,
      ];
      final kept = trailing.firstWhere((c) => !c.leaving);
      final gone = trailing.firstWhere((c) => c.leaving);
      expect(kept.rect.center.dx, moreOrLessEquals(262.33, epsilon: 1e-6));
      expect(gone.rect.center.dx, moreOrLessEquals(355, epsilon: 1e-6));
      motion.advance(3);
      expect(
        motion.capsules.where((c) => c.segment == _trailing),
        hasLength(1),
      );
      expect(motion.isSettled, isTrue);
    });

    test('a group with an id keeps it, the others pair by place', () {
      final motion = GlassBarMotion(spec: GlassBarTransitionSpec.navigation);
      final x = _capsule('x', _trailing, 355, 62, 84, ['x'], anonymous: false);
      motion.setLayout(0, [
        _capsule(('trailing', 1), _trailing, 262.33, 99.33, 84, ['p', 'm']),
        x,
      ]);
      motion.setLayout(1, [x]);
      motion.advance(1.001);
      expect(motion.capsuleFrame('x')!.rect.width, moreOrLessEquals(62));
      final gone = motion.capsules.firstWhere((c) => c.leaving);
      expect(gone.id, ('trailing', 1));
      motion.advance(3);
      expect(motion.capsules, hasLength(1));
    });

    test('a leaving group that loses its id to a survivor is told apart', () {
      final motion = GlassBarMotion(spec: GlassBarTransitionSpec.navigation);
      motion.setLayout(0, [
        _capsule(('trailing', 1), _trailing, 230, 44, 84, ['a']),
        _capsule(('trailing', 0), _trailing, 300, 80, 84, ['b']),
      ]);
      motion.setLayout(1, [
        _capsule(('trailing', 0), _trailing, 235, 44, 84, ['c']),
      ]);
      motion.advance(1.001);
      final ids = [for (final c in motion.capsules) c.id];
      expect(ids, hasLength(2));
      expect(ids.toSet(), hasLength(2));
      final gone = motion.capsules.firstWhere((c) => c.leaving);
      expect(gone.id, isA<GlassBarDepartedId>());
      expect((gone.id as GlassBarDepartedId).id, ('trailing', 0));
    });
  });

  group('the birth and death law', () {
    test('a group grows out of the survivor it fits in, flush to its side', () {
      final motion = GlassBarMotion(spec: GlassBarTransitionSpec.navigation);
      motion.setLayout(0, _navB(2));
      motion.setLayout(1, _navB(3));
      motion.advance(1.0001);
      final born = motion.capsuleFrame(('trailing', 1))!;
      expect(born.apart, isFalse);
      expect(born.rect.center.dx, moreOrLessEquals(212.33 + 22, epsilon: 0.01));
      expect(born.rect.width, moreOrLessEquals(44 * 0.2, epsilon: 1e-6));
      motion.advance(3);
      expect(
        motion.capsuleFrame(('trailing', 1))!.rect.center.dx,
        moreOrLessEquals(178.33, epsilon: 0.01),
      );
      expect(motion.isSettled, isTrue);
    });

    test('a navigation bar grows a larger group out of the survivor', () {
      final motion = GlassBarMotion(spec: GlassBarTransitionSpec.navigation);
      motion.setLayout(0, _navB(0));
      motion.setLayout(1, _navB(1));
      motion.advance(1.0001);
      final born = motion.capsuleFrame(('trailing', 1))!;
      expect(born.apart, isFalse);
      expect(born.rect.center.dx, moreOrLessEquals(355, epsilon: 1e-6));
      expect(born.rect.width, moreOrLessEquals(62 * 0.2, epsilon: 1e-6));
      expect(born.rect.height, moreOrLessEquals(44 * 0.2, epsilon: 1e-6));
    });

    test('a toolbar shows a group too large for its survivor in place', () {
      final motion = GlassBarMotion();
      motion.setLayout(0, _toolbarB('D'));
      motion.setLayout(1, _toolbarB('E'));
      motion.advance(1.0001);
      final born = motion.capsuleFrame(('trailing', 1))!;
      expect(born.apart, isTrue);
      expect(born.rect.center.dx, moreOrLessEquals(230.17, epsilon: 1e-6));
      expect(born.opacity, 0);
      final kept = motion.capsuleFrame(('trailing', 0))!;
      expect(kept.rect.width, moreOrLessEquals(48, epsilon: 1e-6));
      motion.advance(1.3);
      expect(
        motion.capsuleFrame(('trailing', 0))!.rect.width,
        moreOrLessEquals(48, epsilon: 1e-6),
        reason: 'a survivor nothing grew out of does not swell',
      );
    });

    test('a group as large as its survivor fits it at any place', () {
      for (var k = 0; k < 40; k++) {
        final left = 16 + k / 3;
        final motion = GlassBarMotion(spec: GlassBarTransitionSpec.navigation);
        GlassBarCapsuleLayout at(Object id, double x, double w) =>
            GlassBarCapsuleLayout(
              id,
              Rect.fromLTWH(x, 62, w, 44),
              [GlassBarItemLayout('$id', Rect.fromLTWH(x, 62, w, 44))],
              segment: _leading,
              anonymous: true,
            );
        motion.setLayout(0, [at(('leading', 0), left, 44 + k / 7)]);
        motion.setLayout(1, [
          at(('leading', 0), left, 44 + k / 7),
          at(('leading', 1), left + 56 + k / 7, 44 + k / 7),
        ]);
        motion.advance(1.0001);
        expect(motion.capsules, hasLength(2));
      }
    });

    test('a group that goes shrinks into its survivor and vanishes', () {
      final motion = GlassBarMotion(spec: GlassBarTransitionSpec.navigation);
      motion.setLayout(0, _navB(1));
      motion.setLayout(1, _navB(0));
      final dying = motion.capsules.firstWhere(
        (c) => c.leaving && c.segment == _trailing,
      );
      expect(dying.apart, isFalse);
      Rect? last;
      for (var t = 1.0; t < 3; t += 1 / 120) {
        motion.advance(t);
        for (final c in motion.capsules) {
          if (c.leaving && c.segment == _trailing) last = c.rect;
        }
      }
      expect(last!.center.dx, moreOrLessEquals(355, epsilon: 0.1));
      expect(last.width, moreOrLessEquals(62 * 0.2, epsilon: 0.1));
      expect(motion.capsules.where((c) => c.leaving), isEmpty);
      expect(motion.itemFrame('plus'), isNull);
      expect(motion.isSettled, isTrue);
    });

    test('items of a group that goes leave into its death point', () {
      final motion = GlassBarMotion(spec: GlassBarTransitionSpec.navigation);
      motion.setLayout(0, _navB(3));
      motion.setLayout(1, _navB(2));
      motion.advance(1.3);
      final heart = motion.itemFrame('heart3')!;
      expect(heart.leaving, isTrue);
      expect(heart.center.dx, greaterThan(200));
    });
  });
}

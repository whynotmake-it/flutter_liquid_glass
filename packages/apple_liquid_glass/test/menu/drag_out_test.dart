import 'dart:convert';
import 'dart:math' as math;

import 'package:apple_liquid_glass/src/motions/menu_metrics.dart';
import 'package:apple_liquid_glass/src/motions/menu_motion.dart';
import 'package:apple_liquid_glass/src/motions/menu_values.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

/// The standard tuning with this phone's 250 pt tall four-row menu (82 +
/// 42 per row: menu/manifest.json), so the finger crosses the recorded
/// menu's edges where it did on the device.
const _device = MenuMetrics(topInset: 41);

/// A capture of UIKit's open-menu flex: its touches and, per 120 Hz lab
/// tick, the list view's frame and the flex's state.
class _Capture {
  _Capture(this.name, this.button);

  final String name;

  /// The button that opened the menu, in the capture's coordinates.
  final Rect button;

  late final List<Map<String, Object?>> rows = [
    for (final line in Fixtures.lines(
      'test/fixtures/ios27-device/menu/$name.jsonl',
    ))
      if (line.trim().isNotEmpty)
        (jsonDecode(line) as Map).cast<String, Object?>(),
  ];

  /// The drags on the open menu: each touch-down that is not a tap on the
  /// button or the dismissing tap, with its touches and the lab ticks up
  /// to 1.3 s after its lift.
  late final List<_Gesture> gestures = () {
    double n(Map<String, Object?> row, String key) =>
        (row[key]! as num).toDouble();
    final touches = [
      for (final row in rows)
        if (row['k'] == 'touch')
          (
            t: n(row, 't'),
            phase: row['phase']! as int,
            at: Offset(n(row, 'x'), n(row, 'y')),
          ),
    ];
    final ticks = [
      for (final row in rows)
        if (row['k'] == 'flex')
          (
            t: n(row, 't'),
            active: row['panState'] == 1 || row['panState'] == 2,
            frame: _rect(row['frame']! as List),
            velocity: (row['translationY_v'] as num?)?.toDouble() ?? 0,
          ),
    ];
    final menu = ticks.first.frame;
    final result = <_Gesture>[];
    for (var i = 0; i < touches.length; i++) {
      final down = touches[i];
      if (down.phase != 0 ||
          !menu.contains(down.at) ||
          button.contains(down.at)) {
        continue;
      }
      var j = i;
      while (touches[j].phase != 3) {
        j++;
      }
      final start = down.t;
      final end = touches[j].t;
      result.add((
        touches: [
          for (final touch in touches.sublist(i, j + 1))
            (t: touch.t - start, phase: touch.phase, at: touch.at),
        ],
        ticks: [
          for (final tick in ticks)
            if (tick.t >= start && tick.t <= end + 1.3)
              (
                t: tick.t - start,
                active: tick.active,
                frame: tick.frame,
                velocity: tick.velocity,
              ),
        ],
        lift: end - start,
      ));
    }
    return result;
  }();

  static Rect _rect(List<Object?> v) => Rect.fromLTWH(
    (v[0]! as num).toDouble(),
    (v[1]! as num).toDouble(),
    (v[2]! as num).toDouble(),
    (v[3]! as num).toDouble(),
  );

  /// A menu opened on the capture's button and settled, as the device's
  /// was before the gesture.
  MenuMotion open() {
    final motion = MenuMotion(
      source: MenuSource(button),
      itemCount: 4,
      bounds: const Size(402, 874),
      padding: const EdgeInsets.only(top: 62, bottom: 34),
      metrics: _device,
    );
    motion.advance(-4);
    motion.open(-3);
    motion.advance(-0.5);
    return motion;
  }
}

typedef _Gesture = ({
  List<({double t, int phase, Offset at})> touches,
  List<({double t, bool active, Rect frame, double velocity})> ticks,
  double lift,
});

/// Plays [gesture]'s touches on [motion] up to each lab tick and hands the
/// tick to [onTick] once the motion stands at its time, with the offset
/// from the capture's coordinates to the motion's.
void _play(
  MenuMotion motion,
  _Gesture gesture,
  void Function(
    ({double t, bool active, Rect frame, double velocity}) tick,
    Rect native,
  )
  onTick,
) {
  final native = gesture.ticks.first.frame;
  final offset = motion.menuRect.center - native.center;
  var touch = 0;
  for (final tick in gesture.ticks) {
    while (touch < gesture.touches.length &&
        gesture.touches[touch].t <= tick.t) {
      final event = gesture.touches[touch];
      final at = event.at + offset;
      switch (event.phase) {
        case 0:
          motion.pointerDown(event.t, at);
        case 3:
          motion.pointerUp(event.t, at);
        default:
          motion.pointerMove(event.t, at);
      }
      touch++;
    }
    motion.advance(tick.t);
    onTick(tick, native);
  }
}

/// The squared errors of the four frame edges the motion flexes against
/// the recorded ones, each relative to its rest frame, over [gesture].
List<double> _errors(
  _Capture capture,
  _Gesture gesture, {
  bool? released,
}) {
  final motion = capture.open();
  final errors = <double>[];
  _play(motion, gesture, (tick, native) {
    final flexed = motion.flexedMenuRect;
    final base = motion.menuRect;
    if (released != null && released != (tick.t > gesture.lift + 0.02)) return;
    errors.addAll([
      (flexed.left - base.left) - (tick.frame.left - native.left),
      (flexed.right - base.right) - (tick.frame.right - native.right),
      (flexed.top - base.top) - (tick.frame.top - native.top),
      (flexed.bottom - base.bottom) - (tick.frame.bottom - native.bottom),
    ]);
  });
  return errors;
}

double _rms(Iterable<double> errors) =>
    math.sqrt(errors.fold<double>(0, (a, e) => a + e * e) / errors.length);

final _captures = [
  _Capture('drag-out-flex', const Rect.fromLTWH(179, 300, 44, 44)),
  _Capture('drag-out-upward-flex', const Rect.fromLTWH(179, 760, 44, 44)),
  _Capture('drag-out-animation-tap', const Rect.fromLTWH(179, 300, 44, 44)),
];

/// The older capture: the list view's frames as drawn, per 120 Hz lab
/// tick, under four drags off the same menu (a holdout for the flex's
/// numbers, which were read from UIKit rather than fitted to it).
List<_Gesture> _drawn() {
  final rows = [
    for (final line in Fixtures.lines(
      'test/fixtures/ios27-device/menu/drag-out.jsonl',
    ))
      if (line.trim().isNotEmpty)
        (jsonDecode(line) as Map).cast<String, Object?>(),
  ];
  double n(Map<String, Object?> row, String key) =>
      (row[key]! as num).toDouble();
  final touches = [
    for (final row in rows)
      if (row['k'] == 'touch')
        (
          t: n(row, 't'),
          phase: row['phase']! as int,
          at: Offset(n(row, 'x'), n(row, 'y')),
        ),
  ];
  final frames = [
    for (final row in rows)
      if (row['k'] == 'frame' && row['cls'] == '_UIContextMenuListView')
        (
          t: n(row, 't'),
          frame: Rect.fromCenter(
            center: Offset(n(row, 'x'), n(row, 'y')),
            width: n(row, 'w'),
            height: n(row, 'h'),
          ),
        ),
  ];
  final gestures = <_Gesture>[];
  for (var i = 0; i < touches.length; i++) {
    final down = touches[i];
    if (down.phase != 0 || (down.at.dy - 365.5).abs() > 5) continue;
    var j = i;
    while (touches[j].phase != 3) {
      j++;
    }
    final start = down.t;
    final end = touches[j].t;
    gestures.add((
      touches: [
        for (final touch in touches.sublist(i, j + 1))
          (t: touch.t - start, phase: touch.phase, at: touch.at),
      ],
      ticks: [
        for (final frame in frames)
          if (frame.t >= start && frame.t <= end + 1)
            (
              t: frame.t - start,
              active: false,
              frame: frame.frame,
              velocity: 0,
            ),
      ],
      lift: end - start,
    ));
  }
  return gestures;
}

final _drawnCapture = _Capture(
  'drag-out',
  const Rect.fromLTWH(179, 300, 44, 44),
);

void main() {
  const names = ['up', 'down', 'left', 'right'];

  test('the captures hold the drags off the menu', () {
    expect(_captures[0].gestures, hasLength(4));
    expect(_captures[1].gestures, hasLength(2));
    expect(_captures[2].gestures, hasLength(2));
    expect(_drawn(), hasLength(4));
  });

  // Input-only replays: the touches in, the list view's frame out, no
  // recorded flex state used. The errors, pt rms over the four edges:
  // drag-out-flex up 0.13, down 0.13, left 0.09, right 0.09;
  // drag-out-upward-flex 0.12 and 0.11; the animation tap capture 0.15
  // and 0.11. UIKit's own recorded translationY velocity drives
  // lab/menu_flex_model.py to 0.25, 0.26 and 0.28.
  const bounds = {
    'drag-out-flex': [0.15, 0.15, 0.1, 0.1],
    'drag-out-upward-flex': [0.14, 0.13],
    'drag-out-animation-tap': [0.17, 0.13],
  };
  for (final capture in _captures) {
    for (var i = 0; i < capture.gestures.length; i++) {
      final name = capture.name == 'drag-out-upward-flex'
          ? ['up', 'down'][i]
          : names[i];
      test('a finger dragged $name off the menu flexes it as UIKit does '
          '(${capture.name})', () {
        final errors = _errors(capture, capture.gestures[i]);
        expect(_rms(errors), lessThan(bounds[capture.name]![i]));
      });
    }
  }

  test('the menu returns from a lift as UIKit does', () {
    // The frames after each lift, pt rms: 0.17, 0.15 and 0.17.
    for (final (capture, bound) in [
      (_captures[0], 0.19),
      (_captures[1], 0.17),
      (_captures[2], 0.19),
    ]) {
      final errors = [
        for (final gesture in capture.gestures)
          ..._errors(capture, gesture, released: true),
      ];
      expect(_rms(errors), lessThan(bound), reason: capture.name);
    }
  });

  test('the drawn frames of the older capture agree', () {
    // Holdout: up 0.16, down 0.12, left 0.06, right 0.06 pt rms (the
    // model fitted to this capture before reached 0.40, 0.36, 0.17, 0.17).
    final gestures = _drawn();
    const drawn = [0.18, 0.14, 0.07, 0.07];
    for (var i = 0; i < gestures.length; i++) {
      final errors = _errors(_drawnCapture, gestures[i]);
      expect(_rms(errors), lessThan(drawn[i]), reason: names[i]);
    }
  });

  for (var i = 0; i < 4; i++) {
    test('the content rides the menu flexed ${names[i]} on every '
        'recorded frame', () {
      final capture = _captures[0];
      final motion = capture.open();
      var largest = 0.0;
      _play(motion, capture.gestures[i], (tick, native) {
        if (!motion.isOpen) return;
        final shape = motion.menuBlob.rect;
        final content = motion.contentRect;
        final reason = '${names[i]} at ${tick.t}';
        expect(content.left, closeTo(shape.left, 0.5), reason: reason);
        expect(content.top, closeTo(shape.top, 0.5), reason: reason);
        expect(content.right, closeTo(shape.right, 0.5), reason: reason);
        expect(content.bottom, closeTo(shape.bottom, 0.5), reason: reason);
        final stretch = motion.contentStretch;
        final scale = motion.contentScale;
        final rest = motion.menuRect.size;
        expect(
          rest.width * scale * stretch.dx,
          closeTo(content.width, 1e-6),
          reason: reason,
        );
        expect(
          rest.height * scale * stretch.dy,
          closeTo(content.height, 1e-6),
          reason: reason,
        );
        final rect = motion.flexedMenuRect;
        largest = [
          largest,
          (rect.left - motion.menuRect.left).abs(),
          (rect.top - motion.menuRect.top).abs(),
          (rect.right - motion.menuRect.right).abs(),
          (rect.bottom - motion.menuRect.bottom).abs(),
        ].reduce(math.max);
      });
      expect(largest, greaterThan(4), reason: 'the replay flexes the menu');
    });
  }

  test('a row is hit where the flexed menu shows it', () {
    final capture = _captures[0];
    final motion = capture.open();
    final rest = motion.menuRect;
    final spans = [
      for (var i = 0; i < 4; i++)
        Rect.fromLTWH(rest.left, rest.top + 41 + 42.0 * i, rest.width, 42),
    ];
    final rows = [for (final span in spans) motion.rowAt(span.center)];
    expect(rows.toSet(), hasLength(4));
    var checked = 0;
    var moved = 0;
    _play(motion, capture.gestures[1], (tick, native) {
      final shown = motion.flexedMenuRect;
      if (!motion.isOpen || shown.bottom - rest.bottom < 6 || checked > 0) {
        return;
      }
      checked++;
      double y(double at) =>
          shown.top + (at - rest.top) * shown.height / rest.height;
      for (var i = 0; i < spans.length; i++) {
        for (final at in [y(spans[i].top) + 1, y(spans[i].bottom) - 1]) {
          final point = Offset(shown.center.dx, at);
          expect(motion.rowAt(point), rows[i], reason: 'row $i at $at');
          if (!spans[i].contains(point)) moved++;
        }
      }
    });
    expect(checked, 1, reason: 'the drag down stretches the menu by 6 pt');
    expect(moved, greaterThan(0), reason: 'some rows show off their rest');
  });

  test('a finger resting where it touched down leaves the menu still', () {
    final motion = MenuMotion(
      source: MenuSource(const Rect.fromLTWH(179, 300, 44, 44)),
      itemCount: 4,
      bounds: const Size(402, 874),
    );
    motion.advance(-4);
    motion.open(-3);
    motion.advance(0);
    final rest = motion.menuRect;
    final at = rest.center.translate(0, -50);
    motion.pointerDown(0, at);
    motion.pointerMove(0.1, at);
    motion.advance(2);
    expect(motion.flexedMenuRect, rest);
    expect(motion.isSettled, isTrue);
  });
}

import 'dart:math' as math;

import 'package:apple_liquid_glass/src/motions/switch_motion.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/switch_lift.dart';
import 'support/trace.dart';

const _dir = 'test/fixtures/ios27/controls';
const _device = 'test/fixtures/ios27-device/controls';

/// The knob center x of the off switch in the recorded scene.
const double _offX = 210;

List<TraceFrame> _knob(Trace trace) => [
  for (final f in trace.frames)
    if (f.cls == '_UILiquidLensView') f,
];

/// Replays a recorded tap and returns rms errors of the knob center and
/// the knob's lifted width.
({double center, double width}) _replayTap(String file, {required bool on}) {
  final trace = Trace.load('$_dir/$file');
  final frames = _knob(trace);
  final down = trace.touches.firstWhere((t) => t.phase == 0);
  final up = trace.touches.firstWhere((t) => t.phase == 3);
  final rest = frames.first;
  final lifting = frames.firstWhere((f) => (f.opt('lpp') ?? 0) > 0.01);
  final liftLag = lifting.t - timeToLift(lifting.opt('lpp')!) - down.t;
  final moved = frames.firstWhere(
    (f) => f.t > up.t && (f.x - rest.x).abs() > 0.3,
  );
  final travelLag = frames[frames.indexOf(moved) - 1].t - up.t;
  final motion = SwitchMotion(value: on, frameRate: 60);
  motion.advance(down.t - 0.1);
  motion.pointerDown(down.t + liftLag, _offX);
  final release = up.t + travelLag;
  var released = false;
  var center = 0.0;
  var width = 0.0;
  var n = 0;
  for (final f in frames) {
    if (f.t < down.t + liftLag) continue;
    if (!released && f.t >= release) {
      motion.pointerUp(release, _offX);
      released = true;
    }
    motion.advance(f.t);
    final size = motion.lens.size(f.t);
    center += math.pow(_offX + motion.knob - f.x, 2);
    width += math.pow(size.width - f.bw, 2);
    n++;
  }
  return (center: math.sqrt(center / n), width: math.sqrt(width / n));
}

double _rms(List<double> errors) => math.sqrt(
  errors.fold<double>(0, (sum, e) => sum + e * e) / errors.length,
);

/// Replays every touch of the device capture [file] and returns the
/// model's final value, the recorded one, the error of the settled knob
/// and the rms error of the knob while the finger is down.
({bool value, bool recorded, double settled, double drag}) _replayDevice(
  String file,
) {
  final trace = Trace.load('$_device/$file');
  final frames = _knob(trace);
  final states = [
    for (final row in trace.states)
      if (row['on'] != null) row['on']! as bool,
  ];
  final first = trace.touches.first;
  final rest = frames.firstWhere((f) => f.t < first.t).x;
  final on = states.first;
  final motion = SwitchMotion(value: on);
  final off = on ? rest - SwitchMotion.travel : rest;
  motion.advance(first.t - 0.1);
  var next = 0;
  var down = false;
  final drag = <double>[];
  for (final f in frames) {
    while (next < trace.touches.length && trace.touches[next].t <= f.t) {
      final touch = trace.touches[next++];
      switch (touch.phase) {
        case 0:
          motion.pointerDown(touch.t, touch.x);
          down = true;
        case 3:
          motion.pointerUp(touch.t, touch.x);
          down = false;
        case _:
          motion.pointerMove(touch.t, touch.x);
      }
    }
    motion.advance(f.t);
    if (down) drag.add(off + motion.knob - f.x);
  }
  motion.advance(frames.last.t + 2);
  return (
    value: motion.value,
    recorded: states.last,
    settled: (off + motion.knob - frames.last.x).abs(),
    drag: drag.isEmpty ? 0 : _rms(drag),
  );
}

void main() {
  test('a tap toggles off to on like the native switch', () {
    final e = _replayTap('switch-off-tap.jsonl', on: false);
    expect(e.center, lessThan(0.45));
    expect(e.width, lessThan(0.3));
  });

  test('a tap toggles on to off like the native switch', () {
    final e = _replayTap('switch-on-tap.jsonl', on: true);
    expect(e.center, lessThan(0.5));
    expect(e.width, lessThan(0.8));
  });

  test('release rules match the native captures', () {
    for (final (file, expected) in const [
      ('switch-off-drag-right50.jsonl', true),
      ('switch-off-drag-right8.jsonl', true),
      ('switch-off-drag-left50.jsonl', true),
      ('switch-off-drag-there-back.jsonl', false),
      ('switch-off-hold800.jsonl', true),
    ]) {
      final trace = Trace.load('$_dir/$file');
      final motion = SwitchMotion(value: false, frameRate: 60);
      motion.advance(trace.touches.first.t - 0.1);
      for (final touch in trace.touches) {
        switch (touch.phase) {
          case 0:
            motion.pointerDown(touch.t, touch.x);
          case 3:
            motion.pointerUp(touch.t, touch.x);
          default:
            motion.pointerMove(touch.t, touch.x);
        }
      }
      motion.advance(trace.touches.last.t + 2);
      expect(motion.value, expected, reason: file);
      final settled = _knob(trace).last;
      expect(_offX + motion.knob, closeTo(settled.x, 0.5), reason: file);
    }
  });

  test('a drag flips the shown state every 25 pt toward the other one', () {
    const variants = {'a': true, 'b': true, 'c': true, 'd': false, 'e': true};
    final drag = <double>[];
    for (final MapEntry(key: variant, value: expected) in variants.entries) {
      for (final rep in [1, 2, 3]) {
        final file = 'switch-tb-$variant$rep.jsonl';
        final e = _replayDevice(file);
        expect(e.value, expected, reason: file);
        expect(e.recorded, expected, reason: '$file recording');
        expect(e.settled, lessThan(0.5), reason: '$file settled knob');
        expect(e.drag, lessThan(1.6), reason: '$file drag');
        drag.add(e.drag);
      }
    }
    expect(_rms(drag), lessThan(1.2));
  });

  test('earlier device captures keep their release rules', () {
    for (final file in const [
      'switch-off-drag-left50.jsonl',
      'switch-off-drag-right100.jsonl',
      'switch-off-drag-right15.jsonl',
      'switch-off-drag-right50.jsonl',
      'switch-off-drag-right8.jsonl',
      'switch-off-fling40.jsonl',
      'switch-off-hold800.jsonl',
      'switch-off-tap.jsonl',
      'switch-on-tap.jsonl',
      'switch-taps.jsonl',
    ]) {
      final e = _replayDevice(file);
      expect(e.value, e.recorded, reason: file);
      expect(e.settled, lessThan(0.5), reason: '$file settled knob');
    }
  });

  test('a drag whose recorded knob never reached the far end toggles', () {
    // The earliest device there-and-back capture tracked the finger late:
    // its knob trails the finger by about 20 pixels and even retreats
    // while the finger advances, so its touches cannot be replayed. The
    // release rule still holds on the knob it recorded.
    final trace = Trace.load('$_device/switch-off-drag-there-back.jsonl');
    final up = trace.touches.lastWhere((t) => t.phase == 3).t;
    final frames = [
      for (final f in _knob(trace))
        if (f.t <= up) f,
    ];
    final rest = frames.first.x;
    final reach = frames.fold<double>(
      0,
      (m, f) => math.max(m, f.x - rest),
    );
    final on = [
      for (final row in trace.states)
        if (row['on'] != null) row['on']! as bool,
    ];
    expect(reach, lessThan(SwitchMotion.travel - 4));
    expect(on.first, isFalse);
    expect(on.last, isTrue);
  });
}

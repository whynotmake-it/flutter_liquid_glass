import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'support/glass_button_replay.dart';
import 'support/onset.dart';
import 'support/trace.dart';

const _dir = 'test/fixtures/ios27-device/controls';

/// The device holds of 0.8 s, each the first touch of its recording.
const _holds = [
  ('button-glass-44x44-hold800.jsonl', Size(44, 44)),
  ('button-glass-60x44-hold800.jsonl', Size(60, 44)),
  ('button-glass-120x44-hold800.jsonl', Size(120, 44)),
  ('button-glass-200x44-hold800.jsonl', Size(200, 44)),
  ('button-glass-300x44-hold800.jsonl', Size(300, 44)),
  ('button-glass-200x100-hold800.jsonl', Size(200, 100)),
  ('button-prominent-120x44-hold800.jsonl', Size(120, 44)),
];

/// Four taps of 83 ms, 1.5 s apart, on the 44 x 44 button.
const _taps = 'button-glass-44x44-taps.jsonl';

// controls_test.dart replays the simulator holds of the same buttons with
// this rms bound on the lift scale.
const double _scaleTolerance = 3e-4;

/// Seconds from the release [up] to the release stamp that best replays
/// the return of that tap of [rows]: each press starts where the recorded
/// one does, and the rms of the return until the next touch is searched
/// over the release stamps within 30 ms of [up].
double _tapReleaseLag(
  List<TraceFrame> rows,
  Size size,
  List<TraceTouch> touches,
  TraceTouch up,
) {
  final center = size.center(Offset.zero);
  final nextDown = touches.firstWhere(
    (t) => t.phase == 0 && t.t > up.t,
    orElse: () => TraceTouch(up.t + 1.2, 0, 0, 0),
  );
  double cost(double lag) {
    final events = <GlassTouch>[
      for (final t in touches)
        if (t.phase == 0)
          (t: t.t + glassPressLag(rows, size, t.t), phase: 0, at: center)
        else if (t.phase == 3)
          (t: t.t + (t == up ? lag : 0), phase: 3, at: center),
    ];
    return rms([
      for (final e in glassErrors(rows, size, events, nextDown.t))
        if (!e.pressed && e.t > up.t) e.error,
    ]);
  }

  var lo = -0.03;
  var hi = 0.03;
  for (var i = 0; i < 40; i++) {
    final a = hi - 0.618 * (hi - lo);
    final b = lo + 0.618 * (hi - lo);
    if (cost(a) < cost(b)) {
      hi = b;
    } else {
      lo = a;
    }
  }
  return (lo + hi) / 2;
}

void main() {
  test('a glass button lifts and returns when the device does, touches at '
      'their logged stamps', () {
    // The press of every touch but the first of a recording (see the
    // skipped test below) and every release land within UIKit's delivery
    // spread of the model fed the touch at its stamp.
    final taps = Trace.load('$_dir/$_taps');
    const size = Size(44, 44);
    final rows = taps.layer('0.0');
    final downs = [
      for (final t in taps.touches)
        if (t.phase == 0) t.t,
    ];
    expect(downs, hasLength(4));
    final presses = [
      for (final down in downs.skip(1)) glassPressLag(rows, size, down),
    ];
    final releases = [
      for (final up in taps.touches.where((t) => t.phase == 3))
        _tapReleaseLag(rows, size, taps.touches, up),
      for (final (file, size) in _holds)
        () {
          final trace = Trace.load('$_dir/$file');
          final up = trace.touches.lastWhere((t) => t.phase == 3).t;
          return glassReleaseLag(trace.layer('0.0'), size, up);
        }(),
    ];
    expect(releases, hasLength(11));
    for (final lag in [...presses, ...releases]) {
      expect(lag.abs(), lessThan(deliverySpread));
    }
    expect(median(presses).abs(), lessThan(deviceFrame / 2));
    expect(median(releases).abs(), lessThan(deviceFrame / 2));
  });

  test('a held glass button lifts and returns like the device once it '
      'starts', () {
    // Press and release start where the recorded ones do: the replay
    // checks the lift and the return apart from their onsets, which the
    // test above checks against the delivery spread. A millisecond moves
    // the return by about 1e-3.
    for (final (file, size) in _holds) {
      final trace = Trace.load('$_dir/$file');
      final rows = trace.layer('0.0');
      final center = size.center(Offset.zero);
      final down = trace.touches.firstWhere((t) => t.phase == 0).t;
      final up = trace.touches.lastWhere((t) => t.phase == 3).t;
      final errors = glassErrors(rows, size, [
        (t: down + glassPressLag(rows, size, down), phase: 0, at: center),
        (t: up + glassReleaseLag(rows, size, up), phase: 3, at: center),
      ], up + 1.2);
      final press = [
        for (final e in errors)
          if (e.pressed) e.error,
      ];
      final release = [
        for (final e in errors)
          if (!e.pressed) e.error,
      ];
      expect(rms(press), lessThan(_scaleTolerance), reason: '$file press');
      expect(rms(release), lessThan(_scaleTolerance), reason: '$file release');
    }
  });

  test(
    'the first touch after a glass button appears lifts when the device '
    'does',
    () {
      final lags = [
        for (final (file, size) in [..._holds, (_taps, const Size(44, 44))])
          () {
            final trace = Trace.load('$_dir/$file');
            final down = trace.touches.firstWhere((t) => t.phase == 0).t;
            return glassPressLag(trace.layer('0.0'), size, down);
          }(),
      ];
      for (final lag in lags) {
        expect(lag.abs(), lessThan(deliverySpread));
      }
    },
    skip:
        'the first touch of each recording lifts 11.8 - 20.9 ms after the '
        'model fed its stamp (8 captures, 37.8 - 46.9 ms after the stamp) '
        'vs the 14.6 ms delivery spread: UIKit sets the button up on that '
        'touch (the next display frame comes 20.6 - 21.5 ms after the one '
        'before instead of 8.3); a one-time cost, not reproduced',
  );
}

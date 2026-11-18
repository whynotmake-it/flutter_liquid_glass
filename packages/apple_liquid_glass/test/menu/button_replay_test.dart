import 'dart:convert';
import 'dart:math' as math;

import 'package:apple_liquid_glass/src/motions/menu_metrics.dart';
import 'package:apple_liquid_glass/src/motions/menu_motion.dart';
import 'package:apple_liquid_glass/src/motions/menu_tuning.dart';
import 'package:apple_liquid_glass/src/motions/menu_values.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/motion.dart';

import '../support/fixtures.dart';
import 'menu_events.dart';

const _dir = 'test/fixtures/ios27/menu';
const _device = 'test/fixtures/ios27-device/menu';
const _screen = Size(390, 844);
const _safeArea = EdgeInsets.only(top: 47, bottom: 34);
const _tuning = MenuTuning.standard;
const _metrics = MenuMetrics.standard;

// The captures record the springs ringing out to rest, past the point where the
// close hands the source back.
const _toRest = MenuTuning(sourceReturnTolerance: 0);

/// A compact menu recording: touches, actions and per-frame values, each
/// frame carrying every value last reported.
class _Capture {
  _Capture(this.name, this.touches, this.actions, this.frames);

  factory _Capture.load(String name, {String dir = _dir}) {
    final touches = <({double t, int phase, Offset at})>[];
    final actions = <({double t, String title})>[];
    final frames = <Map<String, Object?>>[];
    final state = <String, Object?>{};
    for (final line in Fixtures.lines('$dir/$name')) {
      if (line.trim().isEmpty) continue;
      final row = (jsonDecode(line) as Map).cast<String, Object?>();
      final t = (row['t']! as num).toDouble();
      switch (row['k']) {
        case 'touch':
          touches.add((
            t: t,
            phase: row['phase']! as int,
            at: Offset(
              (row['x']! as num).toDouble(),
              (row['y']! as num).toDouble(),
            ),
          ));
        case 'action':
          actions.add((t: t, title: row['title']! as String));
        case 'f':
          state.addAll(row);
          frames.add(Map.of(state));
      }
    }
    return _Capture(name, touches, actions, frames);
  }

  final String name;
  final List<({double t, int phase, Offset at})> touches;
  final List<({double t, String title})> actions;
  final List<Map<String, Object?>> frames;
}

double _d(Map<String, Object?> frame, String key) =>
    (frame[key]! as num).toDouble();

/// Seconds a spring from rest at 0 toward 1 needs to reach [value].
double _timeToReach(Spring spring, double value) {
  final w0 = spring.omega;
  final zeta = spring.dampingRatio;
  final wd = w0 * math.sqrt(1 - zeta * zeta);
  double step(double t) =>
      1 -
      math.exp(-zeta * w0 * t) *
          (math.cos(wd * t) + zeta * w0 / wd * math.sin(wd * t));
  var lo = 0.0;
  var hi = 0.25;
  for (var i = 0; i < 60; i++) {
    final mid = (lo + hi) / 2;
    if (step(mid) < value) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return lo;
}

/// The recorded geometry of one capture and the times its open and close
/// started, solved from the progress the recording shows.
class _Replay {
  _Replay(this.capture) {
    final first = capture.frames.first;
    final menu = (first['menu']! as List).cast<num>();
    height = menu[3].toDouble();
    menuCenter = Offset(menu[0].toDouble(), menu[1].toDouble());
    final navBar = capture.name.startsWith('navbar');
    buttonSize = Size(_d(first, 'S_bw'), _d(first, 'S_bh'));
    sourceHeight = navBar ? 36 : buttonSize.height;
    s0 = 0.5 * sourceHeight / math.max(_metrics.width, height);
    final p = progressOf(first);
    final sx = _d(first, 'S_px');
    final sy = _d(first, 'S_py');
    final k = _tuning.sourceTravel * p;
    buttonCenter = Offset(
      (sx - k * menuCenter.dx) / (1 - k),
      (sy - k * menuCenter.dy) / (1 - k),
    );
    sourceScale = (_d(first, 'S_s') - _tuning.sourceEndScale * p) / (1 - p);
    final starts = [
      for (final f
          in capture.frames
              .where((f) {
                final v = progressOf(f);
                return v > 0.02 && v < 0.9;
              })
              .take(5))
        _d(f, 't') - _timeToReach(_tuning.openSpring, progressOf(f)),
    ];
    starts.sort();
    openStart = starts[starts.length ~/ 2];
    final early = capture.frames.where((f) {
      final t = _d(f, 't');
      return progressOf(f) > 0.001 && t > openStart && t < openStart + 0.07;
    }).toList();
    var bestError = double.infinity;
    for (var i = 0; i < 20; i++) {
      gridOrigin = openStart + (i / 20 - 0.5) / 60;
      var error = 0.0;
      for (final f in early) {
        final t = frameTime(f);
        final open = motion();
        open.advance(t);
        error += math.pow(open.progress - progressOf(f), 2);
      }
      if (error < bestError) {
        bestError = error;
        bestOrigin = gridOrigin;
      }
    }
    gridOrigin = bestOrigin;
    closeStart = _solveClose();
  }

  final _Capture capture;
  late final double height;
  late final Offset menuCenter;
  late final Size buttonSize;
  late final double sourceHeight;
  late final double s0;
  late final Offset buttonCenter;
  late final double sourceScale;
  late final double openStart;
  double gridOrigin = 0;
  double bestOrigin = 0;
  late final double? closeStart;

  double progressOf(Map<String, Object?> frame) =>
      (_d(frame, 'G_s') - s0) / (1 - s0);

  MenuMotion motion({double? close}) {
    final motion = MenuMotion(
      source: MenuSource(
        Rect.fromCenter(
          center: buttonCenter,
          width: buttonSize.width,
          height: buttonSize.height,
        ),
        height: sourceHeight,
      ),
      itemCount: ((height - 2 * _metrics.topInset) / _metrics.rowHeight)
          .round(),
      bounds: _screen,
      padding: _safeArea,
      tuning: _toRest,
    );
    motion.advance(openStart - 0.5);
    motion.open(openStart, sourceScale: sourceScale);
    if (close != null) motion.close(close);
    return motion;
  }

  /// The frame time of [frame]: frames sit on a 60 Hz display grid whose
  /// phase is solved once per capture, while the recorder's timestamps
  /// jitter around it by up to a frame, so the grid slot near the
  /// timestamp whose modelled progress matches the recorded one is taken.
  double frameTime(Map<String, Object?> frame, {double? close}) {
    final base = ((_d(frame, 't') - gridOrigin) * 60).round();
    final observed = progressOf(frame);
    var best = gridOrigin + base / 60;
    var error = double.infinity;
    for (var k = base - 2; k <= base + 2; k++) {
      final t = gridOrigin + k / 60;
      final candidate = motion(
        close: close != null && close <= t ? close : null,
      );
      candidate.advance(t);
      final e = (candidate.progress - observed).abs();
      if (e < error - 1e-9) {
        error = e;
        best = t;
      }
    }
    return best;
  }

  double _gridTime(Map<String, Object?> frame) =>
      gridOrigin + ((_d(frame, 't') - gridOrigin) * 60).round() / 60;

  /// The close start: the first frame whose progress falls behind an
  /// uninterrupted open, and the time that makes the model match it.
  double? _solveClose() {
    final open = motion();
    Map<String, Object?>? diverged;
    var previous = openStart;
    for (final f in capture.frames) {
      if (progressOf(f) < 0.001 || _d(f, 't') < openStart) continue;
      final t = frameTime(f);
      if (t <= openStart) continue;
      open.advance(t);
      if (progressOf(f) < open.progress - 0.004) {
        diverged = f;
        break;
      }
      previous = t;
    }
    if (diverged == null) return null;
    if (open.progress > 0.998 && open.progress < 1.002) {
      final starts = [
        for (final f
            in capture.frames
                .where((f) {
                  final q = 1 - progressOf(f);
                  return _d(f, 't') >= _d(diverged!, 't') &&
                      q > 0.02 &&
                      q < 0.8;
                })
                .take(5))
          _gridTime(f) - _timeToReach(_tuning.closeSpring, 1 - progressOf(f)),
      ];
      starts.sort();
      return starts[starts.length ~/ 2];
    }
    final t = _gridTime(diverged);
    final observed = progressOf(diverged);
    var lo = previous - 1 / 60;
    var hi = t;
    for (var i = 0; i < 60; i++) {
      final mid = (lo + hi) / 2;
      final candidate = motion(close: mid);
      candidate.advance(t);
      if (candidate.progress < observed) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
}

class _Rms {
  double _sum = 0;
  int _n = 0;

  void add(double error) {
    _sum += error * error;
    _n++;
  }

  double get value => _n == 0 ? 0 : math.sqrt(_sum / _n);

  int get count => _n;
}

class _Errors {
  final center = _Rms();
  final size = _Rms();
  final radius = _Rms();
  final scale = _Rms();
  final progress = _Rms();
  final sourceCenter = _Rms();
  final sourceScale = _Rms();

  String describe() =>
      'G center ${center.value.toStringAsFixed(2)} '
      'size ${size.value.toStringAsFixed(2)} '
      'radius ${radius.value.toStringAsFixed(2)} '
      'scale ${scale.value.toStringAsFixed(4)} '
      'p ${progress.value.toStringAsFixed(4)} | '
      'S center ${sourceCenter.value.toStringAsFixed(2)} '
      'scale ${sourceScale.value.toStringAsFixed(4)} (n ${center.count})';
}

/// Replays [replay] through the motion: the open at its solved start and
/// the close at its solved start, comparing every recorded frame.
({_Errors open, _Errors close, double kickRatio}) _replay(_Replay replay) {
  final motion = replay.motion();
  final close = replay.closeStart;
  final open = _Errors();
  final closing = _Errors();
  final cut = _menuLayersLost.contains(replay.capture.name)
      ? replay.capture.touches.lastWhere((t) => t.phase == 0).t
      : double.infinity;
  var closed = false;
  var kickRatio = 1.0;
  var peak = 0.0;
  for (final f in replay.capture.frames) {
    final raw = _d(f, 't');
    if (raw >= cut) break;
    if (close != null && !closed && raw >= close) {
      motion.close(close);
      closed = true;
    }
    final t = replay.frameTime(f, close: close);
    if (t <= replay.openStart) continue;
    if (!closed && replay.progressOf(f) < 0.001) continue;
    motion.advance(t);
    if (!motion.isPresented) break;
    final e = closed ? closing : open;
    final g = motion.menuBlob;
    final s = motion.buttonBlob;
    final scale = _d(f, 'G_s');
    final kick = motion.menuKick;
    if (!closed && kick.abs() > peak) {
      peak = kick.abs();
      kickRatio = _d(f, 'G_ky').abs() / peak;
    }
    final center = Offset(_d(f, 'G_px'), _d(f, 'G_py') + _d(f, 'G_ky'));
    e.center.add((g.rect.center - center).distance);
    e.size.add(
      math.max(
        (g.rect.width - _metrics.width * scale).abs(),
        (g.rect.height - _d(f, 'G_bh') * scale).abs(),
      ),
    );
    if (_d(f, 'G_rvis') > 0) e.radius.add(g.radius - _d(f, 'G_rvis'));
    e.scale.add(g.scale - scale);
    e.progress.add(motion.progress - replay.progressOf(f));
    final sourceCenter = Offset(_d(f, 'S_px'), _d(f, 'S_py') + _d(f, 'S_ky'));
    e.sourceCenter.add((s.rect.center - sourceCenter).distance);
    e.sourceScale.add(s.scale - _d(f, 'S_s'));
  }
  return (open: open, close: closing, kickRatio: kickRatio);
}

/// Captures whose menu-shape layers stop being sampled once the close
/// starts; only their open is compared.
const _menuLayersLost = {'center-items2-dismiss.jsonl'};

/// Captures whose button shape gets no kick on the close (a bar button and
/// one inline button at the leading edge); the model always kicks it.
const _noSourceKick = {'pos-left-dismiss.jsonl', 'navbar3-dismiss.jsonl'};

/// A wide text button: the menu aligns to the pressed glass while the
/// button shape starts from a narrower frame, so the button center the
/// replay derives from that shape is a few pixels off.
const _wide = {'wide3-dismiss.jsonl'};

const _replayed = [
  'center3-tap.jsonl',
  'center3-quicktap.jsonl',
  'center3-dismiss.jsonl',
  'center3-select.jsonl',
  'center3-closemidopen.jsonl',
  'center3-retap-midopen.jsonl',
  'bottom3-dismiss.jsonl',
  'pos-tl-dismiss.jsonl',
  'pos-tr-dismiss.jsonl',
  'pos-bl-dismiss.jsonl',
  'pos-br-dismiss.jsonl',
  'pos-left-dismiss.jsonl',
  'center-items2-dismiss.jsonl',
  'center-items5-dismiss.jsonl',
  'center-items10-dismiss.jsonl',
  'tl-items1-tap.jsonl',
  'tl-items2-tap.jsonl',
  'tl-items4-tap.jsonl',
  'tl-items6-tap.jsonl',
  'tl-items8-tap.jsonl',
  'wide3-dismiss.jsonl',
  'navbar3-dismiss.jsonl',
];

List<({double rms, double delay, double progress})> _reopens(String name) {
  final capture = _Capture.load(name, dir: _device);
  final first = capture.frames.first;
  final size = _d(first, 'S_bh');
  final menu = (first['menu']! as List).cast<num>();
  final s0 = 0.5 * size / math.max(_metrics.width, menu[3]);
  final button = Rect.fromCenter(
    center: Offset(_d(first, 'S_px'), _d(first, 'S_py')),
    width: _d(first, 'S_bw'),
    height: size,
  );
  final samples = [
    for (final line in Fixtures.lines('$_device/$name'))
      if (line.contains('"G_s"'))
        if ((jsonDecode(line) as Map).cast<String, Object?>() case final row)
          (t: _d(row, 't'), p: (_d(row, 'G_s') - s0) / (1 - s0)),
  ];
  double fit(double from, double to, double Function(double t) model) {
    var sum = 0.0;
    var n = 0;
    for (final (:t, :p) in samples) {
      if (t < from || t > to) continue;
      sum += math.pow(model(t) - p, 2);
      n++;
    }
    return math.sqrt(sum / n);
  }

  double best(double lo, double hi, double Function(double at) error) {
    var at = lo;
    var least = double.infinity;
    for (var x = lo; x <= hi; x += 0.0005) {
      final e = error(x);
      if (e < least) {
        least = e;
        at = x;
      }
    }
    return at;
  }

  final touches = capture.touches;
  final out = <({double rms, double delay, double progress})>[];
  for (var i = 0; i + 3 < touches.length; i++) {
    final outside = touches[i + 1];
    final down = touches[i + 2];
    final up = touches[i + 3];
    if (touches[i].phase != 0 ||
        button.contains(touches[i].at) ||
        outside.phase != 3 ||
        down.phase != 0 ||
        down.t - outside.t > 1 ||
        !button.contains(up.at) ||
        up.phase != 3 ||
        samples.where((s) => s.t > up.t && s.t < up.t + 0.6).length < 20) {
      continue;
    }
    MotionValue<double> closing(double close) {
      final progress = MotionValue<double>(0, spring: _tuning.openSpring);
      progress.retarget(close - 5, 1, spring: _tuning.openSpring);
      progress.retarget(close, 0, spring: _tuning.closeSpring);
      return progress;
    }

    final close = best(outside.t, outside.t + 0.15, (double at) {
      final progress = closing(at);
      return fit(outside.t, up.t, progress.valueAt);
    });
    final closed = closing(close);
    double Function(double t) reopened(double at) {
      final progress = closing(close);
      progress.retarget(at, 1, spring: _tuning.openSpring);
      return (double t) => t < at ? closed.valueAt(t) : progress.valueAt(t);
    }

    final end = up.t + 0.6;
    final reopen = best(
      up.t,
      up.t + 0.1,
      (double at) => fit(close, end, reopened(at)),
    );
    out.add((
      rms: fit(close, end, reopened(reopen)),
      delay: reopen - up.t,
      progress: closed.valueAt(reopen),
    ));
  }
  return out;
}

void main() {
  test('a tap during the close re-opens the same morph on its release', () {
    var count = 0;
    for (final name in const [
      'center3-reopen2-0.jsonl',
      'center3-reopen2-50.jsonl',
      'center3-reopen2-120.jsonl',
      'center3-reopen2-200.jsonl',
      'center3-reopen2-350.jsonl',
    ]) {
      for (final e in _reopens(name)) {
        count++;
        expect(e.rms, lessThan(0.007), reason: name);
        expect(e.delay, inInclusiveRange(0.015, 0.05), reason: name);
        expect(e.progress, lessThan(0.07), reason: name);
      }
    }
    expect(count, 7);
  });

  test('a touch that starts as the close starts is swallowed', () {
    final capture = _Capture.load('center3-reopen-stroke.jsonl', dir: _device);
    final first = capture.frames.first;
    final motion = MenuMotion(
      source: MenuSource(
        Rect.fromCenter(
          center: Offset(_d(first, 'S_px'), _d(first, 'S_py')),
          width: _d(first, 'S_bw'),
          height: _d(first, 'S_bh'),
        ),
      ),
      itemCount: 3,
      bounds: const Size(402, 874),
    );
    final touches = capture.touches;
    motion.advance(touches.first.t - 0.5);
    var swallowed = 0;
    for (var i = 0; i < touches.length; i++) {
      final touch = touches[i];
      switch (touch.phase) {
        case 0:
          motion.pointerDown(touch.t, touch.at);
        case 3:
          motion.pointerUp(touch.t, touch.at);
        case _:
          motion.pointerMove(touch.t, touch.at);
      }
      if (touch.phase == 3 && i > 1 && touches[i - 1].t == touches[i - 2].t) {
        motion.advance(touch.t + 1.0);
        expect(motion.isPresented, isFalse);
        swallowed++;
      }
    }
    expect(swallowed, 2);
    expect(menuSelections(motion), isEmpty);
    expect(capture.actions, isEmpty);
  });

  test('a touch before the menu appears belongs to the menu', () {
    for (final (name, selection) in const [
      ('center3-closemidopen.jsonl', <int>[]),
      ('center3-retap-midopen.jsonl', [0]),
      ('center3-early-outside-10.jsonl', <int>[]),
      ('center3-early-outside-25.jsonl', <int>[]),
      ('center3-early-outside-50.jsonl', <int>[]),
      ('center3-early-outside-100.jsonl', <int>[]),
    ]) {
      final capture = _Capture.load(name, dir: _device);
      final replay = _Replay(capture);
      final release = capture.touches[1].t;
      expect(capture.touches[2].t, closeTo(release, 1e-3), reason: name);
      expect(capture.touches[3].t, lessThan(release + 0.11), reason: name);
      ({double rms, double peak, List<int> selected, bool presented}) run(
        double openDelay,
      ) {
        final motion = MenuMotion(
          source: MenuSource(
            Rect.fromCenter(
              center: replay.buttonCenter,
              width: replay.buttonSize.width,
              height: replay.buttonSize.height,
            ),
          ),
          itemCount: 3,
          bounds: const Size(402, 874),
          padding: _safeArea,
          tuning: MenuTuning(tapOpenDelay: openDelay),
        );
        final selected = <int>[];
        motion.advance(capture.touches.first.t - 0.5);
        var next = 0;
        var sum = 0.0;
        var peak = 0.0;
        for (final f in capture.frames) {
          final t = _d(f, 't');
          while (next < capture.touches.length &&
              capture.touches[next].t <= t) {
            final touch = capture.touches[next++];
            switch (touch.phase) {
              case 0:
                motion.pointerDown(touch.t, touch.at);
              case 3:
                motion.pointerUp(touch.t, touch.at);
              case _:
                motion.pointerMove(touch.t, touch.at);
            }
          }
          motion.advance(t);
          selected.addAll(menuSelections(motion));
          final error = motion.progress - replay.progressOf(f);
          sum += error * error;
          peak = math.max(peak, motion.progress);
        }
        motion.advance(_d(capture.frames.last, 't') + 1);
        return (
          rms: math.sqrt(sum / capture.frames.length),
          peak: peak,
          selected: selected,
          presented: motion.isPresented,
        );
      }

      var best = run(_tuning.tapOpenDelay);
      for (var ms = 50; ms <= 120; ms++) {
        final candidate = run(ms / 1000);
        if (candidate.rms < best.rms) best = candidate;
      }
      final recordedPeak = capture.frames
          .map(replay.progressOf)
          .reduce(math.max);
      expect(best.rms, lessThan(0.008), reason: name);
      expect(best.peak, closeTo(recordedPeak, 0.02), reason: name);
      expect(best.selected, selection, reason: name);
      expect(best.presented, isFalse, reason: name);
    }
  });

  test('a tap opens the glass at the mean recorded delay', () {
    final delays = <double>[];
    for (final name in _replayed) {
      if (!Fixtures.exists('$_device/$name')) continue;
      final replay = _Replay(_Capture.load(name, dir: _device));
      final up = replay.capture.touches.firstWhere((t) => t.phase == 3).t;
      delays.add(replay.openStart - up);
    }
    expect(delays, hasLength(17));
    final mean = delays.reduce((a, b) => a + b) / delays.length;
    expect(_tuning.tapOpenDelay, moreOrLessEquals(mean, epsilon: 0.001));
  });

  test('every capture replays through the motion', () {
    final failures = <String>[];
    var variants = 0;
    for (final name in _replayed) {
      final replay = _Replay(_Capture.load(name));
      final e = _replay(replay);
      final canonical = e.kickRatio > 0.95;
      if (!canonical) variants++;
      final open = e.open;
      final close = e.close;
      final label =
          '$name (kick ${e.kickRatio.toStringAsFixed(2)})\n'
          '  open  ${open.describe()}\n'
          '  close ${close.describe()}';
      final wide = _wide.contains(name);
      final midOpen = name.contains('midopen');
      final openOk =
          open.progress.value < 1e-3 &&
          open.scale.value < 1e-3 &&
          open.size.value < 0.3 &&
          open.center.value < (canonical ? 0.7 : (wide ? 4 : 3.2)) &&
          open.radius.value < (canonical ? (midOpen ? 2.5 : 0.7) : 11) &&
          open.sourceCenter.value < (wide ? 2 : 0.8) &&
          open.sourceScale.value < (wide ? 0.015 : 6e-4);
      final closeOk =
          close.center.count == 0 ||
          (close.progress.value < 2e-4 &&
              close.scale.value < 2e-4 &&
              close.size.value < 0.05 &&
              close.radius.value < 0.05 &&
              close.center.value < (midOpen ? 2.2 : 1.8) &&
              close.sourceCenter.value <
                  (_noSourceKick.contains(name) ? 4.8 : 1.8) &&
              close.sourceScale.value < (midOpen ? 0.045 : 0.006));
      if (!openOk || !closeOk) failures.add(label);
    }
    expect(failures, isEmpty);
    expect(variants, lessThan(_replayed.length ~/ 2));
  });

  test('the driven kicks follow the recorded kicks of a 146 pixel menu', () {
    MenuMotion motion() => MenuMotion(
      source: MenuSource(
        Rect.fromCenter(
          center: const Offset(195, 422),
          width: 48,
          height: 48,
        ),
      ),
      itemCount: 3,
      bounds: _screen,
      padding: _safeArea,
    );
    double rms(List<double> errors) => math.sqrt(
      errors.fold<double>(0, (sum, e) => sum + e * e) / errors.length,
    );
    final open = motion();
    open.open(0, sourceScale: 1);
    final openErrors = <double>[];
    for (var n = 1; n < _openKickOracle.length; n++) {
      open.advance(n / 60);
      openErrors.add(open.menuKick - _openKickOracle[n]);
    }
    final closing = motion();
    closing.open(0, sourceScale: 1);
    closing.advance(2);
    closing.close(2);
    const lead = 0.0045;
    final closeErrors = <double>[];
    final sourceErrors = <double>[];
    for (var n = 1; n < 40; n++) {
      closing.advance(2 + lead + n / 60);
      closeErrors.add(closing.menuKick - _closeKickOracle[n]);
      sourceErrors.add(closing.buttonKick - _closeSourceKickOracle[n]);
    }
    expect(rms(openErrors), lessThan(0.25));
    expect(rms(closeErrors), lessThan(0.5));
    expect(rms(sourceErrors), lessThan(0.35));
  });

  test('a menu opens down from the upper half and up from the lower', () {
    const size = Size(250, 146);
    final center = MenuMotion.place(
      button: Rect.fromCenter(
        center: const Offset(195, 422),
        width: 62,
        height: 62,
      ),
      size: size,
      bounds: _screen,
      padding: _safeArea,
    );
    expect(center.down, isTrue);
    expect(center.rect.top, 391);
    expect(center.rect.center.dx, 195);
    final left = MenuMotion.place(
      button: Rect.fromCenter(
        center: const Offset(40.67, 455),
        width: 56,
        height: 56,
      ),
      size: size,
      bounds: _screen,
      padding: _safeArea,
    );
    expect(left.down, isFalse);
    expect(left.rect.bottom, closeTo(483, 1e-9));
    expect(left.rect.left, closeTo(12.67, 1e-9));
    final navBar = MenuMotion.place(
      button: Rect.fromCenter(
        center: const Offset(352, 69),
        width: 50,
        height: 50,
      ),
      size: size,
      bounds: _screen,
      padding: _safeArea,
    );
    expect(navBar.rect.top, 47);
    expect(navBar.rect.right, 377);
    final tall = MenuMotion.place(
      button: Rect.fromCenter(
        center: const Offset(195, 422),
        width: 55,
        height: 55,
      ),
      size: const Size(250, 440),
      bounds: _screen,
      padding: _safeArea,
    );
    expect(tall.rect.bottom, 810);
  });

  test('a close during the open carries the velocity', () {
    final motion = MenuMotion(
      source: MenuSource(
        Rect.fromCenter(
          center: const Offset(195, 422),
          width: 48,
          height: 48,
        ),
      ),
      itemCount: 3,
      bounds: _screen,
      padding: _safeArea,
    );
    motion.open(0, sourceScale: 1);
    motion.advance(4 / 60);
    final before = motion.progress;
    motion.close(4 / 60);
    motion.advance(5 / 60);
    expect(motion.progress, greaterThan(before));
    var t = 5 / 60;
    while (motion.isPresented && t < 3) {
      t += 1 / 60;
      motion.advance(t);
    }
    expect(motion.isPresented, isFalse);
    motion.advance(t + 2);
    expect(motion.isSettled, isTrue);
  });

  test('the glyph leaves early and the content unfolds with the drop', () {
    final motion = MenuMotion(
      source: MenuSource(
        Rect.fromCenter(
          center: const Offset(195, 422),
          width: 48,
          height: 48,
        ),
      ),
      itemCount: 3,
      bounds: _screen,
      padding: _safeArea,
    );
    motion.open(0, sourceScale: 1);
    var t = 0.0;
    var lookGoneAt = double.nan;
    while (t < 1) {
      t += 1 / 120;
      motion.advance(t);
      final p = motion.progress;
      if (lookGoneAt.isNaN && motion.buttonLookOpacity == 0) lookGoneAt = p;
      expect(
        motion.buttonLookStretch,
        moreOrLessEquals(1 + 2.5 * p.clamp(0.0, 1.0), epsilon: 1e-9),
      );
      expect(
        (motion.contentRect.center - motion.menuBlob.rect.center).distance,
        lessThan(1e-9),
      );
      expect(
        motion.contentScale,
        moreOrLessEquals(
          motion.menuBlob.scale + 1.45 * motion.menuKick / 146,
          epsilon: 1e-9,
        ),
      );
      if (p > 0.2 && p < 0.9) {
        expect(
          motion.contentOpacity,
          greaterThan(p - 0.05),
          reason: 'the content is in the drop as it grows',
        );
        expect(motion.contentBlur, greaterThan(0.5));
      }
    }
    expect(lookGoneAt, inInclusiveRange(0.3, 0.42));
    expect(motion.contentOpacity, moreOrLessEquals(1, epsilon: 1e-3));
    expect(motion.contentScale, moreOrLessEquals(1, epsilon: 1e-3));
    expect(motion.contentBlur, lessThan(0.01));
    expect(
      (motion.contentRect.topLeft - motion.menuRect.topLeft).distance,
      lessThan(0.5),
    );

    motion.close(t);
    var contentGoneAt = double.nan;
    var lookBackAt = double.nan;
    while (motion.isPresented && t < 3) {
      t += 1 / 120;
      motion.advance(t);
      final p = motion.progress;
      if (contentGoneAt.isNaN && motion.contentOpacity == 0) {
        contentGoneAt = p;
      }
      if (lookBackAt.isNaN && motion.buttonLookOpacity > 0) lookBackAt = p;
    }
    expect(
      contentGoneAt,
      inInclusiveRange(0.53, 0.7),
      reason: 'the content leaves faster than it came',
    );
    expect(lookBackAt, inInclusiveRange(0.42, 0.55));
  });

  group('the menu unfolds out of the drop in every placement', () {
    const screen = Size(402, 874);
    const safe = EdgeInsets.only(top: 62, bottom: 34);
    Rect at(double x, double y) =>
        Rect.fromCenter(center: Offset(x, y), width: 48, height: 48);
    final placements = <String, (Rect, int)>{
      'center, 3 rows': (at(201, 437), 3),
      'top left, 3 rows': (at(44, 220), 3),
      'top right, 3 rows': (at(358, 220), 3),
      'bottom left, 3 rows': (at(44, 796), 3),
      'bottom right, 3 rows': (at(358, 796), 3),
      'bottom center, 10 rows': (at(201, 796), 10),
      'gallery bottom center, 10 rows': (at(201, 714), 10),
      'top center, 10 rows': (at(201, 140), 10),
      'center, 10 rows, clamped': (at(201, 437), 10),
      'center, 12 rows, clamped both ways': (at(201, 437), 12),
    };

    for (final MapEntry(key: name, value: (button, rows))
        in placements.entries) {
      test(name, () {
        final motion = MenuMotion(
          source: MenuSource(button),
          itemCount: rows,
          bounds: screen,
          padding: safe,
        );
        final menu = motion.menuRect.height;
        final tall = menu > motion.menuWidth;
        void check(String phase) {
          final shape = motion.menuBlob.rect;
          final content = motion.contentRect;
          final reason = '$name, $phase at p ${motion.progress}';
          expect(
            content.center.dx,
            moreOrLessEquals(shape.center.dx, epsilon: 1e-6),
            reason: reason,
          );
          if (tall) {
            expect(
              content.top,
              moreOrLessEquals(shape.top, epsilon: 1e-6),
              reason: '$reason: the first row rides the top edge',
            );
          } else {
            expect(
              content.center.dy,
              moreOrLessEquals(shape.center.dy, epsilon: 1e-6),
              reason: '$reason: the content is centered on the drop',
            );
          }
          final kick = motion.menuKick.abs() / menu;
          expect(
            content.width,
            lessThanOrEqualTo(
              shape.width + motion.menuWidth * 1.45 * kick + 1e-6,
            ),
            reason:
                '$reason: the content is no wider than the drop and '
                'its swell',
          );
          expect(
            content.overlaps(shape) || shape.isEmpty,
            isTrue,
            reason: reason,
          );
        }

        motion.open(0, sourceScale: 1);
        var t = 0.0;
        Offset? last;
        var lastOpacity = 0.0;
        final first = motion.menuBlob.rect;
        expect(
          button.contains(first.topLeft) && button.contains(first.bottomRight),
          isTrue,
          reason: '$name: the drop starts inside the button',
        );
        expect(
          (first.center - button.center).distance,
          lessThan(1e-6),
          reason: name,
        );
        void step(String phase, double until) {
          while (t < until) {
            t += 1 / 120;
            motion.advance(t);
            check(phase);
            final center = motion.menuBlob.rect.center;
            if (last != null) {
              expect(
                (center - last!).distance,
                lessThan(25),
                reason: '$name, $phase: the drop moves without a jump',
              );
            }
            last = center;
            expect(
              (motion.contentOpacity - lastOpacity).abs(),
              lessThan(0.12),
              reason: '$name, $phase: the content fades without a jump',
            );
            lastOpacity = motion.contentOpacity;
          }
        }

        step('open', 0.06);
        motion.close(t);
        step('close during the open', 0.12);
        motion.open(t);
        step('reopen', 1.2);
        expect(
          (motion.contentRect.topLeft - motion.menuRect.topLeft).distance,
          lessThan(0.5),
          reason: '$name: the content lands on the menu',
        );
        motion.close(t);
        step('close', 2.6);
        expect(motion.isPresented, isFalse, reason: name);
      });
    }
  });
}

// driven kicks are checked against.
const List<double> _openKickOracle = [
  0,
  1.11,
  4.662,
  10.487,
  17.443,
  24.395,
  29.595,
  31.688,
  30.984,
  28.198,
  24.157,
  19.598,
  15.085,
  10.986,
  7.501,
  4.696,
  2.551,
  0.995,
  -0.067,
  -0.737,
  -1.108,
  -1.263,
  -1.27,
  -1.183,
  -1.043,
  -0.879,
  -0.711,
  -0.553,
  -0.413,
  -0.294,
  -0.198,
  -0.121,
  -0.064,
  -0.023,
  0.005,
  0.022,
  0.032,
  0.036,
  0.035,
  0.033,
  0.029,
  0.024,
  0.02,
  0.015,
  0.011,
  0.008,
  0,
];

const List<double> _closeKickOracle = [
  0,
  11.648,
  22.774,
  29.226,
  31.342,
  30.252,
  27.071,
  22.955,
  18.676,
  14.699,
  11.257,
  8.427,
  6.19,
  4.479,
  3.202,
  2.269,
  1.598,
  1.12,
  0.782,
  0.542,
  0.371,
  0.25,
  0.158,
  0.092,
  0.043,
  0.007,
  -0.019,
  -0.037,
  -0.049,
  -0.056,
  -0.059,
  -0.059,
  -0.057,
  -0.054,
  -0.049,
  -0.044,
  -0.039,
  -0.033,
  -0.028,
  -0.024,
  -0.019,
  -0.015,
  -0.012,
  -0.009,
  -0.007,
  -0.005,
  -0.003,
  -0.002,
  -0.001,
  0,
  0,
];

const List<double> _closeSourceKickOracle = [
  0,
  -0.212,
  -0.704,
  -1.538,
  -2.741,
  -4.289,
  -6.119,
  -7.821,
  -9.011,
  -9.686,
  -9.89,
  -9.696,
  -9.193,
  -8.47,
  -7.609,
  -6.682,
  -5.744,
  -4.839,
  -3.994,
  -3.23,
  -2.555,
  -2,
  -1.479,
  -1.07,
  -0.737,
  -0.471,
  -0.265,
  -0.108,
  0.008,
  0.089,
  0.144,
  0.177,
  0.193,
  0.197,
  0.193,
  0.182,
  0.167,
  0.151,
  0.133,
  0.115,
  0.098,
  0.082,
  0.068,
  0.055,
  0.044,
  0.034,
  0.026,
  0.019,
  0.013,
  0.009,
  0.005,
  0,
];

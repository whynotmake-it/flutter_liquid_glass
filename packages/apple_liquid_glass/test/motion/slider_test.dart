import 'dart:math' as math;

import 'package:apple_liquid_glass/src/motions/glass_press.dart';
import 'package:apple_liquid_glass/src/motions/slider_motion.dart';
import 'package:apple_liquid_glass/src/motions/small_lens.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/slider_feed.dart';
import 'support/trace.dart';

const _dir = 'test/fixtures/ios27/controls';

/// The window-space center of every control recorded on the simulator.
const double _controlX = 220;

const _deviceDir = 'test/fixtures/ios27-device/controls';

/// The window-space center of every control recorded on the device.
const double _deviceControlX = 201;

double _rms(Iterable<double> errors) {
  var sum = 0.0;
  var n = 0;
  for (final e in errors) {
    sum += e * e;
    n++;
  }
  return n == 0 ? double.nan : math.sqrt(sum / n);
}

/// Feeds the touches of a trace delivered by a time into a feed, once
/// each: a touch arrives a lag after its stamp.
class _Touches {
  _Touches(this.trace, {this.lag = 0});

  final Trace trace;
  final double lag;
  int _next = 0;

  void until(double t, void Function(TraceTouch touch) feed) {
    while (_next < trace.touches.length && trace.touches[_next].t + lag <= t) {
      feed(trace.touches[_next]);
      _next++;
    }
  }
}

({
  SliderMotion motion,
  double left,
  Trace trace,
  _Touches touches,
  Map<TraceTouch, bool> waits,
})
_slider(
  String file, {
  double width = 300,
  double value = 0.3,
  bool device = false,
}) {
  final trace = Trace.load('${device ? _deviceDir : _dir}/$file');
  final motion = SliderMotion(width: width, value: value, frameRate: 60);
  motion.advance(trace.touches.first.t - 1);
  final lag = device ? deviceDeliveryLag : 0.0;
  return (
    motion: motion,
    left: (device ? _deviceControlX : _controlX) - width / 2,
    trace: trace,
    touches: _Touches(trace, lag: lag),
    waits: waitedBegins(trace, width, value, lag),
  );
}

/// The model's value at every recorded valueChanged event during the
/// drag, as errors in pixels of thumb travel.
({double drag, int n}) _sliderValues(
  String file, {
  double width = 300,
  double value = 0.3,
  bool device = false,
}) {
  final s = _slider(file, width: width, value: value, device: device);
  final feed = feedSlider(s.motion, s.left, s.waits);
  final up = s.trace.touches.lastWhere((t) => t.phase == 3).t;
  final drag = <double>[];
  for (final e in s.trace.events) {
    if (e['e'] != 'valueChanged') continue;
    final t = (e['t']! as num).toDouble();
    if (t >= up) break;
    s.touches.until(device ? t : t - 0.002, feed);
    s.motion.advance(t);
    drag.add((s.motion.value - (e['v']! as num).toDouble()) * width);
  }
  return (drag: _rms(drag), n: drag.length);
}

/// The time after a step's start at which [value] of the step is first
/// reached, found by bisection over the first [span] seconds.
double _solveStart(
  double Function(double dt) value,
  double target,
  double span,
) {
  var lo = 0.0;
  var hi = span;
  final rising = value(span) > value(0);
  for (var i = 0; i < 60; i++) {
    final mid = (lo + hi) / 2;
    if ((value(mid) < target) == rising) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  return lo;
}

/// The lens of [file] against the small lens model: lift progress and
/// size, with the lift and landing starts solved from the first moving
/// frames because the simulator delivers touches 16 to 45 ms late.
({double progress, double width, double height}) _liftReplay(String file) {
  final trace = Trace.load('$_dir/$file');
  final frames = trace.track('_UILiquidLensView');
  final lifting = frames.indexWhere((f) => f.opt('lpp')! > 0.5);
  final first = frames[lifting];
  final liftDt = _solveStart(
    (dt) {
      final lens = _lens();
      lens.lift(0);
      return lens.progress(dt);
    },
    first.opt('lpp')!,
    0.1,
  );
  final liftAt = first.t - liftDt;
  final landing = frames.indexWhere(
    (f) => f.t > liftAt + 0.5 && f.opt('lpp')! < 0.999,
  );
  final drop = frames[landing];
  final landDt = _solveStart(
    (dt) {
      final lens = _lens();
      lens.lift(-5);
      lens.unlift(0);
      lens.advance(dt);
      return lens.progress(dt);
    },
    drop.opt('lpp')!,
    0.1,
  );
  final landAt = drop.t - landDt;
  final lens = _lens();
  lens.lift(liftAt);
  var landed = false;
  final progress = <double>[];
  final width = <double>[];
  final height = <double>[];
  double? previous;
  for (final f in frames.skip(lifting)) {
    if (!landed && f.t >= landAt) {
      lens.unlift(landAt);
      landed = true;
    }
    final lpp = f.opt('lpp')!;
    final stale = lpp == previous && lpp != 0 && lpp != 1;
    previous = lpp;
    if (stale) continue;
    lens.advance(f.t);
    progress.add(lens.progress(f.t) - f.opt('lpp')!);
    final size = lens.size(f.t);
    width.add(size.width - f.bw);
    height.add(size.height - f.bh);
  }
  return (progress: _rms(progress), width: _rms(width), height: _rms(height));
}

SmallLens _lens() => SmallLens(
  restSize: SliderMotion.thumbSize,
  liftedSize: SliderMotion.liftedThumbSize,
  frameRate: 60,
);

/// The lift scale of the button in [file] against the model, with the
/// press and release starts solved from the first moving frames because
/// the simulator delivers touches 16 to 45 ms late; `releaseLag` is the
/// model's release stamp, which the model takes up
/// [GlassPress.touchDelay] later, minus the recorded one.
({double press, double release, double peak, double releaseLag}) _buttonReplay(
  String file,
  Size size,
) {
  final trace = Trace.load('$_dir/$file');
  final rows = trace.layer('0.0');
  final up = trace.touches.lastWhere((t) => t.phase == 3).t;
  final center = Offset(size.width / 2, size.height / 2);
  final moving = rows.indexWhere(
    (f) => f.t > trace.touches.first.t - 0.02 && f.sx > 1.0005,
  );
  final first = rows[moving];
  final pressDt = _solveStart(
    (dt) {
      final m = GlassPress(size: size);
      m.pointerDown(0, center);
      m.advance(dt);
      return m.scale;
    },
    first.sx,
    0.1,
  );
  final plateau = rows.lastWhere((f) => f.t < up - 0.005).sx;
  final dropping = rows.indexWhere(
    (f) => f.t > up - 0.03 && f.sx < plateau - 0.002,
  );
  final drop = rows[dropping];
  final releaseDt = _solveStart(
    (dt) {
      final m = GlassPress(size: size);
      m.pointerDown(-5, center);
      m.pointerUp(0, center);
      m.advance(dt);
      return m.scale;
    },
    drop.sx,
    0.1,
  );
  final releaseAt = drop.t - releaseDt;
  final m = GlassPress(size: size);
  m.advance(first.t - pressDt - 0.1);
  m.pointerDown(first.t - pressDt, center);
  final press = <double>[];
  final release = <double>[];
  var released = false;
  for (final f in rows.skip(moving)) {
    if (!released && f.t >= releaseAt) {
      m.pointerUp(releaseAt, center);
      released = true;
    }
    if (f.t > releaseAt + 1.2) break;
    m.advance(f.t);
    (released ? release : press).add(m.scale - f.sx);
  }
  return (
    press: _rms(press),
    release: _rms(release),
    peak: m.liftedScale - plateau,
    releaseLag: releaseAt - up,
  );
}

/// The lean of the 120 x 44 button while a finger drags 150 pixels off
/// and back, against the model fed the recorded touches.
({double lean, double stretch}) _leanReplay({bool device = false}) {
  final trace = Trace.load(
    '${device ? _deviceDir : _dir}/button-glass-120x44-drag-off-back.jsonl',
  );
  const size = Size(120, 44);
  final origin = Offset((device ? _deviceControlX : _controlX) - 60, 400 - 22);
  final m = GlassPress(size: size);
  m.advance(trace.touches.first.t - 1);
  final touches = _Touches(trace);
  final up = trace.touches.lastWhere((t) => t.phase == 3).t;
  final lean = <double>[];
  final stretch = <double>[];
  for (final f in trace.layer('0.0')) {
    if (f.t < trace.touches.first.t + 0.3 || f.t > up) continue;
    touches.until(f.t, (touch) {
      final p = Offset(touch.x, touch.y) - origin;
      switch (touch.phase) {
        case 0:
          m.pointerDown(touch.t, p);
        case 3:
          m.pointerUp(touch.t, p);
        case _:
          m.pointerMove(touch.t, p);
      }
    });
    m.advance(f.t);
    lean.add(m.lean.dx - f.tx);
    stretch.add((m.scaleX - m.scaleY) - (f.sx - f.sy));
  }
  return (lean: _rms(lean), stretch: _rms(stretch));
}

/// The track ends and height of the slider in [file] against the model.
({double left, double right, double height, int n}) _stretchReplay(
  String file, {
  double width = 300,
  double value = 0.3,
  bool device = false,
}) {
  final s = _slider(file, width: width, value: value, device: device);
  final feed = feedSlider(s.motion, s.left, s.waits);
  final left = <double>[];
  final right = <double>[];
  final height = <double>[];
  for (final f in s.trace.layer('0.0.0')) {
    if (f.t < s.trace.touches.first.t) continue;
    s.touches.until(f.t, feed);
    s.motion.advance(f.t);
    final ends = s.motion.trackEnds;
    left.add(s.left + ends.left - (f.x - f.w / 2));
    right.add(s.left + ends.right - (f.x + f.w / 2));
    height.add(s.motion.currentTrackHeight - f.h);
  }
  return (
    left: _rms(left),
    right: _rms(right),
    height: _rms(height),
    n: left.length,
  );
}

/// The thumb center of the device slider in [file] against the model
/// while the finger is down, and the finger's lead over the recorded and
/// the modelled thumb when the value first reaches an end.
({double thumb, double lead, double modelLead, int n}) _thumbReplay(
  String file, {
  required double width,
  required double value,
}) {
  final s = _slider(file, width: width, value: value, device: true);
  final up = s.trace.touches.lastWhere((t) => t.phase == 3).t;
  final atEnd = s.trace.events.where((e) {
    final v = (e['v']! as num).toDouble();
    return e['e'] == 'valueChanged' && (v == 0 || v == 1);
  }).firstOrNull;
  final endTime = (atEnd?['t'] as num?)?.toDouble() ?? double.infinity;
  final thumb = <double>[];
  var finger = s.trace.touches.first.x;
  var lead = double.nan;
  var modelLead = double.nan;
  for (final f in s.trace.layer('0.0.1')) {
    if (f.t < s.trace.touches.first.t || f.t > up) continue;
    s.touches.until(f.t, (touch) {
      finger = touch.x;
      feedSlider(s.motion, s.left, s.waits)(touch);
    });
    s.motion.advance(f.t);
    final model = s.left + s.motion.thumbCenter;
    thumb.add(model - f.x);
    if (lead.isNaN && f.t >= endTime) {
      lead = (finger - f.x).abs();
      modelLead = (finger - model).abs();
    }
  }
  return (
    thumb: _rms(thumb),
    lead: lead,
    modelLead: modelLead,
    n: thumb.length,
  );
}

/// The glide of a device slider capture after a moving release: the
/// travel since the release, recorded against modelled, as the rms
/// error in pixels of thumb travel and the error of the final value, with
/// the release speed measured by Flutter's [VelocityTracker] as the widget
/// measures it; the tracker reads the test binding's clock, so this runs
/// inside a widget test.
///
/// With [tracked] false the release speed is the motion's own: the speed
/// of the last moves however long ago, as UIKit's pan reports it.
({double glide, double end}) _glideReplay(String file, {bool tracked = true}) {
  final width = file.contains('w200') ? 200.0 : 300.0;
  final trace = Trace.load('test/fixtures/ios27-device/controls/$file');
  final left = 201 - width / 2;
  final values = [
    for (final row in trace.states)
      if (row['v'] != null)
        (t: (row['t']! as num).toDouble(), v: (row['v']! as num).toDouble()),
  ];
  final motion = SliderMotion(width: width, value: values.first.v);
  final travel = motion.travel;
  final tracker = VelocityTracker.withKind(PointerDeviceKind.touch);
  final origin = trace.touches.first.t;
  var next = 0;
  void feed(double until) {
    while (next < trace.touches.length && trace.touches[next].t <= until) {
      final touch = trace.touches[next++];
      final x = touch.x - left;
      tracker.addPosition(
        Duration(microseconds: ((touch.t - origin) * 1e6).round()),
        Offset(x, 0),
      );
      switch (touch.phase) {
        case 0:
          motion.pointerDown(touch.t, x);
        case 3:
          motion.pointerUp(
            touch.t,
            x,
            velocity: tracked ? tracker.getVelocity().pixelsPerSecond.dx : null,
          );
        case _:
          motion.pointerMove(touch.t, x);
      }
    }
  }

  motion.advance(origin - 0.5);
  final up = trace.touches.lastWhere((t) => t.phase == 3).t;
  final glide = <double>[];
  var model = motion.value;
  var recorded = values.first.v;
  for (final (:t, :v) in values) {
    if (t < origin || t > up + 0.6) continue;
    feed(t);
    motion.advance(t);
    if (t <= up) {
      model = motion.value;
      recorded = v;
    } else {
      glide.add((motion.value - model - (v - recorded)) * travel);
    }
  }
  motion.advance(up + 2);
  return (
    glide: _rms(glide),
    end: (motion.value - model - (values.last.v - recorded)) * travel,
  );
}

/// The fill end the model draws for every value within 0.04 of an end a
/// device slider in [file] showed while its track was at rest, as the
/// largest error in points (mid-track the fill presentation trails a fast
/// value by a frame, and at the ends themselves the stretch rows can lag
/// the fill's).
double _fillReplay(String file, double width) {
  final trace = Trace.load('$_deviceDir/$file');
  final motion = SliderMotion(width: width, value: 0);
  var value = 0.0;
  var worst = 0.0;
  var track = width;
  var n = 0;
  final rows = <(double, int, Object)>[
    for (final s in trace.states) ((s['t']! as num).toDouble(), 0, s),
    for (final l in trace.layers) (l.t, 1, l),
  ];
  rows.sort((a, b) => a.$1 == b.$1 ? a.$2 - b.$2 : a.$1.compareTo(b.$1));
  for (final (_, _, row) in rows) {
    if (row is Map<String, Object?>) {
      final v = row['v'] as num?;
      if (v != null) value = v.toDouble();
      continue;
    }
    final layer = row as TraceFrame;
    if (layer.raw['c'] == 'track') track = layer.w;
    if (layer.raw['c'] != 'fill' || (track - width).abs() > 0.01) continue;
    if (value == 0 || value == 1 || (value > 0.04 && value < 0.96)) continue;
    motion.setValue(0, value);
    worst = math.max(worst, (motion.fillEnd - layer.w).abs());
    n++;
  }
  expect(n, greaterThan(15), reason: file);
  return worst;
}

/// How long before its own timestamp a probe layer row was committed: the
/// presentation row of a tick shows the state of the previous frame.
const double _rowLag = 1 / 120;

/// A stepped device slider in [file] replayed into the model: the fill
/// end and thumb center errors in points and the reported stops.
({double fill, double thumb, double stops}) _ticksReplay(String file) {
  final s = _slider(file, value: 0, device: true);
  s.motion.ticks = 5;
  final feed = feedSlider(s.motion, s.left, s.waits);
  final fill = <double>[];
  final thumb = <double>[];
  var stops = 0.0;
  final rows = <(double, int, Object)>[
    for (final st in s.trace.states) ((st['t']! as num).toDouble(), 0, st),
    for (final l in s.trace.layers) (l.t, 1, l),
    for (final f in s.trace.frames) (f.t, 2, f),
  ];
  rows.sort((a, b) => a.$1 == b.$1 ? a.$2 - b.$2 : a.$1.compareTo(b.$1));
  final first = s.trace.touches.first.t;
  for (final (t, _, row) in rows) {
    if (t < first) continue;
    s.touches.until(t - _rowLag, feed);
    s.motion.advance(t - _rowLag);
    if (row is Map<String, Object?>) {
      final v = row['v'] as num?;
      if (v != null) {
        stops = math.max(stops, (s.motion.reportedValue - v).abs());
      }
      continue;
    }
    final f = row as TraceFrame;
    if (f.path == null) {
      thumb.add(s.motion.thumbCenter + s.left - f.x);
    } else if (f.raw['c'] == 'fill') {
      fill.add(s.motion.fillEnd + s.left - (f.x + f.w / 2));
    }
  }
  return (fill: _rms(fill), thumb: _rms(thumb), stops: stops);
}

void main() {
  group('replays of the native recordings', () {
    testWidgets('a released slider glides on like the device', (
      WidgetTester tester,
    ) async {
      final all = <double>[];
      for (final file in const [
        'slider-w300-glide-v150.jsonl',
        'slider-w300-glide-v250.jsonl',
        'slider-w300-glide-v400.jsonl',
        'slider-w200-glide-v150.jsonl',
        'slider-w200-glide-v250.jsonl',
        'slider-w200-glide-v400.jsonl',
      ]) {
        final e = _glideReplay(file);
        expect(e.glide, lessThan(3.5), reason: '$file glide');
        expect(e.end.abs(), lessThan(4.5), reason: '$file end');
        all.add(e.glide);
      }
      expect(_rms(all), lessThan(2.2));
      final stale = _glideReplay('slider-w300-drag-slow.jsonl', tracked: false);
      expect(stale.glide, lessThan(3), reason: 'a release after a stop');
      expect(stale.end.abs(), lessThan(3), reason: 'a release after a stop');
    });

    test('the slider thumb lifts and lands like the recorded lens', () {
      final hold = _liftReplay('slider-w300-hold800-thumb.jsonl');
      expect(hold.progress, lessThan(0.002));
      expect(hold.width, lessThan(0.25));
      expect(hold.height, lessThan(0.16));
      final drag = _liftReplay('slider-w300-drag-slow.jsonl');
      expect(drag.progress, lessThan(0.025));
      expect(drag.width, lessThan(0.35));
      expect(drag.height, lessThan(0.25));
    });

    test('glass buttons lift and land by their size', () {
      for (final (file, size) in [
        ('button-glass-44x44-hold800.jsonl', const Size(44, 44)),
        ('button-glass-60x44-hold800.jsonl', const Size(60, 44)),
        ('button-glass-120x44-hold800.jsonl', const Size(120, 44)),
        ('button-glass-200x44-hold800.jsonl', const Size(200, 44)),
        ('button-glass-300x44-hold800.jsonl', const Size(300, 44)),
        ('button-glass-200x100-hold800.jsonl', const Size(200, 100)),
        ('button-prominent-120x44-hold800.jsonl', const Size(120, 44)),
      ]) {
        final e = _buttonReplay(file, size);
        expect(e.press, lessThan(3e-4), reason: '$file press');
        expect(e.release, lessThan(3e-4), reason: '$file release');
        expect(e.peak.abs(), lessThan(1e-4), reason: '$file lifted scale');
        expect(
          (e.releaseLag + GlassPress.touchDelay).abs(),
          lessThan(0.02),
          reason: '$file release',
        );
      }
    });

    test('a glass button leans after a finger that drags off', () {
      // The flex takes up each touch GlassPress.touchDelay
      // after its stamp, as UIKit's does: the device lean halves (0.065 to
      // 0.026 pt rms) and the stretch, against the touches taken up at
      // once, grows from 0.0015 / 0.0016 to 0.0024 / 0.0026.
      final e = _leanReplay();
      expect(e.lean, lessThan(0.05));
      expect(e.stretch, lessThan(0.003));
      final d = _leanReplay(device: true);
      expect(d.lean, lessThan(0.05));
      expect(d.stretch, lessThan(0.003));
    });

    test('the fill runs out to the track ends like the device', () {
      expect(_fillReplay('slider-w300-video-dark.jsonl', 300), lessThan(0.15));
      expect(
        _fillReplay('slider-w200-end-max-fill.jsonl', 200),
        lessThan(0.15),
      );
      expect(
        _fillReplay('slider-w200-end-min-fill.jsonl', 200),
        lessThan(0.15),
      );
    });

    test('a stepped slider follows the device detent curve', () {
      final e = _ticksReplay('slider-ticks5-video-dark.jsonl');
      expect(e.stops, lessThan(1e-6));
      expect(e.fill, lessThan(1.85));
      expect(e.thumb, lessThan(1.55));
    });

    test('device stepped thumbs undo the detent curve onto touch pixels', () {
      for (final file in const [
        'slider-ticks5-video-dark.jsonl',
        'slider-ticks5-drag.jsonl',
      ]) {
        final trace = Trace.load('$_deviceDir/$file');
        const left = _deviceControlX - 150;
        const travel = 300 - 37.0;
        const half = 0.125;
        final off = <double>[];
        for (final f in trace.frames) {
          final place = f.x - ((f.raw['tx'] as num?)?.toDouble() ?? 0);
          final v = (place - left - 18.5) / travel;
          final stop = (v * 4).round().clamp(0, 4) / 4;
          final d = (v - stop) / half;
          if ((d * half * travel).abs() < 0.5 || d.abs() > 0.98) continue;
          final u = math.pow(d.abs(), 1 / SliderMotion.tickExponent);
          final px = (stop + d.sign * u * half) * 300 * 3;
          off.add((px - px.roundToDouble()).abs() / 3);
        }
        off.sort();
        expect(off.length, greaterThan(50), reason: file);
        expect(off[off.length ~/ 2], lessThan(0.01), reason: file);
      }
    });

    test('stepped slider ticks sit where the device draws them', () {
      final trace = Trace.load('$_deviceDir/slider-ticks5-video-dark.jsonl');
      final recorded = <String, double>{
        for (final l in trace.layers)
          if (l.raw['c'] == 'tick') l.path!: l.x - (_deviceControlX - 150),
      };
      final ticks = recorded.values.toList();
      ticks.sort();
      final motion = SliderMotion(width: 300, value: 0, ticks: 5);
      final model = motion.tickCenters;
      expect(model.length, ticks.length);
      for (var i = 0; i < model.length; i++) {
        expect(model[i], moreOrLessEquals(ticks[i], epsilon: 1e-6));
      }
      final y = trace.layers.firstWhere((l) => l.raw['c'] == 'tick').y;
      expect(y - 400, SliderMotion.tickOffset);
    });

    test('a slider drag maps the finger by the full track width', () {
      for (final (file, width, value, limit) in [
        ('slider-w300-drag-slow.jsonl', 300.0, 0.3, 0.2),
        ('slider-w200-drag-slow.jsonl', 200.0, 0.3, 0.2),
        ('slider-w300-glide-v150.jsonl', 300.0, 0.1, 0.3),
        ('slider-w300-glide-v250.jsonl', 300.0, 0.1, 0.5),
        ('slider-w300-glide-v400.jsonl', 300.0, 0.1, 1.7),
        ('slider-w200-glide-v150.jsonl', 200.0, 0.1, 0.05),
        ('slider-w200-glide-v250.jsonl', 200.0, 0.1, 0.05),
        ('slider-w200-glide-v400.jsonl', 200.0, 0.1, 0.05),
        ('slider-w200-end-max-slow.jsonl', 200.0, 0.5, 0.1),
        ('slider-w200-end-min-slow.jsonl', 200.0, 0.5, 0.5),
        ('slider-w200-sweep.jsonl', 200.0, 0.0, 0.55),
        ('slider-w260-sweep.jsonl', 260.0, 0.0, 0.1),
        ('slider-w200-nearend-max.jsonl', 200.0, 0.9, 0.05),
        ('slider-w200-offgrab-max.jsonl', 200.0, 0.5, 0.5),
        ('slider-w200-fast-max.jsonl', 200.0, 0.5, 0.05),
        ('slider-w200-fast-min.jsonl', 200.0, 0.5, 0.05),
        ('slider-w200-fling-max.jsonl', 200.0, 0.5, 0.05),
      ]) {
        final e = _sliderValues(file, width: width, value: value, device: true);
        expect(e.n, greaterThan(15), reason: file);
        expect(e.drag, lessThan(limit), reason: '$file drag');
      }
      for (final file in [
        'slider-w300-drag-pastend.jsonl',
        'slider-w300-drag-pastend-small.jsonl',
      ]) {
        final e = _sliderValues(file);
        expect(e.n, greaterThan(15), reason: file);
        expect(e.drag, lessThan(0.01), reason: '$file drag');
      }
    });

    test('a device slider thumb stays behind the finger at its ends', () {
      for (final (file, width, value, limit, leadTolerance) in [
        ('slider-w200-end-max-slow.jsonl', 200.0, 0.5, 0.7, 0.6),
        ('slider-w200-end-min-slow.jsonl', 200.0, 0.5, 0.5, 0.6),
        ('slider-w200-sweep.jsonl', 200.0, 0.0, 0.6, 0.6),
        ('slider-w260-sweep.jsonl', 260.0, 0.0, 0.4, 0.2),
        ('slider-w200-nearend-max.jsonl', 200.0, 0.9, 0.5, 0.6),
        ('slider-w200-atend-max.jsonl', 200.0, 1.0, 0.55, double.nan),
        ('slider-w200-offgrab-max.jsonl', 200.0, 0.5, 0.6, 1.0),
        ('slider-w200-fast-max.jsonl', 200.0, 0.5, 3.4, 6.0),
        ('slider-w200-fast-min.jsonl', 200.0, 0.5, 1.7, 3.5),
      ]) {
        final e = _thumbReplay(file, width: width, value: value);
        expect(e.n, greaterThan(70), reason: file);
        expect(e.thumb, lessThan(limit), reason: '$file thumb');
        if (!leadTolerance.isNaN) {
          expect(e.lead, greaterThan(14), reason: '$file lead');
          expect(
            (e.lead - e.modelLead).abs(),
            lessThan(leadTolerance),
            reason: '$file lead against the model',
          );
        }
        final st = _stretchReplay(
          file,
          width: width,
          value: value,
          device: true,
        );
        expect(st.n, greaterThan(70), reason: file);
        expect(st.left, lessThan(0.65), reason: '$file left end');
        expect(st.right, lessThan(0.65), reason: '$file right end');
        expect(st.height, lessThan(0.2), reason: '$file height');
      }
    });

    test('a slider dragged past an end stretches the track', () {
      for (final (file, limit) in [
        ('slider-w300-drag-pastend.jsonl', 0.25),
        ('slider-w300-drag-paststart.jsonl', 0.25),
        ('slider-w300-drag-pastend-far.jsonl', 0.75),
        ('slider-w300-drag-pastend-small.jsonl', 2.1),
      ]) {
        final e = _stretchReplay(file);
        expect(e.n, greaterThan(20), reason: file);
        expect(e.left, lessThan(limit), reason: '$file left end');
        expect(e.right, lessThan(limit), reason: '$file right end');
        expect(e.height, lessThan(limit / 2), reason: '$file height');
      }
    });
  });
}

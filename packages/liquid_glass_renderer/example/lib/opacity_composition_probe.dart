import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

const _fake = bool.fromEnvironment('PROBE_FAKE');
const _nested = bool.fromEnvironment('NEST_GLASS_CONTENTS');
const _seed = bool.fromEnvironment('SEED_GLASS_CONTENTS');
const _adaptive = bool.fromEnvironment('ADAPTIVE_GLASS_OPACITY');
const _phased = bool.fromEnvironment('PROBE_PHASED');
const _overdraw = int.fromEnvironment('PROBE_OVERDRAW');
const _independent = bool.fromEnvironment('PROBE_INDEPENDENT');
const _cycles = int.fromEnvironment('PROBE_CYCLES', defaultValue: 1);

void main() => runApp(
  const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: _Probe(),
  ),
);

class _Probe extends StatefulWidget {
  const _Probe();

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> with TickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    lowerBound: 0.05,
    value: _phased ? 1 : null,
    duration: const Duration(milliseconds: 1500),
  );
  late final AnimationController _backdrop = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );
  final _raster = <int>[];
  final _build = <int>[];
  bool _record = false;
  final _timers = <Timer>[];
  String _phase = _phased ? 'opaque' : 'fade';
  int _cycle = 1;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_timings);
    if (_phased) {
      _backdrop.repeat();
    } else {
      _animation.repeat(reverse: true);
    }
    _startMeasurement();
  }

  void _startMeasurement() {
    debugPrint('OPACITY_PHASE $_phase');
    _raster.clear();
    _build.clear();
    _timers.add(Timer(const Duration(seconds: 4), () => _record = true));
    _timers.add(Timer(const Duration(seconds: 14), _report));
  }

  void _timings(List<ui.FrameTiming> timings) {
    if (!_record) return;
    for (final frame in timings) {
      _raster.add(frame.rasterDuration.inMicroseconds);
      _build.add(frame.buildDuration.inMicroseconds);
    }
  }

  Map<String, Object> _summary(List<int> values) {
    values.sort();
    if (values.isEmpty) return {'frames': 0};
    int percentile(double p) => values[((values.length - 1) * p).round()];
    return {
      'frames': values.length,
      'mean_us': values.reduce((a, b) => a + b) / values.length,
      'p50_us': percentile(0.5),
      'p95_us': percentile(0.95),
      'p99_us': percentile(0.99),
      'max_us': values.last,
    };
  }

  void _report() {
    _record = false;
    debugPrint(
      'OPACITY_PROBE ${jsonEncode({
        'fake': _fake,
        'nested': _nested,
        'seed': _seed,
        'adaptive': _adaptive,
        'phase': _phase,
        'cycle': _cycle,
        'overdraw': _overdraw,
        'independent': _independent,
        'independent_composition': const bool.fromEnvironment('INDEPENDENT_GLASS_OPACITY'),
        'raster': _summary(_raster),
        'build': _summary(_build),
      })}',
    );
    if (_phased && _phase != 'restored') {
      if (_phase == 'opaque') {
        _phase = 'fade';
        _animation.repeat(reverse: true);
      } else {
        _phase = 'restored';
        _animation.stop();
        _animation.value = 1;
      }
      _startMeasurement();
    } else if (_phased && _cycle < _cycles) {
      _cycle++;
      _phase = 'opaque';
      _startMeasurement();
    } else {
      _animation.stop();
      _backdrop.stop();
      debugPrint('OPACITY_PHASE done');
    }
  }

  @override
  void dispose() {
    for (final timer in _timers) {
      timer.cancel();
    }
    SchedulerBinding.instance.removeTimingsCallback(_timings);
    _animation.dispose();
    _backdrop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      children: [
        if (_phased)
          Positioned.fill(
            child: CustomPaint(painter: _BackdropWork(_backdrop, _overdraw)),
          )
        else
          const Positioned.fill(child: GridPaper(color: Colors.black)),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'Opacity probe — ${_fake ? "fake" : "real"}\n'
              '${_seed
                  ? "seeded pass"
                  : _nested
                  ? "nested pass"
                  : "original composition"}\n'
              '4s warmup + 10s measurement',
            ),
          ),
        ),
        Center(
          child: _independent
              ? LiquidGlassLayer(
                  fake: _fake,
                  settings: const LiquidGlassSettings(frost: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FadeTransition(
                        opacity: _animation,
                        child: const LiquidGlass(
                          // ignore: avoid_redundant_argument_values
                          shape: LiquidRoundedRectangle(borderRadius: 32),
                          child: SizedBox(
                            width: 200,
                            height: 120,
                            child: Center(child: Text('Fading pill')),
                          ),
                        ),
                      ),
                      const SizedBox(width: 24),
                      const LiquidGlass(
                        // ignore: avoid_redundant_argument_values
                        shape: LiquidOval(),
                        child: SizedBox.square(dimension: 80),
                      ),
                    ],
                  ),
                )
              : FadeTransition(
                  opacity: _animation,
                  child: LiquidGlassLayer(
                    fake: _fake,
                    settings: const LiquidGlassSettings(frost: 8),
                    child: const LiquidGlass(
                      // ignore: avoid_redundant_argument_values
                      shape: LiquidRoundedRectangle(borderRadius: 40),
                      child: SizedBox(
                        width: 320,
                        height: 160,
                        child: Center(
                          child: Text(
                            'Frosted glass',
                            style: TextStyle(fontSize: 28, color: Colors.black),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    ),
  );
}

class _BackdropWork extends CustomPainter {
  _BackdropWork(this.animation, this.overdraw) : super(repaint: animation);
  final Animation<double> animation;
  final int overdraw;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final paint = Paint();
    canvas.drawRect(bounds, paint..color = const Color(0xFFE0E8FF));
    final dx = animation.value * 80;
    paint.color = const Color(0xFF24528A);
    for (double x = dx - 80; x < size.width; x += 80) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 24, size.height), paint);
    }
    // GPU overdraw without additional offscreen targets or geometry mattes.
    // Translucent gradients cannot be discarded as opaque occluders.
    for (var i = 0; i < overdraw; i++) {
      paint
        ..color = Colors.white
        ..shader = ui.Gradient.linear(
          Offset(dx + i % 11, 0),
          Offset(size.width, size.height),
          const [Color(0x06244888), Color(0x06984824)],
        );
      canvas.drawRect(bounds, paint);
    }
  }

  @override
  bool shouldRepaint(_BackdropWork oldDelegate) =>
      oldDelegate.overdraw != overdraw;
}

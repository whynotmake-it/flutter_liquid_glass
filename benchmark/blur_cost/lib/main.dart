import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Throwaway benchmark: cost curve of native Impeller blur
/// (BackdropFilter / ImageFilter.blur) on macOS.
///
/// Phase 1 (display): sweeps sigma x region size x region count on screen,
///   measures per-frame raster/build/span durations via FrameTiming.
/// Phase 2 (raster): serially rasterizes a blurred scene via Picture.toImage +
///   toByteData (GPU round-trip, real GPU completion) -> wall clock per render.
/// Writes JSON to BLUR_BENCH_OUT.
const _outPath = String.fromEnvironment(
  'BLUR_BENCH_OUT',
  defaultValue: 'blur_bench_results.json',
);

const _warmupFrames = 40;
const _measureFrames = 120;
const _rasterWarmup = 10;
const _rasterIters = 50;

/// Logical size of each blurred square; -1 means "fill the whole window".
const _sizes = <double>[64, 128, 256, 384, 512, 768, -1];

const _sigmas = <double>[
  0, 1, 2, 4, 6, 8, 12, 16, 24, 32, 48, 64, 80, 96, 128, 160
];

class _Config {
  const _Config(this.size, this.sigma, this.count);
  final double size;
  final double sigma;
  final int count;

  String get label =>
      'size=${size < 0 ? "full" : size.toInt()} sigma=$sigma count=$count';
}

List<_Config> _buildConfigs() {
  final configs = <_Config>[];
  for (final size in _sizes) {
    for (final sigma in _sigmas) {
      configs.add(_Config(size, sigma, 1));
    }
    configs.add(const _Config(0, 0, 0)); // baseline (no blur widget)
  }
  // Region-count scaling probe at a few sigmas.
  for (final sigma in <double>[8, 32, 96]) {
    for (final count in <int>[2, 4, 8, 16]) {
      configs.add(_Config(128, sigma, count));
    }
  }
  return configs;
}

double _median(List<double> v) {
  if (v.isEmpty) return 0;
  final s = List.of(v)..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

double _pct(List<double> v, double p) {
  if (v.isEmpty) return 0;
  final s = List.of(v)..sort();
  return s[((s.length - 1) * p).round()];
}

double _mean(List<double> v) =>
    v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;

Map<String, dynamic> _stats(List<double> v) => {
      'n': v.length,
      'median_us': _median(v),
      'mean_us': _mean(v),
      'p10_us': _pct(v, 0.1),
      'p90_us': _pct(v, 0.9),
      'min_us': v.isEmpty ? 0 : v.reduce(math.min),
      'max_us': v.isEmpty ? 0 : v.reduce(math.max),
    };

void main() {
  runApp(const BenchApp());
}

class BenchApp extends StatelessWidget {
  const BenchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(body: Bench()),
    );
  }
}

enum _Phase { display, raster, done }

class Bench extends StatefulWidget {
  const Bench({super.key});

  @override
  State<Bench> createState() => _BenchState();
}

class _BenchState extends State<Bench> with SingleTickerProviderStateMixin {
  late final AnimationController _t;
  final _configs = _buildConfigs();
  final _results = <Map<String, dynamic>>[];

  _Phase _phase = _Phase.display;
  int _configIndex = 0;
  int _collected = 0;
  final _rasterUs = <double>[];
  final _buildUs = <double>[];
  final _spanUs = <double>[];
  int _configT0 = 0;

  // Phase 2 progress display.
  String _rasterProgress = '';

  @override
  void initState() {
    super.initState();
    _t = AnimationController(vsync: this, duration: const Duration(seconds: 8))
      ..repeat();
    _configT0 = DateTime.now().millisecondsSinceEpoch;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void _onTimings(List<ui.FrameTiming> timings) {
    if (_phase != _Phase.display || _configIndex >= _configs.length) return;
    for (final t in timings) {
      _collected++;
      _rasterUs.add(t.rasterDuration.inMicroseconds.toDouble());
      _buildUs.add(t.buildDuration.inMicroseconds.toDouble());
      _spanUs.add(t.totalSpan.inMicroseconds.toDouble());
    }
    if (_collected >= _warmupFrames + _measureFrames) {
      _finishConfig();
    }
  }

  void _finishConfig() {
    final c = _configs[_configIndex];
    final raster = _rasterUs.sublist(_warmupFrames);
    final build = _buildUs.sublist(_warmupFrames);
    final span = _spanUs.sublist(_warmupFrames);
    _results.add({
      'phase': 'display',
      'size': c.size,
      'sigma': c.sigma,
      'count': c.count,
      't0_ms': _configT0,
      'raster': _stats(raster),
      'build': _stats(build),
      'span': _stats(span),
    });
    // ignore: avoid_print
    print('bench ${_configIndex + 1}/${_configs.length}: ${c.label} '
        'raster=${_median(raster).toStringAsFixed(0)}us '
        'span=${_median(span).toStringAsFixed(0)}us');
    _rasterUs.clear();
    _buildUs.clear();
    _spanUs.clear();
    _collected = 0;
    _configIndex++;
    _configT0 = DateTime.now().millisecondsSinceEpoch;
    if (_configIndex >= _configs.length) {
      _startRasterPhase();
      return;
    }
    setState(() {});
  }

  // -------------------------------------------------------------------------
  // Phase 2: serial offscreen rasterization (GPU-inclusive wall clock).
  // -------------------------------------------------------------------------

  Future<void> _startRasterPhase() async {
    setState(() {
      _phase = _Phase.raster;
      _rasterProgress = 'starting';
    });
    _t.stop(); // freeze on-screen content; keep GPU contention ~0

    final view = ui.PlatformDispatcher.instance.views.first;
    final dpr = view.devicePixelRatio;
    final physWin = view.physicalSize / dpr;

    for (final size in _sizes) {
      final logicalW = size < 0 ? physWin.width - 16 : size;
      final logicalH = size < 0 ? physWin.height - 16 : size;
      final w = (logicalW * dpr).round();
      final h = (logicalH * dpr).round();

      final scene = _recordScene(w.toDouble(), h.toDouble());

      // Baseline A: scene rasterization with no filter.
      await _measureToImage(scene, w, h, size, sigma: null);

      for (final sigma in _sigmas) {
        final blurred = _recordBlurred(scene, w.toDouble(), h.toDouble(), sigma);
        await _measureToImage(blurred, w, h, size, sigma: sigma);
        blurred.dispose();
        _setProgress('size=$size sigma=$sigma');
      }
      scene.dispose();
    }

    _phase = _Phase.done;
    await _writeResults();
  }

  void _setProgress(String s) {
    _rasterProgress = s;
    // ignore: avoid_print
    print('raster-phase: $s');
    if (mounted) setState(() {});
  }

  /// Records [pic] rasterized [w]x[h], serially, [iters] times and appends a
  /// result row. `sigma == null` means "no image filter" baseline.
  Future<void> _measureToImage(
    ui.Picture pic,
    int w,
    int h,
    double size, {
    required double? sigma,
  }) async {
    final times = <double>[];
    for (var i = 0; i < _rasterWarmup + _rasterIters; i++) {
      final sw = Stopwatch()..start();
      final img = await pic.toImage(w, h);
      final bytes = await img.toByteData(); // forces GPU->CPU sync
      sw.stop();
      img.dispose();
      if (bytes == null) {
        // ignore: avoid_print
        print('toByteData null at size=$size sigma=$sigma');
      }
      if (i >= _rasterWarmup) times.add(sw.elapsedMicroseconds.toDouble());
    }
    _results.add({
      'phase': 'raster',
      'size': size,
      'sigma': sigma,
      'count': sigma == null ? 0 : 1,
      'w_px': w,
      'h_px': h,
      't0_ms': DateTime.now().millisecondsSinceEpoch,
      'serial': _stats(times),
    });
    // ignore: avoid_print
    print('raster size=$size sigma=$sigma -> ${_median(times).toStringAsFixed(0)}us');
  }

  ui.Picture _recordBlurred(ui.Picture scene, double w, double h, double sigma) {
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    canvas.saveLayer(
      Rect.fromLTWH(0, 0, w, h),
      ui.Paint()
        ..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
    );
    canvas.drawPicture(scene);
    canvas.restore();
    return rec.endRecording();
  }

  ui.Picture _recordScene(double w, double h) {
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    const _BackdropPainter(0.37).paint(canvas, Size(w, h));
    return rec.endRecording();
  }

  Future<void> _writeResults() async {
    final view = ui.PlatformDispatcher.instance.views.first;
    final dpr = view.devicePixelRatio;
    final phys = view.physicalSize;
    final out = {
      'meta': {
        'dpr': dpr,
        'physical_size': [phys.width, phys.height],
        'warmup_frames': _warmupFrames,
        'measure_frames': _measureFrames,
        'raster_warmup': _rasterWarmup,
        'raster_iters': _rasterIters,
        'flutter': '3.47.1 (.fvmrc)',
        'timestamp': DateTime.now().toIso8601String(),
      },
      'results': _results,
    };
    await File(_outPath)
        .writeAsString(const JsonEncoder.withIndent('  ').convert(out));
    // ignore: avoid_print
    print('BENCH DONE -> $_outPath');
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayDone = _configIndex >= _configs.length;
    final c = displayDone ? const _Config(0, 0, 0) : _configs[_configIndex];
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_phase == _Phase.display) AnimatedBackdrop(t: _t),
        if (_phase == _Phase.display && !displayDone && c.count > 0)
          Align(
            alignment: Alignment.topLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < c.count; i++) _BlurBox(config: c),
              ],
            ),
          ),
        Positioned(
          left: 8,
          bottom: 8,
          child: Container(
            color: Colors.black54,
            padding: const EdgeInsets.all(4),
            child: Text(
              switch (_phase) {
                _Phase.display =>
                  'display ${_configIndex + 1}/${_configs.length}  ${c.label}',
                _Phase.raster => 'raster phase: $_rasterProgress',
                _Phase.done => 'done - writing results',
              },
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
        ),
      ],
    );
  }
}

class _BlurBox extends StatelessWidget {
  const _BlurBox({required this.config});
  final _Config config;

  @override
  Widget build(BuildContext context) {
    final filtered = ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: config.sigma, sigmaY: config.sigma),
        child: Container(
          color: Colors.white.withValues(alpha: 0.06),
          alignment: Alignment.center,
          child: Text(
            's=${config.sigma.toInt()}',
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
        ),
      ),
    );
    if (config.size < 0) {
      return SizedBox(
        width: MediaQuery.sizeOf(context).width - 16,
        height: MediaQuery.sizeOf(context).height - 16,
        child: filtered,
      );
    }
    return SizedBox(width: config.size, height: config.size, child: filtered);
  }
}

/// Busy animated backdrop: moving saturated blobs + fine checker detail so
/// every frame re-rasterizes and the blur samples realistic content.
class AnimatedBackdrop extends StatelessWidget {
  const AnimatedBackdrop({required this.t});
  final AnimationController t;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: t,
      builder: (context, _) => CustomPaint(
        painter: _BackdropPainter(t.value),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  const _BackdropPainter(this.t);
  final double t;

  static const _colors = [
    Color(0xFFE91E63),
    Color(0xFF3F51B5),
    Color(0xFF009688),
    Color(0xFFFFC107),
    Color(0xFF9C27B0),
    Color(0xFFFF5722),
    Color(0xFF03A9F4),
    Color(0xFF8BC34A),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF202124));
    // High-frequency detail.
    const cell = 12.0;
    final checker = Paint()..color = const Color(0x22FFFFFF);
    for (var y = 0.0; y < size.height; y += cell * 2) {
      for (var x = 0.0; x < size.width; x += cell * 2) {
        canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), checker);
      }
    }
    // Moving blobs.
    for (var i = 0; i < 10; i++) {
      final phase = t * 2 * math.pi + i * 0.83;
      final cx = size.width * (0.5 + 0.42 * math.sin(phase * (0.7 + i * 0.07)));
      final cy = size.height * (0.5 + 0.42 * math.cos(phase * (0.9 + i * 0.05)));
      final r = 60.0 + 40 * math.sin(phase * 1.3 + i);
      canvas.drawCircle(
        Offset(cx, cy),
        r.abs(),
        Paint()..color = _colors[i % _colors.length].withValues(alpha: 0.75),
      );
    }
    // Text-like stripes for structure.
    final stripe = Paint()..color = const Color(0x33FFFFFF);
    for (var y = 40.0; y < size.height; y += 90) {
      canvas.drawRect(Rect.fromLTWH(30, y, size.width * 0.6, 14), stripe);
    }
  }

  @override
  bool shouldRepaint(_BackdropPainter old) => old.t != t;
}

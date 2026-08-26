import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

const _defaultScenarioName = String.fromEnvironment(
  'LIQUID_GLASS_BENCHMARK_SCENARIO',
  defaultValue: 'staticSingle',
);
const _defaultWarmupSeconds = int.fromEnvironment(
  'LIQUID_GLASS_BENCHMARK_WARMUP_SECONDS',
  defaultValue: 3,
);
const _defaultMeasureSeconds = int.fromEnvironment(
  'LIQUID_GLASS_BENCHMARK_MEASURE_SECONDS',
  defaultValue: 8,
);
const _native = MethodChannel('dev.liquid_glass_renderer/benchmark');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final nativeConfiguration =
      await _native.invokeMapMethod<String, Object?>('configuration') ??
      const <String, Object?>{};
  final scenario = BenchmarkScenario.values.byName(
    nativeConfiguration['scenario'] as String? ?? _defaultScenarioName,
  );
  final warmupSeconds =
      nativeConfiguration['warmupSeconds'] as int? ?? _defaultWarmupSeconds;
  final measureSeconds =
      nativeConfiguration['measureSeconds'] as int? ?? _defaultMeasureSeconds;
  final traceMeasureMilliseconds =
      nativeConfiguration['traceMeasureMilliseconds'] as int? ?? 500;
  final repetition = nativeConfiguration['repetition'] as int? ?? 1;
  final isTraceRun = nativeConfiguration['traceRun'] as bool? ?? false;
  final traceStartGate = nativeConfiguration['traceStartGate'] as String?;
  final timings = <FrameTiming>[];
  void collectTimings(List<FrameTiming> values) => timings.addAll(values);

  runApp(
    _BenchmarkApp(
      scenario: scenario,
      traceStartGate: isTraceRun ? traceStartGate : null,
    ),
  );
  await SchedulerBinding.instance.endOfFrame;
  await Future<void>.delayed(Duration(seconds: warmupSeconds));

  if (isTraceRun) {
    if (traceStartGate != null && traceStartGate.isNotEmpty) {
      debugPrint('LIQUID_GLASS_BENCHMARK_TRACE_READY:${scenario.name}');
      while (!File(traceStartGate).existsSync()) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }
    // Xcode 26 can retain less than a second from a bounded rolling Metal
    // trace. Emit adjacent half-second windows so every retained timeline has
    // a sufficiently large exact workload intersection. Each window also
    // reports its rendered frame count: ProMotion varies the refresh rate
    // under tracing, so GPU cost is only comparable across runs when
    // normalized per frame.
    var windowFrameCount = 0;
    void countWindowFrames(List<FrameTiming> values) =>
        windowFrameCount += values.length;

    SchedulerBinding.instance.addTimingsCallback(countWindowFrames);
    while (true) {
      await _startGpuTiming();
      await _native.invokeMethod<void>('beginInterval', scenario.name);
      windowFrameCount = 0;
      stdout.writeln(
        'LIQUID_GLASS_BENCHMARK_MEASURE_BEGIN:${scenario.name}:'
        '${DateTime.now().microsecondsSinceEpoch}',
      );
      await Future<void>.delayed(
        Duration(milliseconds: traceMeasureMilliseconds),
      );
      await SchedulerBinding.instance.endOfFrame;
      await _native.invokeMethod<void>('endInterval', scenario.name);
      final windowGpu = await _stopGpuTiming();
      // The optional trailing field carries the in-process GPU busy time in
      // microseconds; the window regex in the parser tolerates its absence.
      final gpuBusyMillis = windowGpu['busyMilliseconds'];
      final gpuSuffix = windowGpu['available'] == true && gpuBusyMillis is num
          ? ':${(gpuBusyMillis * 1000).round()}'
          : '';
      stdout.writeln(
        'LIQUID_GLASS_BENCHMARK_MEASURE_END:${scenario.name}:'
        '${DateTime.now().microsecondsSinceEpoch}:$windowFrameCount$gpuSuffix',
      );
      await stdout.flush();
    }
  }

  final preMeasureStability = await _sampleUntilStable();
  final preMeasureMemory = _representativeMemory(
    preMeasureStability.samples,
  );
  await _native.invokeMethod<void>('startMemorySampling');

  SchedulerBinding.instance.addTimingsCallback(collectTimings);
  await _startGpuTiming();
  await _native.invokeMethod<void>('beginInterval', scenario.name);
  debugPrint('LIQUID_GLASS_BENCHMARK_MEASURE_BEGIN:${scenario.name}');
  await Future<void>.delayed(Duration(seconds: measureSeconds));
  await _native.invokeMethod<void>('endInterval', scenario.name);
  final commandBufferGpu = await _stopGpuTiming();
  debugPrint('LIQUID_GLASS_BENCHMARK_MEASURE_END:${scenario.name}');
  SchedulerBinding.instance.removeTimingsCallback(collectTimings);

  final memory = await _stopMemorySampling();
  final cooldownStability = await _sampleUntilStable();
  final cooldownMemory = cooldownStability.samples;
  final settledMemory = _representativeMemory(cooldownMemory);
  final report = <String, Object?>{
    'schemaVersion': 5,
    'scenario': scenario.name,
    'repetition': repetition,
    'warmupSeconds': warmupSeconds,
    'measureSeconds': measureSeconds,
    'commandBufferGpu': commandBufferGpu,
    'frames': timings
        .map(
          (timing) => <String, int>{
            'buildMicros': timing.buildDuration.inMicroseconds,
            'rasterMicros': timing.rasterDuration.inMicroseconds,
            'totalMicros': timing.totalSpan.inMicroseconds,
          },
        )
        .toList(),
    'nativeMemory': memory,
    'preMeasureNativeMemory': preMeasureMemory,
    'preMeasureNativeMemorySamples': preMeasureStability.samples,
    'preMeasureMemoryStable': preMeasureStability.stable,
    'preMeasureMemorySlopeMbPerSecond': preMeasureStability.slopeMbPerSecond,
    'settledNativeMemory': settledMemory,
    'cooldownNativeMemory': cooldownMemory,
    'cooldownMemoryStable': cooldownStability.stable,
    'cooldownMemorySlopeMbPerSecond': cooldownStability.slopeMbPerSecond,
  };
  debugPrint('LIQUID_GLASS_BENCHMARK_JSON:${jsonEncode(report)}');
}

/// Starts the native in-process GPU timing session (Metal command-buffer
/// completion timestamps). Failures degrade to an unavailable marker so the
/// benchmark never depends on the channel existing.
Future<Map<String, Object?>> _startGpuTiming() => _invokeGpuTiming(
  'startGpuTiming',
);

/// Stops the session and returns the native stats map: `busyMilliseconds`
/// (union of command-buffer GPU intervals), `windowMilliseconds`,
/// `bufferCount`, and a 100 ms `bucketBusyMilliseconds` series — or
/// `available: false` with a reason.
Future<Map<String, Object?>> _stopGpuTiming() => _invokeGpuTiming(
  'stopGpuTiming',
);

Future<Map<String, Object?>> _invokeGpuTiming(String method) async {
  try {
    final response = await _native.invokeMapMethod<String, Object?>(method);
    return response ??
        <String, Object?>{'available': false, 'reason': 'no native response'};
  } on PlatformException catch (error) {
    return <String, Object?>{'available': false, 'reason': '$error'};
  } on MissingPluginException catch (error) {
    return <String, Object?>{'available': false, 'reason': '$error'};
  }
}

typedef _MemoryStability = ({
  List<Map<String, Object?>> samples,
  bool stable,
  double slopeMbPerSecond,
});

Future<_MemoryStability> _sampleUntilStable() async {
  final samples = <Map<String, Object?>>[];
  var slope = double.infinity;
  for (var attempt = 0; attempt < 3; attempt++) {
    await _native.invokeMethod<void>('startMemorySampling');
    await Future<void>.delayed(const Duration(seconds: 5));
    samples.addAll(await _stopMemorySampling());
    slope = _memorySlope(samples);
    final tail = samples.length <= 20
        ? samples
        : samples.sublist(samples.length - 20);
    final footprints = tail
        .map((sample) => sample['physicalFootprintBytes'])
        .whereType<num>()
        .map((bytes) => bytes / 1048576)
        .toList();
    final range = footprints.isEmpty
        ? double.infinity
        : footprints.reduce(math.max) - footprints.reduce(math.min);
    if (slope.abs() <= 2 && range <= 16) {
      return (samples: samples, stable: true, slopeMbPerSecond: slope);
    }
  }
  return (samples: samples, stable: false, slopeMbPerSecond: slope);
}

double _memorySlope(List<Map<String, Object?>> samples) {
  final valid = samples
      .where(
        (sample) =>
            sample['physicalFootprintBytes'] is num &&
            sample['timestampMicros'] is num,
      )
      .toList();
  if (valid.length < 10) return double.infinity;
  final tail = valid.length <= 20 ? valid : valid.sublist(valid.length - 20);
  final window = math.min(5, tail.length ~/ 2);
  double median(List<double> values) {
    values.sort();
    final middle = values.length ~/ 2;
    return values.length.isOdd
        ? values[middle]
        : (values[middle - 1] + values[middle]) / 2;
  }

  final first = tail.take(window).toList();
  final last = tail.skip(tail.length - window).toList();
  final firstMb = median(
    first
        .map((sample) => (sample['physicalFootprintBytes'] as num) / 1048576)
        .toList(),
  );
  final lastMb = median(
    last
        .map((sample) => (sample['physicalFootprintBytes'] as num) / 1048576)
        .toList(),
  );
  final firstSeconds = median(
    first
        .map((sample) => (sample['timestampMicros'] as num) / 1000000)
        .toList(),
  );
  final lastSeconds = median(
    last.map((sample) => (sample['timestampMicros'] as num) / 1000000).toList(),
  );
  return lastSeconds == firstSeconds
      ? double.infinity
      : (lastMb - firstMb) / (lastSeconds - firstSeconds);
}

Map<String, Object?>? _representativeMemory(
  List<Map<String, Object?>> samples,
) {
  if (samples.isEmpty) return null;
  final tail = samples.length <= 10
      ? samples
      : samples.sublist(samples.length - 10);
  final result = <String, Object?>{};
  for (final key in tail.expand((sample) => sample.keys).toSet()) {
    final values = tail.map((sample) => sample[key]).whereType<num>().toList()
      ..sort((a, b) => a.compareTo(b));
    if (values.isEmpty) continue;
    final middle = values.length ~/ 2;
    result[key] = values.length.isOdd
        ? values[middle]
        : ((values[middle - 1] + values[middle]) / 2).round();
  }
  return result;
}

Future<List<Map<String, Object?>>> _stopMemorySampling() async {
  final values = await _native.invokeListMethod<Object?>('stopMemorySampling');
  return values
          ?.whereType<Map<Object?, Object?>>()
          .map(
            (value) => value.map(
              (key, item) => MapEntry(key as String, item),
            ),
          )
          .toList() ??
      const <Map<String, Object?>>[];
}

enum BenchmarkScenario {
  baselineMotion,
  staticSingle,
  translatedSingle,
  ancestorTranslatedLayer,
  scaledRotatedSingle,
  grouped4Motion,
  grouped8Motion,
  grouped16Motion,
  independent4Motion,
  independent8Motion,
  independent16Motion,
  independent16SharedBackdrop,
  sparse16Motion,
  relativeBlendMotion,
  dynamicBlend16,
  resizeAnimated,
  layerChurn,
  largeStatic,
  largeResize,
  fakeStatic,
  fakeLarge,
}

class _BenchmarkApp extends StatefulWidget {
  const _BenchmarkApp({required this.scenario, this.traceStartGate});
  final BenchmarkScenario scenario;
  final String? traceStartGate;

  @override
  State<_BenchmarkApp> createState() => _BenchmarkAppState();
}

class _BenchmarkAppState extends State<_BenchmarkApp>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;
  bool traceGateOpen = false;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    if (widget.traceStartGate == null || widget.traceStartGate!.isEmpty) {
      traceGateOpen = true;
      controller.repeat(reverse: true);
    } else {
      unawaited(_waitForTraceGate());
    }
  }

  Future<void> _waitForTraceGate() async {
    final gate = File(widget.traceStartGate!);
    while (mounted && !gate.existsSync()) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    if (!mounted) return;
    setState(() => traceGateOpen = true);
    controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scenario = widget.scenario;
    // Keep the expensive benchmark scene out of the render loop while
    // Instruments attaches. The shell supplies this gate only for trace runs;
    // normal frame/memory measurements and production code are unchanged.
    final scenarioWidget = !traceGateOpen
        ? const SizedBox.expand()
        : _isAnimated(scenario)
        ? AnimatedBuilder(
            animation: controller,
            builder: (_, __) => _buildScenario(controller.value),
          )
        : _buildScenario(0);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            const _Background(),
            scenarioWidget,
            // Keep static scenarios on real engine vsync without rebuilding
            // their glass subtree.
            Positioned(
              left: 0,
              top: 0,
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: controller,
                  builder: (_, __) => Transform.translate(
                    offset: Offset(controller.value, 0),
                    child: const SizedBox.square(dimension: 1),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _isAnimated(BenchmarkScenario scenario) => switch (scenario) {
    BenchmarkScenario.staticSingle ||
    BenchmarkScenario.largeStatic ||
    BenchmarkScenario.fakeStatic ||
    BenchmarkScenario.fakeLarge => false,
    _ => true,
  };

  Widget _buildScenario(double t) {
    final settings = const LiquidGlassSettings(thickness: 30, frost: 15);
    final moving = Transform.translate(
      offset: Offset(-180 + 360 * t, 40 * math.sin(t * math.pi * 2)),
      child: _tile(0),
    );

    return switch (widget.scenario) {
      BenchmarkScenario.baselineMotion => Center(child: moving),
      BenchmarkScenario.staticSingle => Center(
        child: LiquidGlass.withOwnLayer(
          settings: settings,
          shape: const LiquidRoundedSuperellipse(borderRadius: 32),
          child: _tile(0),
        ),
      ),
      BenchmarkScenario.translatedSingle => LiquidGlassLayer(
        settings: settings,
        child: Center(
          child: Transform.translate(
            offset: Offset(-180 + 360 * t, 0),
            child: LiquidGlass(
              shape: const LiquidRoundedSuperellipse(borderRadius: 32),
              child: _tile(0),
            ),
          ),
        ),
      ),
      BenchmarkScenario.ancestorTranslatedLayer => Transform.translate(
        offset: Offset(-180 + 360 * t, 0),
        child: LiquidGlassLayer(
          settings: settings,
          child: Center(
            child: LiquidGlass(
              shape: const LiquidRoundedSuperellipse(borderRadius: 32),
              child: _tile(0),
            ),
          ),
        ),
      ),
      BenchmarkScenario.scaledRotatedSingle => LiquidGlassLayer(
        settings: settings,
        child: Center(
          child: Transform.rotate(
            angle: t * math.pi * .5,
            child: Transform.scale(
              scaleX: .7 + t * .6,
              scaleY: 1.3 - t * .6,
              child: LiquidGlass(
                shape: const LiquidRoundedRectangle(borderRadius: 32),
                child: _tile(0),
              ),
            ),
          ),
        ),
      ),
      BenchmarkScenario.grouped4Motion => _groupedGrid(
        settings: settings,
        count: 4,
        t: t,
      ),
      BenchmarkScenario.grouped8Motion => _groupedGrid(
        settings: settings,
        count: 8,
        t: t,
      ),
      BenchmarkScenario.grouped16Motion => _groupedGrid(
        settings: settings,
        count: 16,
        t: t,
      ),
      BenchmarkScenario.independent4Motion => _independentGrid(
        settings: settings,
        count: 4,
        t: t,
      ),
      BenchmarkScenario.independent8Motion => _independentGrid(
        settings: settings,
        count: 8,
        t: t,
      ),
      BenchmarkScenario.independent16Motion => _independentGrid(
        settings: settings,
        count: 16,
        t: t,
      ),
      BenchmarkScenario.independent16SharedBackdrop => BackdropGroup(
        child: Center(
          child: Transform.translate(
            offset: Offset(30 * math.sin(t * math.pi * 2), 0),
            child: Wrap(
              alignment: WrapAlignment.center,
              children: List.generate(
                16,
                (index) => LiquidGlass.withOwnLayer(
                  settings: settings,
                  useBackdropGroup: true,
                  shape: LiquidRoundedSuperellipse(
                    borderRadius: 8.0 + index,
                  ),
                  child: _tile(index, size: 72),
                ),
              ),
            ),
          ),
        ),
      ),
      BenchmarkScenario.sparse16Motion => _sparseGroup(
        settings: settings,
        t: t,
      ),
      BenchmarkScenario.relativeBlendMotion => _relativeBlendGroup(
        settings: settings,
        t: t,
      ),
      BenchmarkScenario.dynamicBlend16 => _groupedGrid(
        settings: settings,
        count: 16,
        t: t,
        blend: 2 + 30 * t,
      ),
      BenchmarkScenario.resizeAnimated => _resizeLayer(
        settings: settings,
        size: 120 + t * 360,
      ),
      BenchmarkScenario.layerChurn => Center(
        child: (t * 20).floor().isEven
            ? LiquidGlass.withOwnLayer(
                key: ValueKey((t * 20).floor()),
                settings: settings,
                shape: const LiquidOval(),
                child: _tile(0, size: 260),
              )
            : _tile(0, size: 260),
      ),
      BenchmarkScenario.largeStatic => _largeLayer(
        settings: settings,
        size: 2048,
      ),
      BenchmarkScenario.largeResize => _largeLayer(
        settings: settings,
        size: 1024 + t * 1024,
      ),
      BenchmarkScenario.fakeStatic => LiquidGlassLayer(
        settings: settings,
        fake: true,
        child: Center(
          child: LiquidGlass(
            shape: const LiquidRoundedSuperellipse(borderRadius: 32),
            child: _tile(0),
          ),
        ),
      ),
      BenchmarkScenario.fakeLarge => _largeLayer(
        settings: settings,
        size: 2048,
        fake: true,
      ),
    };
  }

  Widget _largeLayer({
    required LiquidGlassSettings settings,
    required double size,
    bool fake = false,
  }) => LiquidGlassLayer(
    settings: settings,
    fake: fake,
    child: Center(
      child: OverflowBox(
        maxWidth: double.infinity,
        maxHeight: double.infinity,
        child: LiquidGlass(
          shape: const LiquidRoundedSuperellipse(borderRadius: 96),
          child: _tile(0, size: size),
        ),
      ),
    ),
  );

  // Constant per-layer tile size across the count ladder so the scenarios
  // isolate the cost of each additional independent layer.
  Widget _independentGrid({
    required LiquidGlassSettings settings,
    required int count,
    required double t,
  }) => Center(
    child: Transform.translate(
      offset: Offset(30 * math.sin(t * math.pi * 2), 0),
      child: Wrap(
        alignment: WrapAlignment.center,
        children: List.generate(
          count,
          (index) => LiquidGlass.withOwnLayer(
            settings: settings,
            shape: LiquidRoundedSuperellipse(
              borderRadius: 8.0 + index,
            ),
            child: _tile(index, size: 72),
          ),
        ),
      ),
    ),
  );

  Widget _groupedGrid({
    required LiquidGlassSettings settings,
    required int count,
    required double t,
    double blend = 24,
  }) {
    // Keep total glass area approximately constant across the count ladder.
    final tileSize = 72 * math.sqrt(16 / count);
    return LiquidGlassLayer(
      settings: settings,
      child: Center(
        child: Transform.translate(
          offset: Offset(30 * math.sin(t * math.pi * 2), 0),
          child: LiquidGlassBlendGroup(
            blend: blend,
            child: Wrap(
              alignment: WrapAlignment.center,
              children: List.generate(
                count,
                (index) => LiquidGlass.grouped(
                  shape: LiquidRoundedSuperellipse(
                    borderRadius: 8.0 + index,
                  ),
                  child: _tile(index, size: tileSize),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sparseGroup({
    required LiquidGlassSettings settings,
    required double t,
  }) => LiquidGlassLayer(
    settings: settings,
    child: Center(
      child: SizedBox(
        width: 720,
        height: 480,
        child: LiquidGlassBlendGroup(
          blend: 24,
          child: Stack(
            children: List.generate(16, (index) {
              final column = index % 4;
              final row = index ~/ 4;
              return Positioned(
                left: column * 210 + 8 * math.sin(t * math.pi * 2 + index),
                top: row * 135 + 8 * math.cos(t * math.pi * 2 + index),
                child: LiquidGlass.grouped(
                  shape: LiquidRoundedSuperellipse(
                    borderRadius: 8.0 + index,
                  ),
                  child: _tile(index, size: 72),
                ),
              );
            }),
          ),
        ),
      ),
    ),
  );

  Widget _relativeBlendGroup({
    required LiquidGlassSettings settings,
    required double t,
  }) => LiquidGlassLayer(
    settings: settings,
    child: Center(
      child: SizedBox(
        width: 560,
        height: 300,
        child: LiquidGlassBlendGroup(
          blend: 32,
          child: Stack(
            children: [
              Positioned(
                left: 40 + 260 * t,
                top: 45,
                child: LiquidGlass.grouped(
                  shape: const LiquidRoundedSuperellipse(borderRadius: 36),
                  child: SizedBox(
                    width: 100 + 180 * t,
                    height: 120,
                    child: _tile(0),
                  ),
                ),
              ),
              Positioned(
                right: 40 + 180 * t,
                bottom: 45,
                child: LiquidGlass.grouped(
                  shape: const LiquidOval(),
                  child: _tile(1, size: 140),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _resizeLayer({
    required LiquidGlassSettings settings,
    required double size,
  }) => Center(
    child: LiquidGlass.withOwnLayer(
      settings: settings,
      shape: const LiquidRoundedSuperellipse(borderRadius: 32),
      child: _tile(0, size: size),
    ),
  );

  Widget _tile(int index, {double size = 220}) => SizedBox.square(
    dimension: size,
    child: ColoredBox(
      color: Colors.primaries[index % Colors.primaries.length].withValues(
        alpha: .35,
      ),
      child: Center(child: Text('glass $index')),
    ),
  );
}

class _Background extends StatelessWidget {
  const _Background();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0xff182848), Color(0xff4b6cb7)],
      ),
    ),
    child: GridPaper(
      color: Colors.white.withValues(alpha: .25),
      interval: 48,
      child: const SizedBox.expand(),
    ),
  );
}

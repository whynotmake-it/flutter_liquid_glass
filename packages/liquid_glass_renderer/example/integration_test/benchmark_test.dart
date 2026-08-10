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
  final repetition = nativeConfiguration['repetition'] as int? ?? 1;
  final isTraceRun = nativeConfiguration['traceRun'] as bool? ?? false;
  final traceStartGate = nativeConfiguration['traceStartGate'] as String?;
  final timings = <FrameTiming>[];
  void collectTimings(List<FrameTiming> values) => timings.addAll(values);

  runApp(_BenchmarkApp(scenario: scenario));
  await SchedulerBinding.instance.endOfFrame;
  await Future<void>.delayed(Duration(seconds: warmupSeconds));

  if (isTraceRun) {
    if (traceStartGate != null && traceStartGate.isNotEmpty) {
      debugPrint('LIQUID_GLASS_BENCHMARK_TRACE_READY:${scenario.name}');
      while (!File(traceStartGate).existsSync()) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }
    // Game Performance initializes some Metal streams lazily. Emit repeated,
    // exact intervals for the bounded trace lifetime; the parser accepts only
    // a full-duration interval with overlapping target-process GPU work.
    while (true) {
      await _native.invokeMethod<void>('beginInterval', scenario.name);
      debugPrint('LIQUID_GLASS_BENCHMARK_MEASURE_BEGIN:${scenario.name}');
      await Future<void>.delayed(Duration(seconds: measureSeconds));
      await _native.invokeMethod<void>('endInterval', scenario.name);
      debugPrint('LIQUID_GLASS_BENCHMARK_MEASURE_END:${scenario.name}');
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  final preMeasureMemory = await _native.invokeMapMethod<String, Object?>(
    'sampleMemory',
  );
  await _native.invokeMethod<void>('startMemorySampling');

  SchedulerBinding.instance.addTimingsCallback(collectTimings);
  await _native.invokeMethod<void>('beginInterval', scenario.name);
  debugPrint('LIQUID_GLASS_BENCHMARK_MEASURE_BEGIN:${scenario.name}');
  await Future<void>.delayed(Duration(seconds: measureSeconds));
  await _native.invokeMethod<void>('endInterval', scenario.name);
  debugPrint('LIQUID_GLASS_BENCHMARK_MEASURE_END:${scenario.name}');
  SchedulerBinding.instance.removeTimingsCallback(collectTimings);

  final memory = await _stopMemorySampling();
  var cooldownMemory = const <Map<String, Object?>>[];
  await _native.invokeMethod<void>('startMemorySampling');
  await Future<void>.delayed(const Duration(seconds: 5));
  cooldownMemory = await _stopMemorySampling();
  final settledMemory = cooldownMemory.lastOrNull;
  final report = <String, Object?>{
    'schemaVersion': 3,
    'scenario': scenario.name,
    'repetition': repetition,
    'warmupSeconds': warmupSeconds,
    'measureSeconds': measureSeconds,
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
    'settledNativeMemory': settledMemory,
    'cooldownNativeMemory': cooldownMemory,
  };
  debugPrint('LIQUID_GLASS_BENCHMARK_JSON:${jsonEncode(report)}');
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
  independent16Motion,
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
  const _BenchmarkApp({required this.scenario});
  final BenchmarkScenario scenario;

  @override
  State<_BenchmarkApp> createState() => _BenchmarkAppState();
}

class _BenchmarkAppState extends State<_BenchmarkApp>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
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
    final scenarioWidget = _isAnimated(scenario)
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
    final settings = const LiquidGlassSettings(thickness: 30, blur: 15);
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
      BenchmarkScenario.independent16Motion => Center(
        child: Transform.translate(
          offset: Offset(30 * math.sin(t * math.pi * 2), 0),
          child: Wrap(
            alignment: WrapAlignment.center,
            children: List.generate(
              16,
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

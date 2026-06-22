import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

const _scenarioName = String.fromEnvironment(
  'LIQUID_GLASS_BENCHMARK_SCENARIO',
  defaultValue: 'static_single',
);
const _warmupSeconds = int.fromEnvironment(
  'LIQUID_GLASS_BENCHMARK_WARMUP_SECONDS',
  defaultValue: 3,
);
const _measureSeconds = int.fromEnvironment(
  'LIQUID_GLASS_BENCHMARK_MEASURE_SECONDS',
  defaultValue: 8,
);
const _native = MethodChannel('dev.liquid_glass_renderer/benchmark');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'native benchmark: $_scenarioName',
    (tester) async {
      final scenario = BenchmarkScenario.values.byName(_scenarioName);
      final timings = <FrameTiming>[];
      final memory = <Map<String, Object?>>[];
      void collectTimings(List<FrameTiming> values) => timings.addAll(values);

      await tester.pumpWidget(_BenchmarkApp(scenario: scenario));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(seconds: _warmupSeconds));

      SchedulerBinding.instance.addTimingsCallback(collectTimings);
      await _native.invokeMethod<void>('beginInterval', scenario.name);
      final sampler = Timer.periodic(const Duration(milliseconds: 100), (
        _,
      ) async {
        final sample = await _native.invokeMapMethod<String, Object?>(
          'sampleMemory',
        );
        if (sample != null) memory.add(sample);
      });

      await binding.traceAction(
        () async {
          final stopwatch = Stopwatch()..start();
          while (stopwatch.elapsed < const Duration(seconds: _measureSeconds)) {
            await tester.pump();
            await Future<void>.delayed(const Duration(milliseconds: 16));
          }
        },
        reportKey: '${scenario.name}_timeline',
      );

      sampler.cancel();
      await _native.invokeMethod<void>('endInterval', scenario.name);
      SchedulerBinding.instance.removeTimingsCallback(collectTimings);
      await Future<void>.delayed(const Duration(milliseconds: 250));

      final report = <String, Object?>{
        'schemaVersion': 1,
        'scenario': scenario.name,
        'warmupSeconds': _warmupSeconds,
        'measureSeconds': _measureSeconds,
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
      };
      binding.reportData = <String, Object?>{
        ...?binding.reportData,
        'benchmark': report,
      };
      debugPrint('LIQUID_GLASS_BENCHMARK_JSON:${jsonEncode(report)}');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

enum BenchmarkScenario {
  baselineMotion,
  staticSingle,
  translatedSingle,
  scaledRotatedSingle,
  shared16Motion,
  resizeChurn,
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
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat(reverse: true);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: [
            const _Background(),
            AnimatedBuilder(
              animation: controller,
              builder: (_, __) => _buildScenario(controller.value),
            ),
          ],
        ),
      ),
    );
  }

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
      BenchmarkScenario.shared16Motion => LiquidGlassLayer(
        settings: settings,
        child: Center(
          child: Transform.translate(
            offset: Offset(30 * math.sin(t * math.pi * 2), 0),
            child: LiquidGlassBlendGroup(
              blend: 24,
              child: Wrap(
                alignment: WrapAlignment.center,
                children: List.generate(
                  16,
                  (index) => LiquidGlass.grouped(
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
      ),
      BenchmarkScenario.resizeChurn => Center(
        child: LiquidGlass.withOwnLayer(
          settings: settings,
          shape: const LiquidRoundedSuperellipse(borderRadius: 32),
          child: _tile(0, size: 120 + t * 360),
        ),
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

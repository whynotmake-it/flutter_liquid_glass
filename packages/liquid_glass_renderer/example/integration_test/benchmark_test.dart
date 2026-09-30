import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter, TileMode;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import '../../test/src/submitted_scene_binding.dart';

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
const _defaultRepetition = int.fromEnvironment(
  'LIQUID_GLASS_BENCHMARK_REPETITION',
  defaultValue: 1,
);
const _native = MethodChannel('dev.liquid_glass_renderer/benchmark');

/// Harness-only render-order check: the renderer stamps each matte with a
/// serial and the glass shader paints magenta where a frame samples a matte
/// rewritten before that frame was rasterized.
const _validateMatteOrder = bool.fromEnvironment(
  'LIQUID_GLASS_VALIDATE_MATTE_ORDER',
);

class _MatteOrderBinding extends WidgetsFlutterBinding
    with SubmittedSceneCapture {}

/// Captures submitted scenes back to back for [window] and counts magenta
/// pixels (opaque 255, 0, 255).
Future<Map<String, Object?>> _checkMatteOrder(Duration window) async {
  final binding = WidgetsBinding.instance as _MatteOrderBinding;
  final view = binding.platformDispatcher.views.first;
  binding
    ..captureWidth = view.physicalSize.width.round()
    ..captureHeight = view.physicalSize.height.round();
  var captured = 0;
  var framesWithMagenta = 0;
  var magentaPixels = 0;
  final end = DateTime.now().add(window);
  while (DateTime.now().isBefore(end)) {
    binding
      ..captureNextScene = true
      ..scheduleFrame();
    await binding.endOfFrame;
    final pending = binding.captured;
    binding.captured = null;
    if (pending == null) continue;
    final image = await pending;
    final bytes = (await image.toByteData())!.buffer.asUint8List();
    image.dispose();
    var magenta = 0;
    for (var i = 0; i < bytes.length; i += 4) {
      if (bytes[i] == 255 &&
          bytes[i + 1] == 0 &&
          bytes[i + 2] == 255 &&
          bytes[i + 3] == 255) {
        magenta++;
      }
    }
    captured++;
    if (magenta > 0) framesWithMagenta++;
    magentaPixels += magenta;
  }
  return <String, Object?>{
    'capturedFrames': captured,
    'framesWithMagenta': framesWithMagenta,
    'magentaPixels': magentaPixels,
  };
}

Future<void> main() async {
  if (_validateMatteOrder) {
    _MatteOrderBinding();
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }
  final nativeConfiguration = await _readNativeConfiguration();
  final scenario = BenchmarkScenario.values.byName(
    nativeConfiguration['scenario'] as String? ?? _defaultScenarioName,
  );
  final warmupSeconds =
      nativeConfiguration['warmupSeconds'] as int? ?? _defaultWarmupSeconds;
  final measureSeconds =
      nativeConfiguration['measureSeconds'] as int? ?? _defaultMeasureSeconds;
  final traceMeasureMilliseconds =
      nativeConfiguration['traceMeasureMilliseconds'] as int? ?? 500;
  final repetition =
      nativeConfiguration['repetition'] as int? ?? _defaultRepetition;
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
      await _invokeNativeVoid('beginInterval', scenario.name);
      windowFrameCount = 0;
      stdout.writeln(
        'LIQUID_GLASS_BENCHMARK_MEASURE_BEGIN:${scenario.name}:'
        '${DateTime.now().microsecondsSinceEpoch}',
      );
      await Future<void>.delayed(
        Duration(milliseconds: traceMeasureMilliseconds),
      );
      await SchedulerBinding.instance.endOfFrame;
      await _invokeNativeVoid('endInterval', scenario.name);
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
  await _invokeNativeVoid('startMemorySampling');

  SchedulerBinding.instance.addTimingsCallback(collectTimings);
  var vsyncTicks = 0;
  var measuring = true;
  void countVsync(Duration _) {
    vsyncTicks += 1;
    if (measuring) {
      SchedulerBinding.instance.scheduleFrameCallback(countVsync);
    }
  }

  SchedulerBinding.instance.scheduleFrameCallback(countVsync);
  SchedulerBinding.instance.scheduleFrame();
  await _startGpuTiming();
  await _invokeNativeVoid('beginInterval', scenario.name);
  debugPrint('LIQUID_GLASS_BENCHMARK_MEASURE_BEGIN:${scenario.name}');
  final matteOrderCheck = _validateMatteOrder
      ? _checkMatteOrder(Duration(seconds: measureSeconds))
      : null;
  await Future<void>.delayed(Duration(seconds: measureSeconds));
  final matteOrder = await matteOrderCheck;
  if (matteOrder != null) {
    debugPrint(
      'LIQUID_GLASS_MATTE_ORDER:${scenario.name}:'
      '${matteOrder['capturedFrames']}:${matteOrder['framesWithMagenta']}:'
      '${matteOrder['magentaPixels']}',
    );
  }
  measuring = false;
  await SchedulerBinding.instance.endOfFrame;
  await _invokeNativeVoid('endInterval', scenario.name);
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
    'matteOrderCheck': matteOrder,
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
    'preMeasureMemorySlopeMbPerSecond':
        preMeasureStability.slopeMbPerSecond.isFinite
        ? preMeasureStability.slopeMbPerSecond
        : null,
    'settledNativeMemory': settledMemory,
    'cooldownNativeMemory': cooldownMemory,
    'cooldownMemoryStable': cooldownStability.stable,
    'cooldownMemorySlopeMbPerSecond':
        cooldownStability.slopeMbPerSecond.isFinite
        ? cooldownStability.slopeMbPerSecond
        : null,
  };
  if (Platform.isAndroid) {
    // logcat truncates long lines, so the Android analyzer reads frames and
    // memory samples from chunked lines instead of the report JSON.
    _emitChunked(
      'LIQUID_GLASS_BENCHMARK_FRAMES',
      [
        for (final timing in timings)
          [
            timing.buildDuration.inMicroseconds,
            timing.rasterDuration.inMicroseconds,
          ],
      ],
    );
    _emitChunked(
      'LIQUID_GLASS_BENCHMARK_MEMORY',
      [
        for (final sample in memory)
          [sample['timestampMicros'], sample['physicalFootprintBytes']],
      ],
    );
  }
  debugPrint(
    'LIQUID_GLASS_BENCHMARK_SUMMARY:${jsonEncode(<String, Object?>{
      'scenario': scenario.name,
      'repetition': repetition,
      'frameCount': timings.isNotEmpty ? timings.length : vsyncTicks,
      'buildP95Micros': _timingPercentile(
        timings,
        .95,
        (t) => t.buildDuration,
      ),
      'rasterP50Micros': _timingPercentile(
        timings,
        .5,
        (t) => t.rasterDuration,
      ),
      'rasterP95Micros': _timingPercentile(
        timings,
        .95,
        (t) => t.rasterDuration,
      ),
      'rasterP99Micros': _timingPercentile(
        timings,
        .99,
        (t) => t.rasterDuration,
      ),
      'totalP95Micros': _timingPercentile(timings, .95, (t) => t.totalSpan),
    })}',
  );
  stdout.writeln('LIQUID_GLASS_BENCHMARK_JSON:${jsonEncode(report)}');
}

int? _timingPercentile(
  List<FrameTiming> timings,
  double percentile,
  Duration Function(FrameTiming timing) select,
) {
  if (timings.isEmpty) return null;
  final values =
      timings
          .map((timing) => select(timing).inMicroseconds)
          .toList(growable: false)
        ..sort();
  return values[((values.length - 1) * percentile).round()];
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

Future<Map<String, Object?>> _readNativeConfiguration() async {
  try {
    return await _native.invokeMapMethod<String, Object?>('configuration') ??
        const <String, Object?>{};
  } on PlatformException {
    return const <String, Object?>{};
  } on MissingPluginException {
    return const <String, Object?>{};
  }
}

Future<bool> _invokeNativeVoid(String method, [Object? arguments]) async {
  try {
    await _native.invokeMethod<void>(method, arguments);
    return true;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
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
    if (!await _invokeNativeVoid('startMemorySampling')) {
      return (samples: samples, stable: false, slopeMbPerSecond: slope);
    }
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
        .map((sample) => (sample['physicalFootprintBytes']! as num) / 1048576)
        .toList(),
  );
  final lastMb = median(
    last
        .map((sample) => (sample['physicalFootprintBytes']! as num) / 1048576)
        .toList(),
  );
  final firstSeconds = median(
    first
        .map((sample) => (sample['timestampMicros']! as num) / 1000000)
        .toList(),
  );
  final lastSeconds = median(
    last
        .map((sample) => (sample['timestampMicros']! as num) / 1000000)
        .toList(),
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
  try {
    final values = await _native.invokeListMethod<Object?>(
      'stopMemorySampling',
    );
    return values
            ?.whereType<Map<Object?, Object?>>()
            .map(
              (value) => value.map(
                (key, item) => MapEntry(key! as String, item),
              ),
            )
            .toList() ??
        const <Map<String, Object?>>[];
  } on PlatformException {
    return const <Map<String, Object?>>[];
  } on MissingPluginException {
    return const <Map<String, Object?>>[];
  }
}

void _emitChunked(String tag, List<Object?> rows) {
  final buffer = StringBuffer();
  var chunk = 0;
  for (final row in rows) {
    final encoded = jsonEncode(row);
    if (buffer.length + encoded.length > 800) {
      debugPrint('$tag:${chunk++}:$buffer');
      buffer.clear();
    }
    if (buffer.isNotEmpty) buffer.write(';');
    buffer.write(encoded);
  }
  if (buffer.isNotEmpty) debugPrint('$tag:${chunk++}:$buffer');
}

enum BenchmarkScenario {
  pxButtonStatic,
  pxButtonStretch,
  pxPillStretch,
  pxBlend5Motion,
  pxSheetResize,
  pxMultiLayer,
  colorsBlendStatic,
  colorsBlendMotion,
  baselineMotion,
  staticSingle,
  coloredSingleStatic,
  plainStatic,
  realLightingOnly,
  realBlurOnly,
  realHighBlurOnly,
  realSaturationOnly,
  realBlurSaturation,
  realToolbarMaterial,
  realClearMaterial,
  realClearUnfrosted,
  realClearSmooth,
  realToolbarSmooth,
  realClearNearest,
  realToolbarNearest,
  fakeLightingOnly,
  fakeBlurOnly,
  fakeHighBlurOnly,
  fakeSaturationOnly,
  fakeBlurSaturation,
  fakeToolbarMaterial,
  realToFakeTransition,
  translatedSingle,
  ancestorTranslatedLayer,
  scaledRotatedSingle,
  grouped1Motion,
  grouped4Motion,
  coloredGrouped4Motion,
  grouped4Static,
  coloredGrouped4Static,
  fakeGrouped4Motion,
  fakeUngrouped4Motion,
  grouped8Motion,
  grouped16Motion,
  coloredGrouped16Motion,
  grouped16Static,
  coloredGrouped16Static,
  coloredVisibility16Motion,
  litGrouped16Motion,
  independent4Motion,
  independent8Motion,
  independent16Motion,
  litIndependent16Motion,
  independent16SharedBackdrop,
  sparse16Motion,
  relativeBlendMotion,
  relativeBlend3Motion,
  tintedRelativeBlend3Motion,
  coloredRelativeBlend3Motion,
  fakeRelativeBlend3Motion,
  dynamicBlend16,
  resizeAnimated,
  layerChurn,
  largeStatic,
  largeResize,
  largeShrinkSettled,
  fakeStatic,
  fakeLarge,
  appScrollOpaque,
  appScrollPlainBlur,
  appScrollFake,
  appScrollReal,
  appScrollRealOneLayer,
  appScrollRealShadow,
  appScrollRealTabs,
  appScrollFakeShadow,
  appIdleReal,
  appIdleOpaque,
  appScrollRealNoFrost,
  appIdlePlainBlur,
  appIdleFake,
  appScrollRealTabsStatic,
  appScrollRealTabsOwnLoupe,
  appScrollRealTabsOwnLoupeStatic,
}

class _BenchmarkApp extends StatefulWidget {
  const _BenchmarkApp({required this.scenario, this.traceStartGate});
  final BenchmarkScenario scenario;
  final String? traceStartGate;

  @override
  State<_BenchmarkApp> createState() => _BenchmarkAppState();
}

class _BenchmarkAppState extends State<_BenchmarkApp>
    with TickerProviderStateMixin {
  late final AnimationController controller;
  late final AnimationController framePulse;
  bool traceGateOpen = false;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    framePulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    if (widget.traceStartGate == null || widget.traceStartGate!.isEmpty) {
      traceGateOpen = true;
      _startController();
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
    _startController();
  }

  void _startController() {
    if (widget.scenario == BenchmarkScenario.largeShrinkSettled) {
      controller.forward();
    } else {
      controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    framePulse.dispose();
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
                  animation: framePulse,
                  builder: (_, __) => Transform.translate(
                    offset: Offset(framePulse.value, 0),
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
    BenchmarkScenario.coloredSingleStatic ||
    BenchmarkScenario.grouped4Static ||
    BenchmarkScenario.coloredGrouped4Static ||
    BenchmarkScenario.grouped16Static ||
    BenchmarkScenario.coloredGrouped16Static ||
    BenchmarkScenario.largeStatic ||
    BenchmarkScenario.pxButtonStatic ||
    BenchmarkScenario.colorsBlendStatic ||
    BenchmarkScenario.plainStatic ||
    BenchmarkScenario.fakeStatic ||
    BenchmarkScenario.fakeLarge ||
    BenchmarkScenario.appIdleReal ||
    BenchmarkScenario.appIdleOpaque ||
    BenchmarkScenario.appIdlePlainBlur ||
    BenchmarkScenario.appIdleFake => false,
    _ => true,
  };

  Widget _buildScenario(double t) {
    const settings = LiquidGlassSettings(
      refractionHeight: 30,
      frost: 15,
    );
    const litSettings = LiquidGlassSettings(
      refractionHeight: 30,
      frost: 15,
      contourStrength: .22,
      contourWidth: 1.5,
      contourTransmittance: .8,
      bevelShadowStrength: .025,
    );
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
      BenchmarkScenario.coloredSingleStatic => Center(
        child: LiquidGlass.withOwnLayer(
          settings: settings,
          appearance: const LiquidGlassAppearance(
            tint: Color(0xAA287DFF),
            saturation: 1.8,
            transmissionGamma: .78,
            vibrancy: .25,
          ),
          shape: const LiquidRoundedSuperellipse(borderRadius: 32),
          child: _tile(0),
        ),
      ),
      BenchmarkScenario.plainStatic => Center(child: _tile(0)),
      BenchmarkScenario.realLightingOnly => _realLayer(
        const LiquidGlassSettings(
          frost: 0,
        ),
        t,
        appearance: const LiquidGlassAppearance(),
      ),
      BenchmarkScenario.realBlurOnly => _realLayer(
        const LiquidGlassSettings(
          frost: 15,
          highlight: 0,
        ),
        t,
        appearance: const LiquidGlassAppearance(),
      ),
      BenchmarkScenario.realHighBlurOnly => _realLayer(
        const LiquidGlassSettings(
          frost: 40,
          highlight: 0,
        ),
        t,
        appearance: const LiquidGlassAppearance(),
      ),
      BenchmarkScenario.realSaturationOnly => _realLayer(
        const LiquidGlassSettings(
          frost: 0,
          highlight: 0,
        ),
        t,
        appearance: const LiquidGlassAppearance(saturation: 1.5),
      ),
      BenchmarkScenario.realBlurSaturation => _realLayer(
        const LiquidGlassSettings(
          frost: 15,
          highlight: 0,
        ),
        t,
        appearance: const LiquidGlassAppearance(saturation: 1.5),
      ),
      BenchmarkScenario.realToolbarMaterial => _realLayer(
        LiquidGlassSettings.ios27ToolbarLight(),
        t,
        appearance: const LiquidGlassAppearance.ios27ToolbarLight(),
      ),
      BenchmarkScenario.realClearMaterial => _realLayer(
        LiquidGlassSettings.ios27Clear(),
        t,
        appearance: const LiquidGlassAppearance(),
      ),
      BenchmarkScenario.realClearUnfrosted => _realLayer(
        LiquidGlassSettings.ios27Clear(frost: 0),
        t,
        appearance: const LiquidGlassAppearance(),
      ),
      BenchmarkScenario.realClearSmooth => _realLayer(
        LiquidGlassSettings.ios27Clear(
          frost: 0,
        ).copyWith(smoothRefraction: true),
        t,
        appearance: const LiquidGlassAppearance(),
      ),
      BenchmarkScenario.realToolbarSmooth => _realLayer(
        LiquidGlassSettings.ios27ToolbarLight().copyWith(
          smoothRefraction: true,
        ),
        t,
        appearance: const LiquidGlassAppearance.ios27ToolbarLight(),
      ),
      BenchmarkScenario.realClearNearest => _realLayer(
        LiquidGlassSettings.ios27Clear(
          frost: 0,
        ).copyWith(smoothRefraction: false),
        t,
        appearance: const LiquidGlassAppearance(),
      ),
      BenchmarkScenario.realToolbarNearest => _realLayer(
        LiquidGlassSettings.ios27ToolbarLight().copyWith(
          smoothRefraction: false,
        ),
        t,
        appearance: const LiquidGlassAppearance.ios27ToolbarLight(),
      ),
      BenchmarkScenario.fakeLightingOnly => _fakeLayer(
        const LiquidGlassSettings(
          frost: 0,
        ),
        t,
        appearance: const LiquidGlassAppearance(),
      ),
      BenchmarkScenario.fakeBlurOnly => _fakeLayer(
        const LiquidGlassSettings(
          frost: 15,
          highlight: 0,
        ),
        t,
        appearance: const LiquidGlassAppearance(),
      ),
      BenchmarkScenario.fakeHighBlurOnly => _fakeLayer(
        const LiquidGlassSettings(
          frost: 40,
          highlight: 0,
        ),
        t,
        appearance: const LiquidGlassAppearance(),
      ),
      BenchmarkScenario.fakeSaturationOnly => _fakeLayer(
        const LiquidGlassSettings(
          frost: 0,
          highlight: 0,
        ),
        t,
        appearance: const LiquidGlassAppearance(saturation: 1.5),
      ),
      BenchmarkScenario.fakeBlurSaturation => _fakeLayer(
        const LiquidGlassSettings(
          frost: 15,
          highlight: 0,
        ),
        t,
        appearance: const LiquidGlassAppearance(saturation: 1.5),
      ),
      BenchmarkScenario.fakeToolbarMaterial => _fakeLayer(
        LiquidGlassSettings.ios27ToolbarLight(),
        t,
        appearance: const LiquidGlassAppearance.ios27ToolbarLight(),
      ),
      BenchmarkScenario.realToFakeTransition => _RealThenFakeScenario(
        t: t,
        retirementDelay:
            widget.traceStartGate == null || widget.traceStartGate!.isEmpty
            ? const Duration(milliseconds: 1500)
            : const Duration(seconds: 5),
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
      BenchmarkScenario.grouped1Motion => _groupedGrid(
        settings: settings,
        count: 1,
        t: t,
      ),
      BenchmarkScenario.grouped4Motion => _groupedGrid(
        settings: settings,
        count: 4,
        t: t,
      ),
      BenchmarkScenario.coloredGrouped4Motion => _groupedGrid(
        settings: settings,
        count: 4,
        t: t,
        variedAppearance: true,
      ),
      BenchmarkScenario.grouped4Static => _groupedGrid(
        settings: settings,
        count: 4,
        t: 0,
      ),
      BenchmarkScenario.coloredGrouped4Static => _groupedGrid(
        settings: settings,
        count: 4,
        t: 0,
        variedAppearance: true,
      ),
      BenchmarkScenario.fakeGrouped4Motion => _groupedGrid(
        settings: settings,
        count: 4,
        t: t,
        fake: true,
        shareBackdrop: true,
      ),
      BenchmarkScenario.fakeUngrouped4Motion => _groupedGrid(
        settings: settings,
        count: 4,
        t: t,
        blend: 0,
        fake: true,
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
      BenchmarkScenario.coloredGrouped16Motion => _groupedGrid(
        settings: settings,
        count: 16,
        t: t,
        variedAppearance: true,
      ),
      BenchmarkScenario.grouped16Static => _groupedGrid(
        settings: settings,
        count: 16,
        t: 0,
      ),
      BenchmarkScenario.coloredGrouped16Static => _groupedGrid(
        settings: settings,
        count: 16,
        t: 0,
        variedAppearance: true,
      ),
      BenchmarkScenario.coloredVisibility16Motion => _groupedGrid(
        settings: settings,
        count: 16,
        t: t,
        variedAppearance: true,
        animateVisibility: true,
      ),
      BenchmarkScenario.litGrouped16Motion => _groupedGrid(
        settings: litSettings,
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
      BenchmarkScenario.litIndependent16Motion => _independentGrid(
        settings: litSettings,
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
      BenchmarkScenario.relativeBlend3Motion => _relativeBlend3Group(
        settings: settings,
        t: t,
      ),
      BenchmarkScenario.tintedRelativeBlend3Motion => _relativeBlend3Group(
        settings: settings,
        t: t,
        tintOnly: true,
      ),
      BenchmarkScenario.coloredRelativeBlend3Motion => _relativeBlend3Group(
        settings: settings,
        t: t,
        variedResponse: true,
      ),
      BenchmarkScenario.fakeRelativeBlend3Motion => _relativeBlend3Group(
        settings: settings,
        t: t,
        tintOnly: true,
        fake: true,
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
      BenchmarkScenario.pxButtonStatic => _pxStretched(t, 44, 44, false),
      BenchmarkScenario.pxButtonStretch => _pxStretched(t, 44, 44, true),
      BenchmarkScenario.pxPillStretch => _pxStretched(t, 96, 40, true),
      BenchmarkScenario.pxBlend5Motion => _pxBlend5(t),
      BenchmarkScenario.pxSheetResize => _pxSheet(t),
      BenchmarkScenario.pxMultiLayer => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _pxMultiLayer(120 + 24 * t),
            const SizedBox(height: 16),
            _pxMultiLayer(90 + 24 * t, tinted: true),
            const SizedBox(height: 16),
            _pxMultiLayer(150 - 24 * t),
          ],
        ),
      ),
      BenchmarkScenario.colorsBlendStatic => _colorsBlend(0),
      BenchmarkScenario.colorsBlendMotion => _colorsBlend(t),
      BenchmarkScenario.largeStatic => _largeLayer(
        settings: settings,
        size: 2048,
      ),
      BenchmarkScenario.largeResize => _largeLayer(
        settings: settings,
        size: 1024 + t * 1024,
      ),
      BenchmarkScenario.largeShrinkSettled => _largeLayer(
        settings: settings,
        size: 2048 - t * 1792,
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
      BenchmarkScenario.appScrollOpaque => _AppLikeScene(
        t: t,
        scroll: true,
        chrome: _AppChromeKind.opaque,
      ),
      BenchmarkScenario.appScrollPlainBlur => _AppLikeScene(
        t: t,
        scroll: true,
        chrome: _AppChromeKind.plainBlur,
      ),
      BenchmarkScenario.appScrollFake => _AppLikeScene(
        t: t,
        scroll: true,
        chrome: _AppChromeKind.fake,
      ),
      BenchmarkScenario.appScrollReal => _AppLikeScene(
        t: t,
        scroll: true,
        chrome: _AppChromeKind.real,
      ),
      BenchmarkScenario.appScrollRealOneLayer => _AppLikeScene(
        t: t,
        scroll: true,
        chrome: _AppChromeKind.realOneLayer,
      ),
      BenchmarkScenario.appScrollRealShadow => _AppLikeScene(
        t: t,
        scroll: true,
        chrome: _AppChromeKind.realShadow,
      ),
      BenchmarkScenario.appScrollRealTabs => _AppLikeScene(
        t: t,
        scroll: true,
        chrome: _AppChromeKind.realTabs,
      ),
      BenchmarkScenario.appScrollFakeShadow => _AppLikeScene(
        t: t,
        scroll: true,
        chrome: _AppChromeKind.fakeShadow,
      ),
      BenchmarkScenario.appIdleReal => const _AppLikeScene(
        t: 0,
        scroll: false,
        chrome: _AppChromeKind.real,
      ),
      BenchmarkScenario.appIdleOpaque => const _AppLikeScene(
        t: 0,
        scroll: false,
        chrome: _AppChromeKind.opaque,
      ),
      BenchmarkScenario.appScrollRealNoFrost => _AppLikeScene(
        t: t,
        scroll: true,
        chrome: _AppChromeKind.realNoFrost,
      ),
      BenchmarkScenario.appIdlePlainBlur => const _AppLikeScene(
        t: 0,
        scroll: false,
        chrome: _AppChromeKind.plainBlur,
      ),
      BenchmarkScenario.appIdleFake => const _AppLikeScene(
        t: 0,
        scroll: false,
        chrome: _AppChromeKind.fake,
      ),
      BenchmarkScenario.appScrollRealTabsStatic => _AppLikeScene(
        t: t,
        scroll: true,
        chrome: _AppChromeKind.realTabsStatic,
      ),
      BenchmarkScenario.appScrollRealTabsOwnLoupe => _AppLikeScene(
        t: t,
        scroll: true,
        chrome: _AppChromeKind.realTabsOwnLoupe,
      ),
      BenchmarkScenario.appScrollRealTabsOwnLoupeStatic => _AppLikeScene(
        t: t,
        scroll: true,
        chrome: _AppChromeKind.realTabsOwnLoupeStatic,
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

  Widget _realLayer(
    LiquidGlassSettings settings,
    double t, {
    LiquidGlassAppearance? appearance,
  }) => LiquidGlassLayer(
    settings: settings,
    defaultAppearance: appearance,
    child: Center(
      child: Transform.translate(
        offset: Offset(-180 + 360 * t, 0),
        child: LiquidGlass(
          shape: const LiquidRoundedSuperellipse(borderRadius: 32),
          child: _tile(0),
        ),
      ),
    ),
  );

  Widget _fakeLayer(
    LiquidGlassSettings settings,
    double t, {
    LiquidGlassAppearance? appearance,
  }) => LiquidGlassLayer(
    settings: settings,
    defaultAppearance: appearance,
    fake: true,
    child: Center(
      child: Transform.translate(
        offset: Offset(-180 + 360 * t, 0),
        child: LiquidGlass(
          shape: const LiquidRoundedSuperellipse(borderRadius: 32),
          child: _tile(0),
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

  static const _pxSettings = LiquidGlassSettings(
    refractionHeight: 30,
    frost: 15,
  );

  Widget _pxStretched(double t, double width, double height, bool animate) {
    final s = animate ? t : 0.0;
    return LiquidGlassLayer(
      settings: _pxSettings,
      child: Center(
        child: Transform.scale(
          scaleX: 1 + .3 * s,
          scaleY: 1 - .18 * s,
          child: LiquidGlass(
            shape: LiquidRoundedSuperellipse(borderRadius: height / 2),
            child: SizedBox(
              width: width,
              height: height,
              child: const Center(child: Icon(Icons.add, size: 22)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _pxBlend5(double t) => LiquidGlassLayer(
    settings: _pxSettings,
    child: Center(
      child: SizedBox(
        width: 400,
        height: 200,
        child: LiquidGlassBlendGroup(
          blend: 40,
          child: Stack(
            children: [
              for (var i = 0; i < 5; i++)
                Positioned(
                  left: 8 + i * 78.0,
                  top: 74 + 30 * math.sin(2 * math.pi * t + i * 1.3),
                  child: const LiquidGlass.grouped(
                    shape: LiquidRoundedSuperellipse(borderRadius: 26),
                    child: SizedBox(width: 72, height: 52),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _pxSheet(double t) {
    final size = MediaQuery.sizeOf(context);
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: LiquidGlass.withOwnLayer(
          settings: _pxSettings,
          shape: const LiquidRoundedSuperellipse(borderRadius: 38),
          child: SizedBox(
            width: size.width - 16,
            height: size.height * (.45 + .45 * t),
          ),
        ),
      ),
    );
  }

  Widget _pxMultiLayer(double width, {bool tinted = false}) => LiquidGlassLayer(
    settings: _pxSettings,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        LiquidGlass(
          shape: const LiquidRoundedSuperellipse(borderRadius: 22),
          child: SizedBox(width: width, height: 44),
        ),
        const SizedBox(width: 8),
        LiquidGlass(
          shape: const LiquidOval(),
          appearance: tinted
              ? const LiquidGlassAppearance(tint: Color(0x552060FF))
              : null,
          child: const SizedBox(width: 44, height: 44),
        ),
      ],
    ),
  );

  // The #183 Colors scene at 2x: light, dark, clear and blue-tinted glass in
  // one blend group. Motion breathes the swatches apart and back together.
  Widget _colorsBlend(double t) {
    const swatches = [
      (Offset(-1, -1), LiquidGlassAppearance.ios27RegularLight()),
      (Offset(1, -1), LiquidGlassAppearance.ios27RegularDark()),
      (Offset(-1, 1), LiquidGlassAppearance.ios27Clear()),
      (
        Offset(1, 1),
        LiquidGlassAppearance.ios27RegularLight(tint: Color(0xFF0A84FF)),
      ),
    ];
    final spread = 100 + 24 * math.sin(t * math.pi * 2);
    return LiquidGlassLayer(
      settings: LiquidGlassSettings.ios27Toolbar(brightness: Brightness.dark),
      child: Center(
        child: SizedBox.square(
          dimension: 560,
          child: LiquidGlassBlendGroup(
            blend: 48,
            child: Stack(
              children: [
                for (final (dir, appearance) in swatches)
                  Positioned(
                    left: 280 + dir.dx * spread - 108,
                    top: 280 + dir.dy * spread - 108,
                    child: LiquidGlass.grouped(
                      appearance: appearance,
                      shape: const LiquidOval(),
                      child: const SizedBox.square(dimension: 216),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _groupedGrid({
    required LiquidGlassSettings settings,
    required int count,
    required double t,
    double blend = 24,
    bool fake = false,
    bool shareBackdrop = false,
    bool variedAppearance = false,
    bool animateVisibility = false,
    LiquidGlassAppearance? defaultAppearance,
  }) {
    // Keep total glass area approximately constant across the count ladder.
    final tileSize = 72 * math.sqrt(16 / count);
    return LiquidGlassLayer(
      settings: settings,
      defaultAppearance: defaultAppearance,
      fake: fake,
      useBackdropGroup: shareBackdrop,
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
                  appearance: variedAppearance
                      ? LiquidGlassAppearance(
                          tint: Color.lerp(
                            const Color(0x99FFFFFF),
                            const Color(0xAA287DFF),
                            index / math.max(count - 1, 1),
                          )!,
                          saturation: 0.8 + index / count * 1.8,
                          transmissionGamma: 0.75 + index / count * 0.35,
                          vibrancy: index / count * 0.25,
                          visibility: animateVisibility
                              ? (0.5 + 0.5 * math.sin(t * math.pi * 2 + index))
                              : 1,
                        )
                      : null,
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

  Widget _relativeBlend3Group({
    required LiquidGlassSettings settings,
    required double t,
    bool tintOnly = false,
    bool variedResponse = false,
    bool fake = false,
  }) {
    LiquidGlassAppearance? appearance(int index) {
      if (!tintOnly && !variedResponse) return null;
      return LiquidGlassAppearance(
        tint: Color.lerp(
          const Color(0x99FFFFFF),
          const Color(0xAA287DFF),
          index / 2,
        )!,
        saturation: variedResponse ? 0.9 + index * 0.6 : 1,
        transmissionGamma: variedResponse ? 0.8 + index * 0.1 : 1,
        vibrancy: variedResponse ? index * 0.1 : 0,
      );
    }

    return LiquidGlassLayer(
      settings: settings,
      fake: fake,
      child: Center(
        child: SizedBox(
          width: 560,
          height: 320,
          child: LiquidGlassBlendGroup(
            blend: 32,
            child: Stack(
              children: [
                Positioned(
                  left: 70 + 180 * t,
                  top: 40,
                  child: LiquidGlass.grouped(
                    appearance: appearance(0),
                    shape: const LiquidRoundedSuperellipse(borderRadius: 36),
                    child: SizedBox(
                      width: 120 + 120 * t,
                      height: 120,
                      child: _tile(0),
                    ),
                  ),
                ),
                Positioned(
                  left: 220,
                  top: 105,
                  child: LiquidGlass.grouped(
                    appearance: appearance(1),
                    shape: const LiquidOval(),
                    child: _tile(1, size: 132),
                  ),
                ),
                Positioned(
                  right: 60 + 80 * t,
                  bottom: 35,
                  child: LiquidGlass.grouped(
                    appearance: appearance(2),
                    shape: const LiquidRoundedSuperellipse(borderRadius: 28),
                    child: _tile(2, size: 116),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

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

class _RealThenFakeScenario extends StatefulWidget {
  const _RealThenFakeScenario({required this.t, required this.retirementDelay});

  final double t;
  final Duration retirementDelay;

  @override
  State<_RealThenFakeScenario> createState() => _RealThenFakeScenarioState();
}

class _RealThenFakeScenarioState extends State<_RealThenFakeScenario> {
  Timer? _retirementTimer;
  bool _fake = false;

  @override
  void initState() {
    super.initState();
    _retirementTimer = Timer(widget.retirementDelay, () {
      if (!mounted) return;
      setState(() => _fake = true);
      debugPrint('LIQUID_GLASS_BENCHMARK_REAL_RENDERER_RETIRED');
    });
  }

  @override
  void dispose() {
    _retirementTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LiquidGlassLayer(
    fake: _fake,
    settings: LiquidGlassSettings.ios27ToolbarLight(),
    child: Center(
      child: Transform.translate(
        offset: Offset(-180 + 360 * widget.t, 0),
        child: const LiquidGlass(
          shape: LiquidRoundedSuperellipse(borderRadius: 32),
          child: SizedBox.square(dimension: 240),
        ),
      ),
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

enum _AppChromeKind {
  opaque,
  plainBlur,
  fake,
  real,
  realOneLayer,
  realShadow,
  realTabs,
  fakeShadow,
  realNoFrost,
  realTabsStatic,
  realTabsOwnLoupe,
  realTabsOwnLoupeStatic,
}

final _appToolbarSettings = LiquidGlassSettings.ios27ToolbarLight();
const _appToolbarAppearance = LiquidGlassAppearance.ios27ToolbarLight();
const _appChromeShadows = [
  BoxShadow(
    color: Color(0x2E000000),
    blurRadius: 24,
    offset: Offset(0, 8),
  ),
];

class _AppLikeScene extends StatefulWidget {
  const _AppLikeScene({
    required this.t,
    required this.scroll,
    required this.chrome,
  });

  final double t;
  final bool scroll;
  final _AppChromeKind chrome;

  @override
  State<_AppLikeScene> createState() => _AppLikeSceneState();
}

class _AppLikeSceneState extends State<_AppLikeScene> {
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
    if (widget.scroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncScroll());
    }
  }

  @override
  void didUpdateWidget(_AppLikeScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scroll) {
      _syncScroll();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncScroll() {
    if (!_controller.hasClients) return;
    final target = (widget.t * 2400).clamp(
      0.0,
      _controller.position.maxScrollExtent,
    );
    if ((_controller.offset - target).abs() > 0.5) {
      _controller.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Fixed status-bar inset: MediaQuery padding can be 0 on the first build
    // or change while the harness pins the screen, which would move ~40 px of
    // top-bar filter area between otherwise identical runs.
    const topInset = 48.0;
    final stack = Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xffe8eef6), Color(0xffd5dde8)],
            ),
          ),
          child: SizedBox.expand(),
        ),
        ListView.builder(
          controller: _controller,
          physics: const NeverScrollableScrollPhysics(),
          itemExtent: 72,
          itemCount: 200,
          padding: EdgeInsets.zero,
          itemBuilder: (context, index) => _AppListRow(index: index),
        ),
        ..._chromeOverlay(topInset),
      ],
    );
    return stack;
  }

  List<Widget> _chromeOverlay(double topInset) {
    final topBar = _topBar(topInset);
    final bottomPill = _bottomPill();
    if (widget.chrome == _AppChromeKind.realOneLayer) {
      return [
        LiquidGlassLayer(
          settings: _layerSettings,
          defaultAppearance: _appToolbarAppearance,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                top: 0,
                left: 8,
                right: 8,
                child: LiquidGlass(
                  shape: const LiquidRoundedSuperellipse(
                    borderRadius: 28,
                  ),
                  child: topBar,
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 24,
                child: Center(
                  child: LiquidGlass(
                    shape: const LiquidRoundedSuperellipse(
                      borderRadius: 32,
                    ),
                    child: bottomPill,
                  ),
                ),
              ),
            ],
          ),
        ),
      ];
    }

    final tabs =
        widget.chrome == _AppChromeKind.realTabs ||
        widget.chrome == _AppChromeKind.realTabsStatic ||
        widget.chrome == _AppChromeKind.realTabsOwnLoupe ||
        widget.chrome == _AppChromeKind.realTabsOwnLoupeStatic;
    return [
      Positioned(
        top: 0,
        left: 8,
        right: 8,
        child: _wrapChrome(
          radius: 28,
          child: topBar,
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 24,
        child: Center(
          child: tabs
              ? _realTabsPill(bottomPill)
              : _wrapChrome(radius: 32, child: bottomPill),
        ),
      ),
    ];
  }

  Widget _topBar(double topInset) => SizedBox(
    height: 56 + topInset,
    width: double.infinity,
    child: Padding(
      padding: EdgeInsets.only(top: topInset),
      child: Row(
        children: [
          const SizedBox(width: 16),
          const Expanded(
            child: Text(
              'Inbox',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.search),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.more_vert),
          ),
        ],
      ),
    ),
  );

  Widget _bottomPill() => const SizedBox(
    width: 340,
    height: 64,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Icon(Icons.home_outlined),
        Icon(Icons.search),
        Icon(Icons.add_box_outlined),
        Icon(Icons.favorite_border),
        Icon(Icons.person_outline),
      ],
    ),
  );

  Widget _realTabsPill(Widget pillContent) {
    const travel = 340.0 - 56 - 8;
    return LiquidGlassLayer(
      settings: _layerSettings,
      defaultAppearance: _appToolbarAppearance,
      child: LiquidGlassBlendGroup(
        child: SizedBox(
          width: 340,
          height: 64,
          child: Stack(
            children: [
              LiquidGlass.grouped(
                shape: const LiquidRoundedSuperellipse(borderRadius: 32),
                shadows: _shadowsFor(widget.chrome),
                child: pillContent,
              ),
              Positioned(
                left:
                    4 +
                    (widget.chrome == _AppChromeKind.realTabsStatic ||
                                widget.chrome ==
                                    _AppChromeKind.realTabsOwnLoupeStatic
                            ? 0.0
                            : widget.t) *
                        travel,
                top: 8,
                // ClickUp's indicator samples the painted bar through its own
                // backdrop capture (frost 0, strong edge refraction). This
                // variant prices that second readback against the blended
                // loupe above.
                child:
                    widget.chrome == _AppChromeKind.realTabsOwnLoupe ||
                        widget.chrome == _AppChromeKind.realTabsOwnLoupeStatic
                    ? const LiquidGlassLayer(
                        settings: LiquidGlassSettings(
                          frost: 0,
                          refractionHeight: 24,
                          refractionAmount: 40,
                          backdropShrink: .08,
                          dispersion: .1,
                          highlight: .4,
                          contourStrength: .1,
                          contourWidth: 1,
                        ),
                        defaultAppearance: LiquidGlassAppearance(),
                        child: LiquidGlass(
                          shape: LiquidRoundedSuperellipse(borderRadius: 24),
                          child: SizedBox(width: 56, height: 48),
                        ),
                      )
                    : const LiquidGlass.grouped(
                        shape: LiquidRoundedSuperellipse(borderRadius: 24),
                        child: SizedBox(width: 56, height: 48),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<BoxShadow> _shadowsFor(_AppChromeKind chrome) =>
      chrome == _AppChromeKind.realShadow || chrome == _AppChromeKind.fakeShadow
      ? _appChromeShadows
      : const [];

  LiquidGlassSettings get _layerSettings =>
      widget.chrome == _AppChromeKind.realNoFrost
      ? _appToolbarSettings.copyWith(frost: 0)
      : _appToolbarSettings;

  static final ImageFilter _sigma7Blur = ImageFilter.blur(
    sigmaX: 7,
    sigmaY: 7,
    tileMode: TileMode.mirror,
  );

  Widget _plainBlurChrome({
    required double radius,
    required Widget child,
    required ImageFilter filter,
  }) {
    final content = ColoredBox(
      color: Colors.white.withValues(alpha: .45),
      child: child,
    );
    return ClipRSuperellipse(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(filter: filter, child: content),
    );
  }

  Widget _wrapChrome({
    required double radius,
    required Widget child,
  }) {
    final shape = LiquidRoundedSuperellipse(borderRadius: radius);
    final shadows = _shadowsFor(widget.chrome);
    switch (widget.chrome) {
      case _AppChromeKind.opaque:
        return DecoratedBox(
          decoration: ShapeDecoration(
            color: const Color(0xffe0e0e0),
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(radius),
            ),
          ),
          child: child,
        );
      case _AppChromeKind.plainBlur:
        return _plainBlurChrome(
          radius: radius,
          child: child,
          filter: _sigma7Blur,
        );
      case _AppChromeKind.fake:
      case _AppChromeKind.fakeShadow:
        return LiquidGlassLayer(
          fake: true,
          settings: _layerSettings,
          defaultAppearance: _appToolbarAppearance,
          child: LiquidGlass(
            shape: shape,
            shadows: shadows,
            child: child,
          ),
        );
      case _AppChromeKind.real:
      case _AppChromeKind.realShadow:
      case _AppChromeKind.realTabs:
      case _AppChromeKind.realTabsStatic:
      case _AppChromeKind.realTabsOwnLoupe:
      case _AppChromeKind.realTabsOwnLoupeStatic:
      case _AppChromeKind.realOneLayer:
      case _AppChromeKind.realNoFrost:
        return LiquidGlassLayer(
          settings: _layerSettings,
          defaultAppearance: _appToolbarAppearance,
          child: LiquidGlass(
            shape: shape,
            shadows: shadows,
            child: child,
          ),
        );
    }
  }
}

class _AppListRow extends StatelessWidget {
  const _AppListRow({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final color = Colors.primaries[index % Colors.primaries.length];
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Message $index',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'Preview line for row $index',
                        style: TextStyle(
                          color: Colors.black.withValues(alpha: .55),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1, thickness: 0.5),
      ],
    );
  }
}

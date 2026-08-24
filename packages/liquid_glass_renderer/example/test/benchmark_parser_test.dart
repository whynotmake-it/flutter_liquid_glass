import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses native GPU intervals and Metal allocation lifetimes', () async {
    final fixture = await Directory.systemTemp.createTemp('glass-benchmark-');
    addTearDown(() => fixture.deleteSync(recursive: true));
    final traces = Directory('${fixture.path}/traces')..createSync();
    _writeScenario(fixture, scenario: 'staticSingle');
    File('${traces.path}/staticSingle.gpu.xml').writeAsStringSync(_gpuXml);
    File(
      '${traces.path}/staticSingle.metal-resources.xml',
    ).writeAsStringSync(_metalXml);

    final result = await _runParser(fixture, enforce: true);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final summary = jsonDecode(
      File('${fixture.path}/summary.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final scenario =
        (summary['scenarioRuns'] as List<dynamic>).single
            as Map<String, dynamic>;
    final gpu = scenario['gpu'] as Map<String, dynamic>;
    final metal = scenario['metal'] as Map<String, dynamic>;
    expect(gpu['intervalCount'], 3);
    expect(gpu['busyMs'], closeTo(200, .001));
    expect(gpu['intervalP95Ms'], closeTo(100, .001));
    expect(metal['allocationCount'], 2);
    expect(metal['deallocationCount'], 1);
    expect(metal['cumulativeAllocatedMb'], closeTo(150 / 1048576, 1e-9));
    expect(scenario['nativeFootprintRetainedDeltaMb'], closeTo(10, 1e-9));
    expect(scenario['nativeFootprintPeakAbovePreMeasureMb'], closeTo(40, 1e-9));
  });

  test('ignores wrapped u64 durations from clipped trace rows', () async {
    final fixture = await Directory.systemTemp.createTemp('glass-benchmark-');
    addTearDown(() => fixture.deleteSync(recursive: true));
    final traces = Directory('${fixture.path}/traces')..createSync();
    _writeScenario(fixture, scenario: 'staticSingle');
    File(
      '${traces.path}/staticSingle.gpu.xml',
    ).writeAsStringSync(_gpuXmlWithWrappedDuration);
    File(
      '${traces.path}/staticSingle.metal-resources.xml',
    ).writeAsStringSync(_metalXml);

    final result = await _runParser(fixture, enforce: true);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final summary = jsonDecode(
      File('${fixture.path}/summary.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final scenario =
        (summary['scenarioRuns'] as List<dynamic>).single
            as Map<String, dynamic>;
    final gpu = scenario['gpu'] as Map<String, dynamic>;
    expect(gpu['intervalCount'], 3);
    expect(gpu['busyMs'], closeTo(200, .001));
  });

  test('reads the interval duration, not the CPU-to-GPU latency', () async {
    final fixture = await Directory.systemTemp.createTemp('glass-benchmark-');
    addTearDown(() => fixture.deleteSync(recursive: true));
    final traces = Directory('${fixture.path}/traces')..createSync();
    _writeScenario(fixture, scenario: 'staticSingle');
    File(
      '${traces.path}/staticSingle.gpu.xml',
    ).writeAsStringSync(_gpuXmlWithLatencyColumn);
    File(
      '${traces.path}/staticSingle.metal-resources.xml',
    ).writeAsStringSync(_metalXml);

    final result = await _runParser(fixture, enforce: true);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final summary = jsonDecode(
      File('${fixture.path}/summary.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final scenario =
        (summary['scenarioRuns'] as List<dynamic>).single
            as Map<String, dynamic>;
    final gpu = scenario['gpu'] as Map<String, dynamic>;
    expect(gpu['intervalCount'], 3);
    expect(gpu['busyMs'], closeTo(200, .001));
    expect(gpu['intervalP95Ms'], closeTo(100, .001));
  });

  test('integrates GPU busy across every aligned workload window', () async {
    final fixture = await Directory.systemTemp.createTemp('glass-benchmark-');
    addTearDown(() => fixture.deleteSync(recursive: true));
    final traces = Directory('${fixture.path}/traces')..createSync();
    _writeScenario(fixture, scenario: 'staticSingle');
    File(
      '${traces.path}/staticSingle.signposts.xml',
    ).writeAsStringSync(_twoWindowSignpostXml);
    File(
      '${traces.path}/staticSingle.gpu.xml',
    ).writeAsStringSync(_gpuXmlTwoWindows);
    File(
      '${traces.path}/staticSingle.metal-resources.xml',
    ).writeAsStringSync(_metalXml);

    final result = await _runParser(fixture, enforce: true);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final summary = jsonDecode(
      File('${fixture.path}/summary.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final scenario =
        (summary['scenarioRuns'] as List<dynamic>).single
            as Map<String, dynamic>;
    final gpu = scenario['gpu'] as Map<String, dynamic>;
    expect(scenario['nativeTraceMeasureSeconds'], closeTo(2, 1e-9));
    expect(gpu['busyMs'], closeTo(300, .001));
    expect(gpu['observedSpanMs'], closeTo(2000, .001));
  });

  test(
    'missing native Instruments tables are informational, not enforced',
    () async {
      final fixture = await Directory.systemTemp.createTemp('glass-benchmark-');
      addTearDown(() => fixture.deleteSync(recursive: true));
      _writeScenario(fixture, scenario: 'staticSingle');

      final result = await _runParser(fixture, enforce: true);

      // GPU and Metal metrics are attribution-only: their absence is reported
      // as unavailable in the summary, never as a gate failure.
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final summary = jsonDecode(
        File('${fixture.path}/summary.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final scenario =
          (summary['scenarioRuns'] as List<dynamic>).single
              as Map<String, dynamic>;
      expect(scenario['gpu'], isNull);
      expect(scenario['metal'], isNull);
      expect(summary['regressionViolations'], isEmpty);
    },
  );

  test('passes enforcement for scenarios without any trace', () async {
    final fixture = await Directory.systemTemp.createTemp('glass-benchmark-');
    addTearDown(() => fixture.deleteSync(recursive: true));
    _writeScenario(fixture, scenario: 'staticSingle');

    final result = await _runParser(fixture, enforce: true);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });

  test('reports in-process command-buffer GPU timing', () async {
    final fixture = await Directory.systemTemp.createTemp('glass-benchmark-');
    addTearDown(() => fixture.deleteSync(recursive: true));
    _writeScenario(
      fixture,
      scenario: 'staticSingle',
      commandBufferGpu: <String, Object?>{
        'available': true,
        'busyMilliseconds': 300.0,
        'windowMilliseconds': 1000.0,
        'bufferCount': 120,
        'bucketMilliseconds': 100,
        'bucketBusyMilliseconds': List<double>.filled(10, 30),
      },
    );

    final result = await _runParser(fixture, enforce: true);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final summary = jsonDecode(
      File('${fixture.path}/summary.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final scenario =
        (summary['scenarioRuns'] as List<dynamic>).single
            as Map<String, dynamic>;
    final inProcessGpu = scenario['inProcessGpu'] as Map<String, dynamic>;
    expect(inProcessGpu['busyMs'], closeTo(300, 1e-9));
    expect(inProcessGpu['busyPercent'], closeTo(30, 1e-9));
    expect(inProcessGpu['bufferCount'], 120);
    // The fixture renders 30 frames, so 300 ms busy is 10 ms per frame.
    expect(inProcessGpu['gpuTimeMsPerFrame'], closeTo(10, 1e-9));
    expect(inProcessGpu['bucketBusyP95Ms'], closeTo(30, 1e-9));
    expect(scenario['inProcessGpuUnavailableReason'], isNull);
    final reliability =
        (summary['reliability'] as List<dynamic>).single
            as Map<String, dynamic>;
    expect(reliability['inProcessGpuFrameTimeMedianMs'], closeTo(10, 1e-9));
    expect(reliability['inProcessGpuBusyMedianPercent'], closeTo(30, 1e-9));
    final markdown = File('${fixture.path}/summary.md').readAsStringSync();
    expect(markdown, contains('30.0% / 10.00 ms'));
    expect(markdown, contains('GPU/frame median 10.00 ms'));
  });

  test(
    'treats runs without the in-process GPU channel as unavailable',
    () async {
      final fixture = await Directory.systemTemp.createTemp('glass-benchmark-');
      addTearDown(() => fixture.deleteSync(recursive: true));
      _writeScenario(fixture, scenario: 'staticSingle');

      final result = await _runParser(fixture, enforce: true);

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final summary = jsonDecode(
        File('${fixture.path}/summary.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final scenario =
          (summary['scenarioRuns'] as List<dynamic>).single
              as Map<String, dynamic>;
      expect(scenario['inProcessGpu'], isNull);
      expect(scenario['inProcessGpuUnavailableReason'], isNull);
      final reliability =
          (summary['reliability'] as List<dynamic>).single
              as Map<String, dynamic>;
      expect(reliability['inProcessGpuFrameTimeMedianMs'], isNull);
      expect(summary['regressionViolations'], isEmpty);
    },
  );

  test(
    'reports unavailable and degenerate in-process GPU payloads '
    'without enforcing',
    // Two parser subprocess invocations need more than the default 30 s.
    timeout: const Timeout(Duration(minutes: 3)),
    () async {
      final fixture = await Directory.systemTemp.createTemp('glass-benchmark-');
      addTearDown(() => fixture.deleteSync(recursive: true));
      _writeScenario(
        fixture,
        scenario: 'staticSingle',
        commandBufferGpu: <String, Object?>{
          'available': false,
          'reason': 'no Metal device or command queue',
        },
      );

      final result = await _runParser(fixture, enforce: true);

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final summary = jsonDecode(
        File('${fixture.path}/summary.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final scenario =
          (summary['scenarioRuns'] as List<dynamic>).single
              as Map<String, dynamic>;
      expect(scenario['inProcessGpu'], isNull);
      expect(
        scenario['inProcessGpuUnavailableReason'],
        'no Metal device or command queue',
      );
      expect(summary['regressionViolations'], isEmpty);

      // A payload that claims availability but carries no usable window is
      // degenerate: reported as unavailable, never as zero GPU time.
      _writeScenario(
        fixture,
        scenario: 'staticSingle',
        commandBufferGpu: <String, Object?>{
          'available': true,
          'busyMilliseconds': 300.0,
          'windowMilliseconds': 0.0,
        },
      );
      final degenerateResult = await _runParser(fixture, enforce: true);

      expect(
        degenerateResult.exitCode,
        0,
        reason: '${degenerateResult.stdout}\n${degenerateResult.stderr}',
      );
      final degenerateSummary = jsonDecode(
        File('${fixture.path}/summary.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final degenerateScenario =
          (degenerateSummary['scenarioRuns'] as List<dynamic>).single
              as Map<String, dynamic>;
      expect(degenerateScenario['inProcessGpu'], isNull);
      expect(
        degenerateScenario['inProcessGpuUnavailableReason'],
        contains('degenerate'),
      );
    },
  );

  test('does not report GPU data without an aligned workload window', () async {
    final fixture = await Directory.systemTemp.createTemp('glass-benchmark-');
    addTearDown(() => fixture.deleteSync(recursive: true));
    final traces = Directory('${fixture.path}/traces')..createSync();
    _writeScenario(fixture, scenario: 'staticSingle');
    File('${traces.path}/staticSingle.signposts.xml').deleteSync();
    File('${traces.path}/staticSingle.gpu.xml').writeAsStringSync(_gpuXml);

    final result = await _runParser(fixture, enforce: true);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final summary = jsonDecode(
      File('${fixture.path}/summary.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final scenario =
        (summary['scenarioRuns'] as List<dynamic>).single
            as Map<String, dynamic>;
    expect(scenario['gpu'], isNull);
    expect(
      scenario['gpuUnavailableReason'],
      contains('no validated measurement window'),
    );
    expect(summary['regressionViolations'], isEmpty);
  });

  test(
    'accepts an exported Metal table with no measured allocations',
    () async {
      final fixture = await Directory.systemTemp.createTemp('glass-benchmark-');
      addTearDown(() => fixture.deleteSync(recursive: true));
      final traces = Directory('${fixture.path}/traces')..createSync();
      _writeScenario(fixture, scenario: 'staticSingle');
      File('${traces.path}/staticSingle.gpu.xml').writeAsStringSync(_gpuXml);
      File(
        '${traces.path}/staticSingle.metal-resources.xml',
      ).writeAsStringSync(_emptyMetalXml);

      final result = await _runParser(fixture, enforce: true);

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final summary = jsonDecode(
        File('${fixture.path}/summary.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final scenario =
          (summary['scenarioRuns'] as List<dynamic>).single
              as Map<String, dynamic>;
      final metal = scenario['metal'] as Map<String, dynamic>;
      expect(metal['allocationCount'], 0);
      expect(metal['cumulativeAllocatedMb'], 0);
    },
  );

  test(
    'reports but does not enforce a trace starting after measurement',
    () async {
      final fixture = await Directory.systemTemp.createTemp('glass-benchmark-');
      addTearDown(() => fixture.deleteSync(recursive: true));
      final traces = Directory('${fixture.path}/traces')..createSync();
      _writeScenario(fixture, scenario: 'staticSingle');
      File('${traces.path}/staticSingle.gpu.xml').writeAsStringSync(_gpuXml);
      File(
        '${traces.path}/staticSingle.metal-resources.xml',
      ).writeAsStringSync(_emptyMetalXml);
      File(
        '${traces.path}/staticSingle.signposts.xml',
      ).writeAsStringSync(_shortSignpostXml);

      final result = await _runParser(fixture, enforce: true);

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final summary = jsonDecode(
        File('${fixture.path}/summary.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final scenario =
          (summary['scenarioRuns'] as List<dynamic>).single
              as Map<String, dynamic>;
      expect(scenario['gpu'], isNull);
      expect(scenario['nativeTraceMeasureSeconds'], isNull);
    },
  );

  test(
    'selects a complete adaptive interval after synthesized startup rows',
    () async {
      final fixture = await Directory.systemTemp.createTemp('glass-benchmark-');
      addTearDown(() => fixture.deleteSync(recursive: true));
      final traces = Directory('${fixture.path}/traces')..createSync();
      _writeScenario(fixture, scenario: 'staticSingle');
      File('${traces.path}/staticSingle.gpu.xml').writeAsStringSync(_gpuXml);
      File(
        '${traces.path}/staticSingle.metal-resources.xml',
      ).writeAsStringSync(_metalXml);
      File(
        '${traces.path}/staticSingle.signposts.xml',
      ).writeAsStringSync(_adaptiveSignpostXml);

      final result = await _runParser(fixture, enforce: true);

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final summary = jsonDecode(
        File('${fixture.path}/summary.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final scenario =
          (summary['scenarioRuns'] as List<dynamic>).single
              as Map<String, dynamic>;
      expect(scenario['nativeTraceMeasureSeconds'], closeTo(1, 1e-9));
    },
  );

  test('aligns logged intervals to the retained trace window', () async {
    final fixture = await Directory.systemTemp.createTemp('glass-benchmark-');
    addTearDown(() => fixture.deleteSync(recursive: true));
    final traces = Directory('${fixture.path}/traces')..createSync();
    final logs = Directory('${fixture.path}/logs')..createSync();
    _writeScenario(fixture, scenario: 'staticSingle');
    File('${traces.path}/staticSingle.signposts.xml').deleteSync();
    File('${traces.path}/staticSingle.gpu.xml').writeAsStringSync(_gpuXml);
    File(
      '${traces.path}/staticSingle.metal-resources.xml',
    ).writeAsStringSync(_emptyMetalXml);
    File('${traces.path}/staticSingle.toc.xml').writeAsStringSync(_tocXml);
    File('${logs.path}/staticSingle.trace-app.log').writeAsStringSync('''
LIQUID_GLASS_BENCHMARK_MEASURE_BEGIN:staticSingle:1789120800000000
LIQUID_GLASS_BENCHMARK_MEASURE_END:staticSingle:1789120801000000
''');

    final result = await _runParser(fixture, enforce: true);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final summary = jsonDecode(
      File('${fixture.path}/summary.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final scenario =
        (summary['scenarioRuns'] as List<dynamic>).single
            as Map<String, dynamic>;
    expect(scenario['nativeTraceMeasureSeconds'], closeTo(.75, 1e-9));
  });

  test('computes per-frame GPU time from logged window frame counts', () async {
    final fixture = await Directory.systemTemp.createTemp('glass-benchmark-');
    addTearDown(() => fixture.deleteSync(recursive: true));
    final traces = Directory('${fixture.path}/traces')..createSync();
    final logs = Directory('${fixture.path}/logs')..createSync();
    _writeScenario(fixture, scenario: 'staticSingle');
    File('${traces.path}/staticSingle.signposts.xml').deleteSync();
    File(
      '${traces.path}/staticSingle.gpu.xml',
    ).writeAsStringSync(_gpuXmlThreeFrameWindows);
    File(
      '${traces.path}/staticSingle.metal-resources.xml',
    ).writeAsStringSync(_emptyMetalXml);
    File(
      '${traces.path}/staticSingle.toc.xml',
    ).writeAsStringSync(_tocXmlTwoSeconds);
    File('${logs.path}/staticSingle.trace-app.log').writeAsStringSync('''
LIQUID_GLASS_BENCHMARK_MEASURE_BEGIN:staticSingle:1789120800000000
LIQUID_GLASS_BENCHMARK_MEASURE_END:staticSingle:1789120800500000:30
LIQUID_GLASS_BENCHMARK_MEASURE_BEGIN:staticSingle:1789120800500000
LIQUID_GLASS_BENCHMARK_MEASURE_END:staticSingle:1789120801000000:30
LIQUID_GLASS_BENCHMARK_MEASURE_BEGIN:staticSingle:1789120801000000
LIQUID_GLASS_BENCHMARK_MEASURE_END:staticSingle:1789120801500000:30
''');

    final result = await _runParser(fixture, enforce: true);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final summary = jsonDecode(
      File('${fixture.path}/summary.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final scenario =
        (summary['scenarioRuns'] as List<dynamic>).single
            as Map<String, dynamic>;
    final gpu = scenario['gpu'] as Map<String, dynamic>;
    expect(scenario['gpuUnavailableReason'], isNull);
    expect(gpu['frameCount'], 90);
    expect(gpu['busyMs'], closeTo(300, .001));
    expect(gpu['gpuTimeMsPerFrame'], closeTo(10 / 3, .001));
  });

  test('rejects a non-uniform capture with an explicit reason', () async {
    final fixture = await Directory.systemTemp.createTemp('glass-benchmark-');
    addTearDown(() => fixture.deleteSync(recursive: true));
    final traces = Directory('${fixture.path}/traces')..createSync();
    final logs = Directory('${fixture.path}/logs')..createSync();
    _writeScenario(fixture, scenario: 'staticSingle');
    File('${traces.path}/staticSingle.signposts.xml').deleteSync();
    File(
      '${traces.path}/staticSingle.gpu.xml',
    ).writeAsStringSync(_gpuXmlNonUniformCapture);
    File(
      '${traces.path}/staticSingle.metal-resources.xml',
    ).writeAsStringSync(_emptyMetalXml);
    File(
      '${traces.path}/staticSingle.toc.xml',
    ).writeAsStringSync(_tocXmlTwoSeconds);
    File('${logs.path}/staticSingle.trace-app.log').writeAsStringSync('''
LIQUID_GLASS_BENCHMARK_MEASURE_BEGIN:staticSingle:1789120800000000
LIQUID_GLASS_BENCHMARK_MEASURE_END:staticSingle:1789120800500000:30
LIQUID_GLASS_BENCHMARK_MEASURE_BEGIN:staticSingle:1789120800500000
LIQUID_GLASS_BENCHMARK_MEASURE_END:staticSingle:1789120801000000:30
LIQUID_GLASS_BENCHMARK_MEASURE_BEGIN:staticSingle:1789120801000000
LIQUID_GLASS_BENCHMARK_MEASURE_END:staticSingle:1789120801500000:30
''');

    // A rejected capture is reported, not a hard failure: the enforced run
    // still passes because raster and footprint remain within their gates.
    final result = await _runParser(fixture, enforce: true);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final summary = jsonDecode(
      File('${fixture.path}/summary.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final scenario =
        (summary['scenarioRuns'] as List<dynamic>).single
            as Map<String, dynamic>;
    expect(scenario['gpu'], isNull);
    expect(scenario['gpuUnavailableReason'], contains('capture rejected'));
    expect(
      scenario['gpuUnavailableReason'],
      contains('intervals-per-frame CV'),
    );
    final markdown = File('${fixture.path}/summary.md').readAsStringSync();
    expect(markdown, contains('GPU capture soundness'));
    expect(markdown, contains('capture rejected'));
  });

  test('rejects a capture with a starved zero-interval window', () async {
    final fixture = await Directory.systemTemp.createTemp('glass-benchmark-');
    addTearDown(() => fixture.deleteSync(recursive: true));
    final traces = Directory('${fixture.path}/traces')..createSync();
    final logs = Directory('${fixture.path}/logs')..createSync();
    _writeScenario(fixture, scenario: 'staticSingle');
    File('${traces.path}/staticSingle.signposts.xml').deleteSync();
    File(
      '${traces.path}/staticSingle.gpu.xml',
    ).writeAsStringSync(_gpuXmlStarvedWindow);
    File(
      '${traces.path}/staticSingle.metal-resources.xml',
    ).writeAsStringSync(_emptyMetalXml);
    File(
      '${traces.path}/staticSingle.toc.xml',
    ).writeAsStringSync(_tocXmlTwoSeconds);
    File('${logs.path}/staticSingle.trace-app.log').writeAsStringSync('''
LIQUID_GLASS_BENCHMARK_MEASURE_BEGIN:staticSingle:1789120800000000
LIQUID_GLASS_BENCHMARK_MEASURE_END:staticSingle:1789120800500000:30
LIQUID_GLASS_BENCHMARK_MEASURE_BEGIN:staticSingle:1789120800500000
LIQUID_GLASS_BENCHMARK_MEASURE_END:staticSingle:1789120801000000:30
LIQUID_GLASS_BENCHMARK_MEASURE_BEGIN:staticSingle:1789120801000000
LIQUID_GLASS_BENCHMARK_MEASURE_END:staticSingle:1789120801500000:30
''');

    final result = await _runParser(fixture, enforce: true);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final summary = jsonDecode(
      File('${fixture.path}/summary.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final scenario =
        (summary['scenarioRuns'] as List<dynamic>).single
            as Map<String, dynamic>;
    expect(scenario['gpu'], isNull);
    expect(
      scenario['gpuUnavailableReason'],
      contains('retained zero GPU intervals'),
    );
  });

  test('reports GPU unavailable with fewer than three windows', () async {
    final fixture = await Directory.systemTemp.createTemp('glass-benchmark-');
    addTearDown(() => fixture.deleteSync(recursive: true));
    final traces = Directory('${fixture.path}/traces')..createSync();
    final logs = Directory('${fixture.path}/logs')..createSync();
    _writeScenario(fixture, scenario: 'staticSingle');
    File('${traces.path}/staticSingle.signposts.xml').deleteSync();
    File(
      '${traces.path}/staticSingle.gpu.xml',
    ).writeAsStringSync(_gpuXmlFrameWindows);
    File(
      '${traces.path}/staticSingle.metal-resources.xml',
    ).writeAsStringSync(_emptyMetalXml);
    File(
      '${traces.path}/staticSingle.toc.xml',
    ).writeAsStringSync(_tocXmlTwoSeconds);
    File('${logs.path}/staticSingle.trace-app.log').writeAsStringSync('''
LIQUID_GLASS_BENCHMARK_MEASURE_BEGIN:staticSingle:1789120800000000
LIQUID_GLASS_BENCHMARK_MEASURE_END:staticSingle:1789120800500000:30
LIQUID_GLASS_BENCHMARK_MEASURE_BEGIN:staticSingle:1789120800500000
LIQUID_GLASS_BENCHMARK_MEASURE_END:staticSingle:1789120801000000:30
''');

    final result = await _runParser(fixture, enforce: true);

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final summary = jsonDecode(
      File('${fixture.path}/summary.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final scenario =
        (summary['scenarioRuns'] as List<dynamic>).single
            as Map<String, dynamic>;
    expect(scenario['gpu'], isNull);
    expect(
      scenario['gpuUnavailableReason'],
      contains('at least 3 are required'),
    );
  });

  test(
    'never enforces GPU for rejected captures while raster and footprint '
    'gates still evaluate',
    // Two parser subprocess invocations need more than the default 30 s.
    timeout: const Timeout(Duration(minutes: 3)),
    () async {
      final fixture = await Directory.systemTemp.createTemp('glass-benchmark-');
      addTearDown(() => fixture.deleteSync(recursive: true));
      final traces = Directory('${fixture.path}/traces')..createSync();
      final logs = Directory('${fixture.path}/logs')..createSync();
      for (var repetition = 1; repetition <= 3; repetition++) {
        final runKey = 'staticSingle.r$repetition';
        _writeScenario(
          fixture,
          scenario: 'staticSingle',
          repetition: repetition,
          runKey: runKey,
        );
        File(
          '${traces.path}/$runKey.gpu.xml',
        ).writeAsStringSync(_gpuXmlNonUniformCapture);
        File(
          '${traces.path}/$runKey.metal-resources.xml',
        ).writeAsStringSync(_emptyMetalXml);
        File(
          '${traces.path}/$runKey.toc.xml',
        ).writeAsStringSync(_tocXmlTwoSeconds);
        File('${logs.path}/$runKey.trace-app.log').writeAsStringSync('''
LIQUID_GLASS_BENCHMARK_MEASURE_BEGIN:staticSingle:1789120800000000
LIQUID_GLASS_BENCHMARK_MEASURE_END:staticSingle:1789120800500000:30
LIQUID_GLASS_BENCHMARK_MEASURE_BEGIN:staticSingle:1789120800500000
LIQUID_GLASS_BENCHMARK_MEASURE_END:staticSingle:1789120801000000:30
LIQUID_GLASS_BENCHMARK_MEASURE_BEGIN:staticSingle:1789120801000000
LIQUID_GLASS_BENCHMARK_MEASURE_END:staticSingle:1789120801500000:30
''');
      }

      final result = await _runParser(fixture, enforce: true);

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final summary = jsonDecode(
        File('${fixture.path}/summary.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final violations = (summary['regressionViolations'] as List<dynamic>)
          .cast<String>();
      expect(violations, isEmpty, reason: violations.join('\n'));
      final markdown = File('${fixture.path}/summary.md').readAsStringSync();
      expect(markdown, contains('capture rejected in 3/3 runs'));

      // The raster CV gate still evaluates for the same rejected captures.
      for (var repetition = 1; repetition <= 3; repetition++) {
        final report = jsonDecode(
          File(
            '${fixture.path}/staticSingle.r$repetition.json',
          ).readAsStringSync(),
        ) as Map<String, dynamic>;
        final frames = (report['frames'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        for (final frame in frames) {
          frame['rasterMicros'] =
              1000 * (1 + repetition); // CV ~16% across repetitions
        }
        File(
          '${fixture.path}/staticSingle.r$repetition.json',
        ).writeAsStringSync(jsonEncode(report));
      }

      final rasterResult = await _runParser(fixture, enforce: true);

      expect(rasterResult.exitCode, 1);
      expect(rasterResult.stderr, contains('not repeatable enough'));
      expect(rasterResult.stderr, isNot(contains('GPU')));
    },
  );

  test(
    'reports memory-unstable scenarios as informational without failing',
    () async {
      final fixture = await Directory.systemTemp.createTemp('glass-benchmark-');
      addTearDown(() => fixture.deleteSync(recursive: true));
      _writeScenario(fixture, scenario: 'staticSingle');
      _writeScenario(fixture, scenario: 'baselineMotion');
      // Schema version >= 4 opts into stability metadata; mark both
      // stability flags false to emulate the flaky cooldown path.
      final reportFile = File('${fixture.path}/staticSingle.json');
      final report =
          jsonDecode(reportFile.readAsStringSync()) as Map<String, dynamic>;
      report['schemaVersion'] = 4;
      report['preMeasureMemoryStable'] = false;
      report['preMeasureMemorySlopeMbPerSecond'] = 3.5;
      report['cooldownMemoryStable'] = false;
      report['cooldownMemorySlopeMbPerSecond'] = -4.25;
      reportFile.writeAsStringSync(jsonEncode(report));

      final result = await _runParser(fixture, enforce: true);

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final summary = jsonDecode(
        File('${fixture.path}/summary.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      // Both scenarios are summarized: an unstable run does not abort or
      // suppress the remaining scenarios.
      expect(summary['scenarioRuns'], hasLength(2));
      expect(summary['regressionViolations'], isEmpty);
      final scenario = (summary['scenarioRuns'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .firstWhere((run) => run['scenario'] == 'staticSingle');
      expect(scenario['nativeFootprintPreMeasureStable'], isFalse);
      expect(scenario['nativeFootprintCooldownStable'], isFalse);
      final markdown = File('${fixture.path}/summary.md').readAsStringSync();
      expect(markdown, contains('Memory stability (informational)'));
      expect(markdown, contains('pre-measurement footprint not stable'));
      expect(markdown, contains('cooldown footprint did not settle'));
    },
  );

  test('records harness-reported scenario failures in the summary', () async {
    final fixture = await Directory.systemTemp.createTemp('glass-benchmark-');
    addTearDown(() => fixture.deleteSync(recursive: true));
    final failures = Directory('${fixture.path}/failures')..createSync();
    _writeScenario(fixture, scenario: 'staticSingle');
    File(
      '${failures.path}/independent16Motion.r2.txt',
    ).writeAsStringSync('frame/memory pass failed in two fresh processes');

    final result = await _runParser(fixture, enforce: true);

    expect(result.exitCode, 1);
    expect(result.stderr, contains('independent16Motion r2 failed'));
    final summary = jsonDecode(
      File('${fixture.path}/summary.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final failedRuns = (summary['failedRuns'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(failedRuns, hasLength(1));
    expect(failedRuns.single['scenario'], 'independent16Motion');
    expect(failedRuns.single['repetition'], 2);
    expect(
      failedRuns.single['reason'],
      contains('frame/memory pass failed'),
    );
    final markdown = File('${fixture.path}/summary.md').readAsStringSync();
    expect(markdown, contains('Scenario failures'));
  });
}

Future<ProcessResult> _runParser(
  Directory fixture, {
  required bool enforce,
}) => Process.run(
  _dartExecutable,
  [
    'run',
    'tool/parse_benchmark_results.dart',
    '--input',
    fixture.path,
    '--markdown',
    '${fixture.path}/summary.md',
    '--json',
    '${fixture.path}/summary.json',
    '--enforce',
    '$enforce',
  ],
  workingDirectory: Directory.current.path,
);

String get _dartExecutable {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  return flutterRoot == null ? 'dart' : '$flutterRoot/bin/dart';
}

void _writeScenario(
  Directory fixture, {
  required String scenario,
  int repetition = 1,
  String? runKey,
  Map<String, Object?>? commandBufferGpu,
}) {
  const mb = 1048576;
  final report = <String, Object?>{
    'schemaVersion': commandBufferGpu == null ? 2 : 5,
    'scenario': scenario,
    'repetition': repetition,
    'measureSeconds': 1,
    if (commandBufferGpu != null) 'commandBufferGpu': commandBufferGpu,
    'frames': List.generate(
      30,
      (_) => <String, int>{
        'buildMicros': 500,
        'rasterMicros': 1000,
        'totalMicros': 2000,
      },
    ),
    'nativeMemory': List.generate(
      10,
      (index) => <String, int>{
        'timestampMicros': index * 100000,
        'physicalFootprintBytes': (100 + index * 40 ~/ 9) * mb,
        'residentBytes': 80 * mb,
      },
    ),
    'preMeasureNativeMemory': <String, int>{
      'timestampMicros': -1,
      'physicalFootprintBytes': 100 * mb,
    },
    'settledNativeMemory': <String, int>{
      'timestampMicros': 1100000,
      'physicalFootprintBytes': 110 * mb,
    },
  };
  final key = runKey ?? scenario;
  File('${fixture.path}/$key.json').writeAsStringSync(jsonEncode(report));
  final traces = Directory('${fixture.path}/traces')..createSync();
  File(
    '${traces.path}/$key.signposts.xml',
  ).writeAsStringSync(_signpostXml);
}

const _gpuXml = '''
<trace-query-result>
  <process id="1" fmt="liquid_glass_renderer_example (42)"></process>
  <start-time id="10">0</start-time>
  <duration id="20">100000000</duration>
  <row><start-time ref="10"/><duration ref="20"/><process ref="1"/></row>
  <row><start-time>50000000</start-time><duration ref="20"/><process ref="1"/></row>
  <row><start-time>900000000</start-time><duration>50000000</duration><process ref="1"/></row>
</trace-query-result>
''';

// Rolling-window clipping can corrupt a row into a negative duration, which
// xctrace exports as a wrapped unsigned 64-bit integer (observed in a real
// independent16Motion Metal System Trace). The parser must reinterpret the
// value as two's-complement signed and exclude the row from the union.
const _gpuXmlWithWrappedDuration = '''
<trace-query-result>
  <process id="1" fmt="liquid_glass_renderer_example (42)"></process>
  <start-time id="10">0</start-time>
  <duration id="20">100000000</duration>
  <duration id="21" fmt="307445734.56 min">18446744073709540491</duration>
  <row><start-time ref="10"/><duration ref="20"/><process ref="1"/></row>
  <row><start-time>50000000</start-time><duration ref="20"/><process ref="1"/></row>
  <row><start-time>900000000</start-time><duration>50000000</duration><process ref="1"/></row>
  <row><start-time>200000000</start-time><duration ref="21"/><process ref="1"/></row>
  <row><start-time>300000000</start-time><duration>18446744073709540491</duration><process ref="1"/></row>
</trace-query-result>
''';

// A metal-gpu-intervals row carries two duration-typed columns in schema
// order: the interval's own Duration first, then the CPU-to-GPU start
// latency. When the real duration is exported as a shared reference while
// the latency is inline, a value-first search would read the latency
// (observed inflating independent16Motion to a false 100% GPU busy).
const _gpuXmlWithLatencyColumn = '''
<trace-query-result>
  <process id="1" fmt="liquid_glass_renderer_example (42)"></process>
  <start-time id="10">0</start-time>
  <duration id="20">100000000</duration>
  <duration id="30" fmt="507.54 ms">507543792</duration>
  <row><start-time ref="10"/><duration ref="20"/><gpu-frame-number>1</gpu-frame-number><duration id="31" fmt="507.54 ms">507543792</duration><process ref="1"/></row>
  <row><start-time>50000000</start-time><duration ref="20"/><duration>300000000</duration><process ref="1"/></row>
  <row><start-time>900000000</start-time><duration>50000000</duration><duration ref="30"/><process ref="1"/></row>
</trace-query-result>
''';

const _twoWindowSignpostXml = '''
<trace-query-result>
  <schema name="os-signpost"></schema>
  <process id="7" fmt="liquid_glass_renderer_example (42)"></process>
  <row><event-time id="1">0</event-time><process ref="7"/><event-type id="2">Begin</event-type><os-signpost-identifier id="3">42</os-signpost-identifier><signpost-name id="4">LiquidGlassBenchmark</signpost-name><subsystem id="5">com.example.liquidGlassRenderer</subsystem><os-log-metadata id="6" fmt="staticSingle"></os-log-metadata></row>
  <row><event-time>1000000000</event-time><process ref="7"/><event-type>End</event-type><os-signpost-identifier ref="3"/><signpost-name ref="4"/><subsystem ref="5"/><os-log-metadata ref="6"/></row>
  <row><event-time>1000000000</event-time><process ref="7"/><event-type>Begin</event-type><os-signpost-identifier>43</os-signpost-identifier><signpost-name ref="4"/><subsystem ref="5"/><os-log-metadata ref="6"/></row>
  <row><event-time>2000000000</event-time><process ref="7"/><event-type>End</event-type><os-signpost-identifier>43</os-signpost-identifier><signpost-name ref="4"/><subsystem ref="5"/><os-log-metadata ref="6"/></row>
</trace-query-result>
''';

const _gpuXmlTwoWindows = '''
<trace-query-result>
  <process id="1" fmt="liquid_glass_renderer_example (42)"></process>
  <start-time id="10">0</start-time>
  <duration id="20">100000000</duration>
  <row><start-time ref="10"/><duration ref="20"/><process ref="1"/></row>
  <row><start-time>1500000000</start-time><duration>200000000</duration><process ref="1"/></row>
</trace-query-result>
''';

const _gpuXmlFrameWindows = '''
<trace-query-result>
  <process id="1" fmt="liquid_glass_renderer_example (42)"></process>
  <start-time id="10">0</start-time>
  <duration id="20">100000000</duration>
  <row><start-time ref="10"/><duration ref="20"/><process ref="1"/></row>
  <row><start-time>500000000</start-time><duration>200000000</duration><process ref="1"/></row>
</trace-query-result>
''';

// One 100 ms interval in each of three half-second windows: a perfectly
// uniform capture that passes the intervals-per-frame uniformity check.
const _gpuXmlThreeFrameWindows = '''
<trace-query-result>
  <process id="1" fmt="liquid_glass_renderer_example (42)"></process>
  <start-time id="10">0</start-time>
  <duration id="20">100000000</duration>
  <row><start-time ref="10"/><duration ref="20"/><process ref="1"/></row>
  <row><start-time>500000000</start-time><duration ref="20"/><process ref="1"/></row>
  <row><start-time>1000000000</start-time><duration ref="20"/><process ref="1"/></row>
</trace-query-result>
''';

// One interval in the first two windows but a ten-interval burst in the
// third: intervals-per-frame CV ~1.3, the signature of silent kdebug event
// loss in the earlier windows (observed on saturated real captures).
const _gpuXmlNonUniformCapture = '''
<trace-query-result>
  <process id="1" fmt="liquid_glass_renderer_example (42)"></process>
  <start-time id="10">0</start-time>
  <duration id="20">100000000</duration>
  <row><start-time ref="10"/><duration ref="20"/><process ref="1"/></row>
  <row><start-time>500000000</start-time><duration ref="20"/><process ref="1"/></row>
  <row><start-time>1000000000</start-time><duration ref="20"/><process ref="1"/></row>
  <row><start-time>1050000000</start-time><duration ref="20"/><process ref="1"/></row>
  <row><start-time>1100000000</start-time><duration ref="20"/><process ref="1"/></row>
  <row><start-time>1150000000</start-time><duration ref="20"/><process ref="1"/></row>
  <row><start-time>1200000000</start-time><duration ref="20"/><process ref="1"/></row>
  <row><start-time>1250000000</start-time><duration ref="20"/><process ref="1"/></row>
  <row><start-time>1300000000</start-time><duration ref="20"/><process ref="1"/></row>
  <row><start-time>1350000000</start-time><duration ref="20"/><process ref="1"/></row>
  <row><start-time>1400000000</start-time><duration ref="20"/><process ref="1"/></row>
  <row><start-time>1450000000</start-time><duration ref="20"/><process ref="1"/></row>
</trace-query-result>
''';

// The third window retains no intervals at all while the first two do: the
// kdebug buffer starved mid-recording, so the capture is rejected outright.
const _gpuXmlStarvedWindow = '''
<trace-query-result>
  <process id="1" fmt="liquid_glass_renderer_example (42)"></process>
  <start-time id="10">0</start-time>
  <duration id="20">100000000</duration>
  <row><start-time ref="10"/><duration ref="20"/><process ref="1"/></row>
  <row><start-time>500000000</start-time><duration ref="20"/><process ref="1"/></row>
</trace-query-result>
''';

const _tocXmlTwoSeconds = '''
<trace-toc>
  <run number="1">
    <info>
      <start-date>2026-09-11T10:00:00.000Z</start-date>
      <duration>2</duration>
      <target>
        <process type="attached" name="liquid_glass_renderer_example" pid="42"/>
      </target>
    </info>
  </run>
</trace-toc>
''';

const _metalXml = '''
<trace-query-result>
  <schema name="metal-resource-allocations"></schema>
  <process id="1" fmt="liquid_glass_renderer_example (42)"></process>
  <gpu-memory-event-name id="10">Allocation</gpu-memory-event-name>
  <gpu-memory-event-name id="11">Deallocation</gpu-memory-event-name>
  <size-in-bytes id="20">100</size-in-bytes>
  <row><start-time>100000000</start-time><process ref="1"/><gpu-memory-event-name ref="10"/><size-in-bytes ref="20"/></row>
  <row><start-time>200000000</start-time><process ref="1"/><gpu-memory-event-name>Allocation</gpu-memory-event-name><size-in-bytes>50</size-in-bytes></row>
  <row><start-time>300000000</start-time><process ref="1"/><gpu-memory-event-name ref="11"/><size-in-bytes ref="20"/></row>
</trace-query-result>
''';

const _emptyMetalXml = '''
<trace-query-result>
  <node><schema name="metal-resource-allocations"></schema></node>
</trace-query-result>
''';

const _signpostXml = '''
<trace-query-result>
  <schema name="os-signpost"></schema>
  <process id="7" fmt="liquid_glass_renderer_example (42)"></process>
  <row><event-time id="1">0</event-time><process ref="7"/><event-type id="2">Begin</event-type><os-signpost-identifier id="3">42</os-signpost-identifier><signpost-name id="4">LiquidGlassBenchmark</signpost-name><subsystem id="5">com.example.liquidGlassRenderer</subsystem><os-log-metadata id="6" fmt="staticSingle"></os-log-metadata></row>
  <row><event-time>1000000000</event-time><process ref="7"/><event-type>End</event-type><os-signpost-identifier ref="3"/><signpost-name ref="4"/><subsystem ref="5"/><os-log-metadata ref="6"/></row>
</trace-query-result>
''';

const _shortSignpostXml = '''
<trace-query-result>
  <schema name="os-signpost"></schema>
  <process id="7" fmt="liquid_glass_renderer_example (42)"></process>
  <row><event-time id="1">0</event-time><process ref="7"/><event-type id="2">Begin</event-type><os-signpost-identifier id="3">42</os-signpost-identifier><signpost-name id="4">LiquidGlassBenchmark</signpost-name><subsystem id="5">com.example.liquidGlassRenderer</subsystem><os-log-metadata id="6" fmt="staticSingle"></os-log-metadata></row>
  <row><event-time>180000000</event-time><process ref="7"/><event-type>End</event-type><os-signpost-identifier ref="3"/><signpost-name ref="4"/><subsystem ref="5"/><os-log-metadata ref="6"/></row>
</trace-query-result>
''';

const _adaptiveSignpostXml = '''
<trace-query-result>
  <schema name="os-signpost"></schema>
  <process id="7" fmt="liquid_glass_renderer_example (42)"></process>
  <row><event-time id="1">0</event-time><process ref="7"/><event-type id="2">Begin</event-type><os-signpost-identifier id="3">41</os-signpost-identifier><signpost-name id="4">LiquidGlassBenchmark</signpost-name><subsystem id="5">com.example.liquidGlassRenderer</subsystem><os-log-metadata id="6" fmt="staticSingle"></os-log-metadata></row>
  <row><event-time>180000000</event-time><process ref="7"/><event-type>End</event-type><os-signpost-identifier ref="3"/><signpost-name ref="4"/><subsystem ref="5"/><os-log-metadata ref="6"/></row>
  <row><event-time>0</event-time><process ref="7"/><event-type>Begin</event-type><os-signpost-identifier>42</os-signpost-identifier><signpost-name ref="4"/><subsystem ref="5"/><os-log-metadata ref="6"/></row>
  <row><event-time>1000000000</event-time><process ref="7"/><event-type>End</event-type><os-signpost-identifier>42</os-signpost-identifier><signpost-name ref="4"/><subsystem ref="5"/><os-log-metadata ref="6"/></row>
</trace-query-result>
''';

const _tocXml = '''
<trace-toc>
  <run number="1">
    <info>
      <start-date>2026-09-11T10:00:00.250Z</start-date>
      <duration>0.75</duration>
      <target>
        <process type="attached" name="liquid_glass_renderer_example" pid="42"/>
      </target>
    </info>
  </run>
</trace-toc>
''';

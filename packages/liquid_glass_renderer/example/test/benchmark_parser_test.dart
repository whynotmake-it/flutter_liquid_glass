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
    final summary =
        jsonDecode(
              File('${fixture.path}/summary.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
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

  test('enforced parsing rejects missing native Instruments tables', () async {
    final fixture = await Directory.systemTemp.createTemp('glass-benchmark-');
    addTearDown(() => fixture.deleteSync(recursive: true));
    _writeScenario(fixture, scenario: 'staticSingle');

    final result = await _runParser(fixture, enforce: true);

    expect(result.exitCode, 1);
    expect(result.stderr, contains('missing process-filtered Metal GPU'));
    expect(result.stderr, contains('missing the Metal resource allocation'));
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
      final summary =
          jsonDecode(File('${fixture.path}/summary.json').readAsStringSync())
              as Map<String, dynamic>;
      final scenario =
          (summary['scenarioRuns'] as List<dynamic>).single
              as Map<String, dynamic>;
      final metal = scenario['metal'] as Map<String, dynamic>;
      expect(metal['allocationCount'], 0);
      expect(metal['cumulativeAllocatedMb'], 0);
    },
  );

  test('rejects a trace that starts after the measurement interval', () async {
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

    expect(result.exitCode, 1);
    expect(result.stderr, contains('native trace captured 0.18 s'));
  });

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
      final summary =
          jsonDecode(File('${fixture.path}/summary.json').readAsStringSync())
              as Map<String, dynamic>;
      final scenario =
          (summary['scenarioRuns'] as List<dynamic>).single
              as Map<String, dynamic>;
      expect(scenario['nativeTraceMeasureSeconds'], closeTo(1, 1e-9));
    },
  );
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

void _writeScenario(Directory fixture, {required String scenario}) {
  const mb = 1048576;
  final report = <String, Object?>{
    'schemaVersion': 2,
    'scenario': scenario,
    'measureSeconds': 1,
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
  File('${fixture.path}/$scenario.json').writeAsStringSync(jsonEncode(report));
  final traces = Directory('${fixture.path}/traces')..createSync();
  File(
    '${traces.path}/$scenario.signposts.xml',
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

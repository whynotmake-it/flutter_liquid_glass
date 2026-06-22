import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

void main(List<String> arguments) {
  final options = _options(arguments);
  final input = Directory(options['input'] ?? 'build/benchmark');
  final reports =
      input
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .where((file) => !file.path.endsWith('summary.json'))
          .map((file) => _readReport(file, input))
          .toList()
        ..sort((a, b) => a.scenario.compareTo(b.scenario));
  if (reports.isEmpty) throw StateError('No benchmark scenario reports found.');

  final baseline = reports
      .where((report) => report.scenario == 'baselineMotion')
      .firstOrNull;
  final fakeBaseline = reports
      .where((report) => report.scenario == 'fakeStatic')
      .firstOrNull;
  final violations = _violations(reports);
  final summary = <String, Object?>{
    'schemaVersion': 1,
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'host': <String, Object?>{
      'os': Platform.operatingSystemVersion,
      'processors': Platform.numberOfProcessors,
    },
    'scenarios': reports
        .map(
          (report) => report.toJson(
            report.scenario.startsWith('fake') ? fakeBaseline : baseline,
          ),
        )
        .toList(),
    'regressionViolations': violations,
  };

  final markdown = _markdown(reports, baseline, fakeBaseline, violations);
  File(options['json'] ?? '${input.path}/summary.json')
    ..createSync(recursive: true)
    ..writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(summary)}\n',
    );
  File(options['markdown'] ?? '${input.path}/summary.md')
    ..createSync(recursive: true)
    ..writeAsStringSync(markdown);

  if (Platform.environment['GITHUB_OUTPUT'] case final output?) {
    File(output).writeAsStringSync(
      'summary<<LIQUID_GLASS_EOF\n$markdown\nLIQUID_GLASS_EOF\n',
      mode: FileMode.append,
    );
  }
  if (options['enforce'] == 'true' && violations.isNotEmpty) {
    stderr.writeln('Benchmark regression thresholds failed:');
    for (final violation in violations) stderr.writeln('- $violation');
    exitCode = 1;
  }
}

Map<String, String> _options(List<String> args) {
  final result = <String, String>{};
  for (var i = 0; i < args.length; i += 2) {
    if (!args[i].startsWith('--') || i + 1 >= args.length) {
      throw FormatException('Expected --name value arguments.');
    }
    result[args[i].substring(2)] = args[i + 1];
  }
  return result;
}

_Report _readReport(File file, Directory input) {
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final frames = (json['frames'] as List<dynamic>).cast<Map<String, dynamic>>();
  final memory = (json['nativeMemory'] as List<dynamic>)
      .cast<Map<String, dynamic>>();
  return _Report(
    scenario: json['scenario'] as String,
    frameBuildMs: frames.map((f) => (f['buildMicros'] as num) / 1000).toList(),
    frameRasterMs: frames
        .map((f) => (f['rasterMicros'] as num) / 1000)
        .toList(),
    frameTotalMs: frames.map((f) => (f['totalMicros'] as num) / 1000).toList(),
    footprintMb: memory
        .where((m) => m['physicalFootprintBytes'] is num)
        .map((m) => (m['physicalFootprintBytes'] as num) / 1048576)
        .toList(),
    residentMb: memory
        .where((m) => m['residentBytes'] is num)
        .map((m) => (m['residentBytes'] as num) / 1048576)
        .toList(),
    gpu: _readGpuIntervals(
      File('${input.path}/traces/${json['scenario']}.gpu.xml'),
    ),
  );
}

_GpuMetrics? _readGpuIntervals(File file) {
  if (!file.existsSync()) return null;
  final xml = file.readAsStringSync();
  final processMatch = RegExp(
    r'<process id="(\d+)" fmt="liquid_glass_renderer_example \(\d+\)">',
  ).firstMatch(xml);
  if (processMatch == null) return null;
  final processId = processMatch.group(1)!;

  final durations = <String, int>{
    for (final match in RegExp(
      r'<duration id="(\d+)"[^>]*>(\d+)</duration>',
    ).allMatches(xml))
      match.group(1)!: int.parse(match.group(2)!),
  };
  final starts = <String, int>{
    for (final match in RegExp(
      r'<start-time id="(\d+)"[^>]*>(\d+)</start-time>',
    ).allMatches(xml))
      match.group(1)!: int.parse(match.group(2)!),
  };
  final intervals = <(int, int)>[];
  for (final match in RegExp(
    r'<row>(.*?)</row>',
    dotAll: true,
  ).allMatches(xml)) {
    final row = match.group(1)!;
    if (!row.contains('<process ref="$processId"/>') &&
        !row.contains('<process id="$processId" ')) {
      continue;
    }
    final start = _valueOrReference(row, 'start-time', starts);
    final duration = _valueOrReference(row, 'duration', durations);
    if (start != null && duration != null)
      intervals.add((start, start + duration));
  }
  if (intervals.isEmpty) return null;
  intervals.sort((a, b) => a.$1.compareTo(b.$1));
  var unionNanos = 0;
  var start = intervals.first.$1;
  var end = intervals.first.$2;
  for (final interval in intervals.skip(1)) {
    if (interval.$1 <= end) {
      end = math.max(end, interval.$2);
    } else {
      unionNanos += end - start;
      start = interval.$1;
      end = interval.$2;
    }
  }
  unionNanos += end - start;
  final spanNanos = intervals.last.$2 - intervals.first.$1;
  return _GpuMetrics(
    intervalCount: intervals.length,
    busyMs: unionNanos / 1000000,
    observedSpanMs: spanNanos / 1000000,
  );
}

int? _valueOrReference(String row, String tag, Map<String, int> references) {
  final value = RegExp(
    '<$tag(?: id="\\d+")?[^>]*>(\\d+)</$tag>',
  ).firstMatch(row);
  if (value != null) return int.parse(value.group(1)!);
  final reference = RegExp('<$tag ref="(\\d+)"/>').firstMatch(row);
  return reference == null ? null : references[reference.group(1)];
}

String _markdown(
  List<_Report> reports,
  _Report? baseline,
  _Report? fakeBaseline,
  List<String> violations,
) {
  final out = StringBuffer()
    ..writeln('## Liquid Glass native performance')
    ..writeln()
    ..writeln(
      '| Scenario | Frames | Raster p95 / p99 | Total p95 | GPU busy | Footprint peak | Peak over median | Retained delta | Max sample step |',
    )
    ..writeln('|---|---:|---:|---:|---:|---:|---:|---:|---:|');
  for (final report in reports) {
    out.writeln(
      '| `${report.scenario}` | ${report.frameTotalMs.length} | ${_ms(report.p95Raster)} / ${_ms(report.p99Raster)} | ${_ms(report.p95Total)} | ${report.gpu == null ? 'unavailable' : '${report.gpu!.utilizationPercent.toStringAsFixed(1)}%'} | ${_mb(report.peakFootprint)} | ${_mb(report.peakAboveMedian)} | ${_signedMb(report.retainedFootprintDelta)} | ${_signedMb(report.maxFootprintStep)} |',
    );
  }
  out
    ..writeln()
    ..writeln('### Attribution signals')
    ..writeln();
  if (baseline != null) {
    for (final report in reports.where(
      (r) => r != baseline && r != fakeBaseline,
    )) {
      final comparison = report.scenario.startsWith('fake')
          ? fakeBaseline
          : baseline;
      if (comparison == null) continue;
      final rasterDelta = report.p95Raster - comparison.p95Raster;
      final memoryDelta = report.peakFootprint - comparison.peakFootprint;
      final gpuDelta = report.gpu != null && comparison.gpu != null
          ? report.gpu!.utilizationPercent - comparison.gpu!.utilizationPercent
          : null;
      out.writeln(
        '- `${report.scenario}`: raster p95 ${_signedMs(rasterDelta)}, GPU busy ${gpuDelta == null ? 'unavailable' : '${gpuDelta >= 0 ? '+' : ''}${gpuDelta.toStringAsFixed(1)} points'}, and peak native footprint ${_signedMb(memoryDelta)} versus `${comparison.scenario}`.',
      );
    }
  }
  out
    ..writeln(
      '- `resizeChurn` isolates ordinary render-target reallocation, while `largeResize` amplifies it. Large sample steps identify allocation events; retained delta distinguishes transient peaks from resources that remain resident.',
    )
    ..writeln(
      '- `layerChurn` isolates layer/renderer lifetime; growth without matching resize growth points to lifecycle retention.',
    )
    ..writeln(
      '- `translatedSingle` versus `scaledRotatedSingle` separates ordinary geometry invalidation from transform-specific work and correctness risk.',
    )
    ..writeln(
      '- `largeStatic` measures steady-state cost of a 2048×2048 matte. `fakeStatic` and `fakeLarge` run on Skia and isolate the public FakeGlass path from Flutter GPU and Impeller.',
    )
    ..writeln(
      '- `.trace` artifacts contain the signposted measurement interval for Metal System Trace inspection. Missing traces are reported in the adjacent `.xctrace.log`; do not treat unavailable GPU counters as zero.',
    )
    ..writeln()
    ..writeln(
      '_Memory is Mach `phys_footprint`, not Dart heap. Percentiles are per-frame Flutter engine timings from profile-mode Impeller runs._',
    );
  out
    ..writeln()
    ..writeln('### Regression gates')
    ..writeln();
  if (violations.isEmpty) {
    out.writeln(
      '- Passed: p99 raster, retained footprint, and allocation-step limits.',
    );
  } else {
    for (final violation in violations) out.writeln('- ❌ $violation');
  }
  return out.toString();
}

List<String> _violations(List<_Report> reports) {
  final violations = <String>[];
  for (final report in reports) {
    if ({'largeResize', 'largeStatic', 'fakeLarge'}.contains(report.scenario) &&
        report.p99Raster > 16.67) {
      violations.add(
        '${report.scenario} raster p99 ${_ms(report.p99Raster)} exceeds the 16.67 ms frame budget.',
      );
    }
    if ({'largeResize', 'largeStatic', 'fakeLarge'}.contains(report.scenario) &&
        report.retainedFootprintDelta > 64) {
      violations.add(
        '${report.scenario} retained ${_mb(report.retainedFootprintDelta)}; limit is 64 MB.',
      );
    }
    if (report.scenario == 'largeResize' && report.maxFootprintStep > 64) {
      violations.add(
        'largeResize allocated ${_mb(report.maxFootprintStep)} in one sample; limit is 64 MB.',
      );
    }
  }
  return violations;
}

String _ms(double value) => '${value.toStringAsFixed(2)} ms';
String _mb(double value) => '${value.toStringAsFixed(1)} MB';
String _signedMs(double value) =>
    '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)} ms';
String _signedMb(double value) =>
    '${value >= 0 ? '+' : ''}${value.toStringAsFixed(1)} MB';

class _Report {
  _Report({
    required this.scenario,
    required this.frameBuildMs,
    required this.frameRasterMs,
    required this.frameTotalMs,
    required this.footprintMb,
    required this.residentMb,
    required this.gpu,
  });
  final String scenario;
  final List<double> frameBuildMs;
  final List<double> frameRasterMs;
  final List<double> frameTotalMs;
  final List<double> footprintMb;
  final List<double> residentMb;
  final _GpuMetrics? gpu;

  double get p95Build => _percentile(frameBuildMs, .95);
  double get p95Raster => _percentile(frameRasterMs, .95);
  double get p99Raster => _percentile(frameRasterMs, .99);
  double get p95Total => _percentile(frameTotalMs, .95);
  double get peakFootprint =>
      footprintMb.isEmpty ? 0 : footprintMb.reduce(math.max);
  double get medianFootprint => _percentile(footprintMb, .5);
  double get peakAboveMedian => peakFootprint - medianFootprint;
  double get retainedFootprintDelta {
    if (footprintMb.length < 4) return 0;
    final window = math.max(2, footprintMb.length ~/ 5);
    return _median(footprintMb.sublist(footprintMb.length - window)) -
        _median(footprintMb.sublist(0, window));
  }

  double get maxFootprintStep {
    var result = 0.0;
    for (var i = 1; i < footprintMb.length; i++) {
      result = math.max(result, footprintMb[i] - footprintMb[i - 1]);
    }
    return result;
  }

  Map<String, Object?> toJson(_Report? baseline) => <String, Object?>{
    'scenario': scenario,
    'frameCount': frameTotalMs.length,
    'buildP95Ms': p95Build,
    'rasterP95Ms': p95Raster,
    'rasterP99Ms': p99Raster,
    'totalP95Ms': p95Total,
    'nativeFootprintPeakMb': peakFootprint,
    'nativeFootprintMedianMb': medianFootprint,
    'nativeFootprintPeakAboveMedianMb': peakAboveMedian,
    'nativeFootprintRetainedDeltaMb': retainedFootprintDelta,
    'nativeFootprintMaxSampleStepMb': maxFootprintStep,
    'gpu': gpu?.toJson(),
    if (baseline != null && baseline != this)
      'versusBaseline': <String, double>{
        'rasterP95DeltaMs': p95Raster - baseline.p95Raster,
        'nativeFootprintPeakDeltaMb': peakFootprint - baseline.peakFootprint,
      },
  };
}

class _GpuMetrics {
  const _GpuMetrics({
    required this.intervalCount,
    required this.busyMs,
    required this.observedSpanMs,
  });
  final int intervalCount;
  final double busyMs;
  final double observedSpanMs;
  double get utilizationPercent =>
      observedSpanMs == 0 ? 0 : busyMs / observedSpanMs * 100;
  Map<String, Object?> toJson() => <String, Object?>{
    'intervalCount': intervalCount,
    'busyMs': busyMs,
    'observedSpanMs': observedSpanMs,
    'utilizationPercent': utilizationPercent,
  };
}

double _percentile(List<double> values, double percentile) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  return sorted[((sorted.length - 1) * percentile).round()];
}

double _median(List<double> values) => _percentile(values, .5);

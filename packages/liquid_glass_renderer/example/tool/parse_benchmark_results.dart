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
  final minimumRepetitions = int.parse(options['minimum-repetitions'] ?? '1');
  final violations = _violations(
    reports,
    minimumRepetitions: minimumRepetitions,
  );
  final summary = <String, Object?>{
    'schemaVersion': 1,
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'host': <String, Object?>{
      'os': Platform.operatingSystemVersion,
      'processors': Platform.numberOfProcessors,
    },
    'scenarioRuns': reports.map(
      (report) {
        final baselineName = report.scenario.startsWith('fake')
            ? 'fakeStatic'
            : 'baselineMotion';
        final matchedBaseline = reports
            .where(
              (candidate) =>
                  candidate.scenario == baselineName &&
                  candidate.repetition == report.repetition,
            )
            .firstOrNull;
        return report.toJson(matchedBaseline);
      },
    ).toList(),
    'reliability': _reliability(reports),
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
  final schemaVersion = (json['schemaVersion'] as num?)?.toInt() ?? 0;
  final runKey = file.uri.pathSegments.last.replaceFirst('.json', '');
  final scenario = json['scenario'] as String;
  final measureSeconds = (json['measureSeconds'] as num).toDouble();
  final frames = (json['frames'] as List<dynamic>).cast<Map<String, dynamic>>();
  final memory =
      (json['nativeMemory'] as List<dynamic>).cast<Map<String, dynamic>>()
        ..sort(
          (a, b) => ((a['timestampMicros'] as num?) ?? 0).compareTo(
            (b['timestampMicros'] as num?) ?? 0,
          ),
        );
  final preMeasureMemory = json['preMeasureNativeMemory'];
  final settledMemory = json['settledNativeMemory'];
  final cooldownMemory =
      (json['cooldownNativeMemory'] as List<dynamic>? ?? const <dynamic>[])
          .cast<Map<String, dynamic>>()
          .toList()
        ..sort(
          (a, b) => ((a['timestampMicros'] as num?) ?? 0).compareTo(
            (b['timestampMicros'] as num?) ?? 0,
          ),
        );
  final measurementWindow = _readMeasurementWindow(
    File('${input.path}/traces/$runKey.signposts.xml'),
    scenario,
    measureSeconds,
  );
  return _Report(
    scenario: scenario,
    runKey: runKey,
    repetition: (json['repetition'] as num?)?.toInt() ?? 1,
    expectedMeasureSeconds: measureSeconds,
    measurementWindow: measurementWindow,
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
    preMeasureFootprintMb: _memoryMb(
      preMeasureMemory,
      'physicalFootprintBytes',
    ),
    preMeasureMemoryStable:
        json['preMeasureMemoryStable'] as bool? ?? schemaVersion < 4,
    preMeasureMemorySlopeMbPerSecond:
        (json['preMeasureMemorySlopeMbPerSecond'] as num?)?.toDouble(),
    settledFootprintMb:
        _settledMemoryMb(cooldownMemory) ??
        _memoryMb(settledMemory, 'physicalFootprintBytes'),
    cooldownFootprintMb: cooldownMemory
        .where((m) => m['physicalFootprintBytes'] is num)
        .map((m) => (m['physicalFootprintBytes'] as num) / 1048576)
        .toList(),
    cooldownTimestampSeconds: cooldownMemory
        .where((m) => m['physicalFootprintBytes'] is num)
        .map((m) => ((m['timestampMicros'] as num?) ?? 0) / 1000000)
        .toList(),
    cooldownMemoryStable:
        json['cooldownMemoryStable'] as bool? ?? schemaVersion < 4,
    reportedCooldownSlopeMbPerSecond:
        (json['cooldownMemorySlopeMbPerSecond'] as num?)?.toDouble(),
    gpu: _readGpuIntervals(
      File('${input.path}/traces/$runKey.gpu.xml'),
      measureSeconds: measureSeconds,
      measurementWindow: measurementWindow,
    ),
    metal: _readMetalResources(
      File(
        '${input.path}/traces/$runKey.metal-resources.xml',
      ),
      measurementWindow: measurementWindow,
    ),
  );
}

double? _settledMemoryMb(List<Map<String, dynamic>> samples) {
  final values = samples
      .where((sample) => sample['physicalFootprintBytes'] is num)
      .map((sample) => (sample['physicalFootprintBytes'] as num) / 1048576)
      .toList();
  if (values.isEmpty) return null;
  final window = math.min(10, values.length);
  return _median(values.sublist(values.length - window));
}

double? _memoryMb(Object? value, String key) {
  if (value is! Map<String, dynamic> || value[key] is! num) return null;
  return (value[key] as num) / 1048576;
}

_GpuMetrics? _readGpuIntervals(
  File file, {
  required double measureSeconds,
  required _MeasurementWindow? measurementWindow,
}) {
  if (!file.existsSync()) return null;
  final xml = file.readAsStringSync();
  final targetPid = measurementWindow?.processPid;
  final processMatch = targetPid == null
      ? RegExp(
          r'<process id="(\d+)" fmt="liquid_glass_renderer_example \(\d+\)">',
        ).firstMatch(xml)
      : RegExp(
          '<process id="(\\d+)" fmt="[^"]+ \\($targetPid\\)">',
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
  final windowEnd = measurementWindow?.endNanos ?? intervals.last.$2;
  final windowStart =
      measurementWindow?.startNanos ??
      math.max(
        intervals.first.$1,
        windowEnd - (measureSeconds * 1000000000).round(),
      );
  final measuredIntervals = intervals
      .where(
        (interval) => interval.$2 > windowStart && interval.$1 < windowEnd,
      )
      .map(
        (interval) => (
          math.max(interval.$1, windowStart),
          math.min(interval.$2, windowEnd),
        ),
      )
      .toList();
  if (measuredIntervals.isEmpty) return null;
  var unionNanos = 0;
  var start = measuredIntervals.first.$1;
  var end = measuredIntervals.first.$2;
  for (final interval in measuredIntervals.skip(1)) {
    if (interval.$1 <= end) {
      end = math.max(end, interval.$2);
    } else {
      unionNanos += end - start;
      start = interval.$1;
      end = interval.$2;
    }
  }
  unionNanos += end - start;
  final spanNanos = windowEnd - windowStart;
  return _GpuMetrics(
    intervalCount: measuredIntervals.length,
    busyMs: unionNanos / 1000000,
    observedSpanMs: spanNanos / 1000000,
    intervalMs: measuredIntervals
        .map((interval) => (interval.$2 - interval.$1) / 1000000)
        .toList(),
  );
}

typedef _MeasurementWindow = ({
  int startNanos,
  int endNanos,
  int processPid,
});

_MeasurementWindow? _readMeasurementWindow(
  File file,
  String scenario,
  double expectedSeconds,
) {
  if (!file.existsSync()) return null;
  final xml = file.readAsStringSync();
  if (!xml.contains('<schema name="os-signpost">')) return null;
  final times = _numericReferences(xml, 'event-time');
  final identifiers = _textReferences(xml, 'os-signpost-identifier');
  final eventTypes = _textReferences(xml, 'event-type');
  final names = _textReferences(xml, 'signpost-name');
  final subsystems = _textReferences(xml, 'subsystem');
  final messages = <String, String>{
    for (final match in RegExp(
      r'<os-log-metadata id="(\d+)"[^>]*fmt="([^"]*)"',
    ).allMatches(xml))
      match.group(1)!: match.group(2)!,
  };
  final processPids = <String, int>{
    for (final match in RegExp(
      r'<process id="(\d+)" fmt="[^"]+ \((\d+)\)">',
    ).allMatches(xml))
      match.group(1)!: int.parse(match.group(2)!),
  };
  final begins = <String, int>{};
  final beginPids = <String, int>{};
  final windows = <_MeasurementWindow>[];
  for (final match in RegExp(
    r'<row>(.*?)</row>',
    dotAll: true,
  ).allMatches(xml)) {
    final row = match.group(1)!;
    if (_textOrReference(row, 'signpost-name', names) !=
            'LiquidGlassBenchmark' ||
        _textOrReference(row, 'subsystem', subsystems) !=
            'com.example.liquidGlassRenderer' ||
        _formattedOrReference(row, 'os-log-metadata', messages) != scenario) {
      continue;
    }
    final time = _valueOrReference(row, 'event-time', times);
    final identifier = _textOrReference(
      row,
      'os-signpost-identifier',
      identifiers,
    );
    final eventType = _textOrReference(row, 'event-type', eventTypes);
    final processReference = RegExp(
      r'<process ref="(\d+)"/>',
    ).firstMatch(row)?.group(1);
    final processInline = RegExp(
      r'<process id="(\d+)" ',
    ).firstMatch(row)?.group(1);
    final processPid = processPids[processReference ?? processInline];
    if (time == null ||
        identifier == null ||
        eventType == null ||
        processPid == null) {
      continue;
    }
    if (eventType == 'Begin') {
      begins[identifier] = time;
      beginPids[identifier] = processPid;
    } else if (eventType == 'End') {
      final start = begins[identifier];
      final beginPid = beginPids[identifier];
      if (start != null && beginPid == processPid) {
        windows.add((
          startNanos: start,
          endNanos: time,
          processPid: processPid,
        ));
      }
    }
  }
  if (windows.isEmpty) return null;
  final expectedNanos = expectedSeconds * 1000000000;
  windows.sort((a, b) {
    final aError = ((a.endNanos - a.startNanos) - expectedNanos).abs();
    final bError = ((b.endNanos - b.startNanos) - expectedNanos).abs();
    final comparison = aError.compareTo(bError);
    return comparison == 0 ? b.startNanos.compareTo(a.startNanos) : comparison;
  });
  return windows.first;
}

Map<String, int> _numericReferences(String xml, String tag) => <String, int>{
  for (final match in RegExp(
    '<$tag id="(\\d+)"[^>]*>(\\d+)</$tag>',
  ).allMatches(xml))
    match.group(1)!: int.parse(match.group(2)!),
};

Map<String, String> _textReferences(String xml, String tag) => <String, String>{
  for (final match in RegExp(
    '<$tag id="(\\d+)"[^>]*>([^<]*)</$tag>',
  ).allMatches(xml))
    match.group(1)!: match.group(2)!,
};

String? _textOrReference(
  String row,
  String tag,
  Map<String, String> references,
) {
  final value = RegExp(
    '<$tag(?: id="\\d+")?[^>]*>([^<]*)</$tag>',
  ).firstMatch(row);
  if (value != null) return value.group(1);
  final reference = RegExp('<$tag ref="(\\d+)"/>').firstMatch(row);
  return reference == null ? null : references[reference.group(1)];
}

String? _formattedOrReference(
  String row,
  String tag,
  Map<String, String> references,
) {
  final value = RegExp(
    '<$tag(?: id="\\d+")?[^>]*fmt="([^"]*)"',
  ).firstMatch(row);
  if (value != null) return value.group(1);
  final reference = RegExp('<$tag ref="(\\d+)"/>').firstMatch(row);
  return reference == null ? null : references[reference.group(1)];
}

_MetalMetrics? _readMetalResources(
  File file, {
  required _MeasurementWindow? measurementWindow,
}) {
  if (!file.existsSync()) return null;
  final xml = file.readAsStringSync();
  if (!xml.contains('<schema name="metal-resource-allocations">')) {
    return null;
  }
  final targetPid = measurementWindow?.processPid;
  final processMatch = targetPid == null
      ? RegExp(
          r'<process id="(\d+)" fmt="liquid_glass_renderer_example \(\d+\)">',
        ).firstMatch(xml)
      : RegExp(
          '<process id="(\\d+)" fmt="[^"]+ \\($targetPid\\)">',
        ).firstMatch(xml);
  // A static scenario can legitimately have no resource rows. If rows exist
  // but none belong to the measured PID, attribution is missing—not zero.
  if (processMatch == null) {
    return xml.contains('<row>') ? null : _MetalMetrics.zero();
  }
  final processId = processMatch.group(1)!;
  final sizes = <String, int>{
    for (final match in RegExp(
      r'<size-in-bytes id="(\d+)"[^>]*>(\d+)</size-in-bytes>',
    ).allMatches(xml))
      match.group(1)!: int.parse(match.group(2)!),
  };
  final events = <String, String>{
    for (final match in RegExp(
      r'<gpu-memory-event-name id="(\d+)"[^>]*>([^<]+)</gpu-memory-event-name>',
    ).allMatches(xml))
      match.group(1)!: match.group(2)!,
  };
  final starts = _numericReferences(xml, 'start-time');
  var allocationCount = 0;
  var deallocationCount = 0;
  var allocatedBytes = 0;
  var deallocatedBytes = 0;
  var largestAllocationBytes = 0;
  for (final match in RegExp(
    r'<row>(.*?)</row>',
    dotAll: true,
  ).allMatches(xml)) {
    final row = match.group(1)!;
    if (!row.contains('<process ref="$processId"/>') &&
        !row.contains('<process id="$processId" ')) {
      continue;
    }
    final eventTime = _valueOrReference(row, 'start-time', starts);
    if (measurementWindow != null &&
        (eventTime == null ||
            eventTime < measurementWindow.startNanos ||
            eventTime >= measurementWindow.endNanos)) {
      continue;
    }
    final eventValue = RegExp(
      r'<gpu-memory-event-name(?: id="\d+")?[^>]*>([^<]+)</gpu-memory-event-name>',
    ).firstMatch(row)?.group(1);
    final eventReference = RegExp(
      r'<gpu-memory-event-name ref="(\d+)"/>',
    ).firstMatch(row)?.group(1);
    final event = eventValue ?? events[eventReference];
    final isAllocation = event == 'Allocation';
    final isDeallocation = event == 'Deallocation' || event == 'Free';
    if (!isAllocation && !isDeallocation) continue;
    final sizeMatches = RegExp(
      r'<size-in-bytes(?: id="\d+")?[^>]*>(\d+)</size-in-bytes>|<size-in-bytes ref="(\d+)"/>',
    ).allMatches(row);
    if (sizeMatches.isEmpty) continue;
    final lastSize = sizeMatches.last;
    final size = lastSize.group(1) == null
        ? sizes[lastSize.group(2)]
        : int.parse(lastSize.group(1)!);
    if (size == null) continue;
    if (isAllocation) {
      allocationCount++;
      allocatedBytes += size;
      largestAllocationBytes = math.max(largestAllocationBytes, size);
    } else {
      deallocationCount++;
      deallocatedBytes += size;
    }
  }
  return _MetalMetrics(
    allocationCount: allocationCount,
    deallocationCount: deallocationCount,
    allocatedBytes: allocatedBytes,
    deallocatedBytes: deallocatedBytes,
    largestAllocationBytes: largestAllocationBytes,
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
      '| Scenario | Frames | Raster p95 / p99 | Total p95 | GPU busy / interval p95 | Metal alloc/free / allocated | Footprint peak | Peak over pre | Settled − pre | Max sample step |',
    )
    ..writeln('|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|');
  for (final report in reports) {
    out.writeln(
      '| `${report.scenario}` r${report.repetition} | ${report.frameTotalMs.length} | ${_ms(report.p95Raster)} / ${_ms(report.p99Raster)} | ${_ms(report.p95Total)} | ${report.gpu == null ? 'unavailable' : '${report.gpu!.utilizationPercent.toStringAsFixed(1)}% / ${_ms(report.gpu!.p95IntervalMs)}'} | ${report.metal == null ? 'unavailable' : '${report.metal!.allocationCount}/${report.metal!.deallocationCount} / ${_mb(report.metal!.allocatedMb)}'} | ${_mb(report.peakFootprint)} | ${_signedMb(report.peakAbovePreMeasure)} | ${_signedMb(report.retainedFootprintDelta)} | ${_signedMb(report.maxFootprintStep)} |',
    );
  }
  out
    ..writeln()
    ..writeln('### Repeatability')
    ..writeln();
  for (final entry in _groupByScenario(reports).entries) {
    final raster = entry.value.map((report) => report.p95Raster).toList();
    final footprint = entry.value
        .map((report) => report.peakFootprint)
        .toList();
    final gpu = entry.value
        .map((report) => report.gpu?.utilizationPercent)
        .nonNulls
        .toList();
    out.writeln(
      '- `${entry.key}` (${entry.value.length} runs): raster p95 median ${_ms(_median(raster))}, CV ${(_coefficientOfVariation(raster) * 100).toStringAsFixed(1)}%; GPU busy median ${gpu.isEmpty ? 'unavailable' : '${_median(gpu).toStringAsFixed(1)}%'}, CV ${gpu.isEmpty ? 'unavailable' : '${(_coefficientOfVariation(gpu) * 100).toStringAsFixed(1)}%'}; footprint peak median ${_mb(_median(footprint))}, CV ${(_coefficientOfVariation(footprint) * 100).toStringAsFixed(1)}%.',
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
      '- `resizeAnimated` measures the internal grow-only, bucketed matte heuristic under continuous size changes. `largeResize` amplifies retained-memory and allocation-step signals.',
    )
    ..writeln(
      '- `layerChurn` isolates layer/renderer lifetime; growth without matching resize growth points to lifecycle retention.',
    )
    ..writeln(
      '- `ancestorTranslatedLayer` should stay close to `baselineMotion` because it reuses the complete layer matte. `translatedSingle` and `scaledRotatedSingle` measure relative shape transforms that invalidate geometry.',
    )
    ..writeln(
      '- `largeStatic` measures steady-state cost of a 2048×2048 matte. `fakeStatic` and `fakeLarge` stay on Impeller but bypass Flutter-GPU geometry, isolating the public FakeGlass path without changing renderer backends.',
    )
    ..writeln(
      '- Instruments attaches to the exact post-warmup target PID. A pre-registered Darwin notification opens the measurement gate when recording starts, then repeated signpost intervals adapt to lazy Metal-stream initialization. GPU intervals are PID-filtered and clipped to the closest full-duration interval. Metal allocation/free events are counted only inside it; raw XML/trace artifacts preserve resource lifetimes and backtraces. Missing target data fails enforced runs and is never treated as zero.',
    )
    ..writeln()
    ..writeln(
      '_Memory is Mach `phys_footprint`, not Dart heap. Retained memory is the settled native sample minus the post-warm-up pre-measurement sample. Percentiles are per-frame Flutter engine timings from profile-mode Impeller runs._',
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

List<String> _violations(
  List<_Report> reports, {
  required int minimumRepetitions,
}) {
  final violations = <String>[];
  for (final entry in _groupByScenario(reports).entries) {
    if (entry.value.length < minimumRepetitions) {
      violations.add(
        '${entry.key} has ${entry.value.length} repetitions; $minimumRepetitions are required.',
      );
    }
    if (entry.value.length >= 3) {
      final rasterCv = _coefficientOfVariation(
        entry.value.map((report) => report.p95Raster).toList(),
      );
      final footprintCv = _coefficientOfVariation(
        entry.value.map((report) => report.peakFootprint).toList(),
      );
      final gpuValues = entry.value
          .map((report) => report.gpu?.utilizationPercent)
          .nonNulls
          .toList();
      final gpuCv = gpuValues.length == entry.value.length
          ? _coefficientOfVariation(gpuValues)
          : null;
      if (rasterCv > .15 || footprintCv > .15 || (gpuCv ?? 0) > .15) {
        violations.add(
          '${entry.key} is not repeatable enough (raster CV ${(rasterCv * 100).toStringAsFixed(1)}%, GPU CV ${gpuCv == null ? 'unavailable' : '${(gpuCv * 100).toStringAsFixed(1)}%'}, footprint CV ${(footprintCv * 100).toStringAsFixed(1)}%; limit 15%).',
        );
      }
    }
  }
  for (final report in reports) {
    if (report.frameTotalMs.length < 30) {
      violations.add(
        '${report.scenario} captured only ${report.frameTotalMs.length} frames; at least 30 are required.',
      );
    }
    if (report.footprintMb.length < 10 ||
        report.preMeasureFootprintMb == null ||
        report.settledFootprintMb == null) {
      violations.add(
        '${report.scenario} is missing required native Mach memory samples.',
      );
    }
    if (!report.preMeasureMemoryStable) {
      violations.add(
        '${report.scenario} native footprint was not stable before measurement (${_signedMb(report.preMeasureMemorySlopeMbPerSecond ?? double.nan)}/s).',
      );
    }
    if (!report.cooldownMemoryStable) {
      violations.add(
        '${report.scenario} native footprint did not settle before the cooldown deadline (${_signedMb(report.cooldownSlopeMbPerSecond)}/s).',
      );
    }
    if (report.gpu == null) {
      violations.add(
        '${report.scenario} is missing process-filtered Metal GPU intervals.',
      );
    }
    if (report.measurementWindow == null) {
      violations.add(
        '${report.scenario} is missing its native measurement signpost interval.',
      );
    } else if ((report.traceMeasureSeconds - report.expectedMeasureSeconds)
            .abs() >
        report.expectedMeasureSeconds * .1) {
      violations.add(
        '${report.scenario} native trace captured ${report.traceMeasureSeconds.toStringAsFixed(2)} s of the ${report.expectedMeasureSeconds.toStringAsFixed(2)} s measurement.',
      );
    }
    if (report.metal == null) {
      violations.add(
        '${report.scenario} is missing the Metal resource allocation table.',
      );
    }
    if (report.cooldownMemoryStable &&
        report.cooldownSlopeMbPerSecond.abs() > 2) {
      violations.add(
        '${report.scenario} native footprint did not settle during cooldown (${_signedMb(report.cooldownSlopeMbPerSecond)}/s).',
      );
    }
    if (report.p99Raster > 16.67) {
      violations.add(
        '${report.scenario} raster p99 ${_ms(report.p99Raster)} exceeds the 16.67 ms frame budget.',
      );
    }
    if (report.retainedFootprintDelta > 64) {
      violations.add(
        '${report.scenario} retained ${_mb(report.retainedFootprintDelta)}; limit is 64 MB.',
      );
    }
    if (report.maxFootprintStep > 64) {
      violations.add(
        '${report.scenario} allocated ${_mb(report.maxFootprintStep)} in one sample; limit is 64 MB.',
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
    required this.runKey,
    required this.repetition,
    required this.expectedMeasureSeconds,
    required this.measurementWindow,
    required this.frameBuildMs,
    required this.frameRasterMs,
    required this.frameTotalMs,
    required this.footprintMb,
    required this.residentMb,
    required this.preMeasureFootprintMb,
    required this.preMeasureMemoryStable,
    required this.preMeasureMemorySlopeMbPerSecond,
    required this.settledFootprintMb,
    required this.cooldownFootprintMb,
    required this.cooldownTimestampSeconds,
    required this.cooldownMemoryStable,
    required this.reportedCooldownSlopeMbPerSecond,
    required this.gpu,
    required this.metal,
  });
  final String scenario;
  final String runKey;
  final int repetition;
  final double expectedMeasureSeconds;
  final _MeasurementWindow? measurementWindow;
  final List<double> frameBuildMs;
  final List<double> frameRasterMs;
  final List<double> frameTotalMs;
  final List<double> footprintMb;
  final List<double> residentMb;
  final double? preMeasureFootprintMb;
  final bool preMeasureMemoryStable;
  final double? preMeasureMemorySlopeMbPerSecond;
  final double? settledFootprintMb;
  final List<double> cooldownFootprintMb;
  final List<double> cooldownTimestampSeconds;
  final bool cooldownMemoryStable;
  final double? reportedCooldownSlopeMbPerSecond;
  final _GpuMetrics? gpu;
  final _MetalMetrics? metal;

  double get traceMeasureSeconds => measurementWindow == null
      ? 0
      : (measurementWindow!.endNanos - measurementWindow!.startNanos) /
            1000000000;

  double get p95Build => _percentile(frameBuildMs, .95);
  double get p95Raster => _percentile(frameRasterMs, .95);
  double get p99Raster => _percentile(frameRasterMs, .99);
  double get p95Total => _percentile(frameTotalMs, .95);
  double get peakFootprint =>
      footprintMb.isEmpty ? 0 : footprintMb.reduce(math.max);
  double get medianFootprint => _percentile(footprintMb, .5);
  double get peakAboveMedian => peakFootprint - medianFootprint;
  double get peakAbovePreMeasure =>
      peakFootprint - (preMeasureFootprintMb ?? medianFootprint);
  double get retainedFootprintDelta {
    if (preMeasureFootprintMb != null && settledFootprintMb != null) {
      return settledFootprintMb! - preMeasureFootprintMb!;
    }
    if (footprintMb.length < 4) return 0;
    final window = math.max(2, footprintMb.length ~/ 5);
    return _median(footprintMb.sublist(footprintMb.length - window)) -
        _median(footprintMb.sublist(0, window));
  }

  double get maxFootprintStep {
    var result = 0.0;
    final samples = <double>[
      if (preMeasureFootprintMb != null) preMeasureFootprintMb!,
      ...footprintMb,
      if (settledFootprintMb != null) settledFootprintMb!,
    ];
    for (var i = 1; i < samples.length; i++) {
      result = math.max(result, samples[i] - samples[i - 1]);
    }
    return result;
  }

  double get cooldownSlopeMbPerSecond {
    if (reportedCooldownSlopeMbPerSecond case final slope?) return slope;
    if (cooldownFootprintMb.length < 4 || cooldownTimestampSeconds.length < 4) {
      return 0;
    }
    final window = math.min(10, cooldownFootprintMb.length ~/ 2);
    final firstValue = _median(cooldownFootprintMb.sublist(0, window));
    final lastValue = _median(
      cooldownFootprintMb.sublist(cooldownFootprintMb.length - window),
    );
    final firstTime = _median(cooldownTimestampSeconds.sublist(0, window));
    final lastTime = _median(
      cooldownTimestampSeconds.sublist(
        cooldownTimestampSeconds.length - window,
      ),
    );
    return lastTime == firstTime
        ? 0
        : (lastValue - firstValue) / (lastTime - firstTime);
  }

  Map<String, Object?> toJson(_Report? baseline) => <String, Object?>{
    'scenario': scenario,
    'repetition': repetition,
    'nativeTraceMeasureSeconds': measurementWindow == null
        ? null
        : traceMeasureSeconds,
    'frameCount': frameTotalMs.length,
    'buildP95Ms': p95Build,
    'rasterP95Ms': p95Raster,
    'rasterP99Ms': p99Raster,
    'totalP95Ms': p95Total,
    'nativeFootprintPeakMb': peakFootprint,
    'nativeFootprintMedianMb': medianFootprint,
    'nativeFootprintPeakAboveMedianMb': peakAboveMedian,
    'nativeFootprintPeakAbovePreMeasureMb': peakAbovePreMeasure,
    'nativeFootprintPreMeasureMb': preMeasureFootprintMb,
    'nativeFootprintPreMeasureStable': preMeasureMemoryStable,
    'nativeFootprintPreMeasureSlopeMbPerSecond':
        preMeasureMemorySlopeMbPerSecond,
    'nativeFootprintSettledMb': settledFootprintMb,
    'nativeFootprintRetainedDeltaMb': retainedFootprintDelta,
    'nativeFootprintMaxSampleStepMb': maxFootprintStep,
    'nativeFootprintCooldownSlopeMbPerSecond': cooldownSlopeMbPerSecond,
    'nativeFootprintCooldownStable': cooldownMemoryStable,
    'gpu': gpu?.toJson(),
    'metal': metal?.toJson(),
    if (baseline != null && baseline != this)
      'versusBaseline': <String, double>{
        'rasterP95DeltaMs': p95Raster - baseline.p95Raster,
        'nativeFootprintPeakDeltaMb': peakFootprint - baseline.peakFootprint,
      },
  };
}

class _MetalMetrics {
  const _MetalMetrics({
    required this.allocationCount,
    required this.deallocationCount,
    required this.allocatedBytes,
    required this.deallocatedBytes,
    required this.largestAllocationBytes,
  });

  factory _MetalMetrics.zero() => const _MetalMetrics(
    allocationCount: 0,
    deallocationCount: 0,
    allocatedBytes: 0,
    deallocatedBytes: 0,
    largestAllocationBytes: 0,
  );

  final int allocationCount;
  final int deallocationCount;
  final int allocatedBytes;
  final int deallocatedBytes;
  final int largestAllocationBytes;

  double get allocatedMb => allocatedBytes / 1048576;
  double get deallocatedMb => deallocatedBytes / 1048576;
  double get largestAllocationMb => largestAllocationBytes / 1048576;

  Map<String, Object?> toJson() => <String, Object?>{
    'allocationCount': allocationCount,
    'deallocationCount': deallocationCount,
    'cumulativeAllocatedMb': allocatedMb,
    'cumulativeDeallocatedMb': deallocatedMb,
    'largestAllocationMb': largestAllocationMb,
  };
}

class _GpuMetrics {
  const _GpuMetrics({
    required this.intervalCount,
    required this.busyMs,
    required this.observedSpanMs,
    required this.intervalMs,
  });
  final int intervalCount;
  final double busyMs;
  final double observedSpanMs;
  final List<double> intervalMs;
  double get totalIntervalMs => intervalMs.fold(0, (sum, value) => sum + value);
  double get p50IntervalMs => _percentile(intervalMs, .5);
  double get p95IntervalMs => _percentile(intervalMs, .95);
  double get p99IntervalMs => _percentile(intervalMs, .99);
  double get maxIntervalMs =>
      intervalMs.isEmpty ? 0 : intervalMs.reduce(math.max);
  double get utilizationPercent =>
      observedSpanMs == 0 ? 0 : busyMs / observedSpanMs * 100;
  Map<String, Object?> toJson() => <String, Object?>{
    'intervalCount': intervalCount,
    'busyMs': busyMs,
    'totalIntervalMs': totalIntervalMs,
    'observedSpanMs': observedSpanMs,
    'utilizationPercent': utilizationPercent,
    'intervalP50Ms': p50IntervalMs,
    'intervalP95Ms': p95IntervalMs,
    'intervalP99Ms': p99IntervalMs,
    'intervalMaxMs': maxIntervalMs,
  };
}

double _percentile(List<double> values, double percentile) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  return sorted[((sorted.length - 1) * percentile).round()];
}

double _median(List<double> values) => _percentile(values, .5);

Map<String, List<_Report>> _groupByScenario(List<_Report> reports) {
  final groups = <String, List<_Report>>{};
  for (final report in reports) {
    groups.putIfAbsent(report.scenario, () => []).add(report);
  }
  return groups;
}

List<Map<String, Object?>> _reliability(List<_Report> reports) =>
    _groupByScenario(reports).entries.map((entry) {
      final gpu = entry.value
          .map((report) => report.gpu?.utilizationPercent)
          .nonNulls
          .toList();
      return <String, Object?>{
        'scenario': entry.key,
        'repetitions': entry.value.length,
        'rasterP95MedianMs': _median(
          entry.value.map((report) => report.p95Raster).toList(),
        ),
        'rasterP95CoefficientOfVariation': _coefficientOfVariation(
          entry.value.map((report) => report.p95Raster).toList(),
        ),
        'gpuBusyMedianPercent': gpu.isEmpty ? null : _median(gpu),
        'gpuBusyCoefficientOfVariation': gpu.isEmpty
            ? null
            : _coefficientOfVariation(gpu),
        'nativeFootprintPeakMedianMb': _median(
          entry.value.map((report) => report.peakFootprint).toList(),
        ),
        'nativeFootprintPeakCoefficientOfVariation': _coefficientOfVariation(
          entry.value.map((report) => report.peakFootprint).toList(),
        ),
      };
    }).toList();

double _coefficientOfVariation(List<double> values) {
  if (values.length < 2) return 0;
  final mean = values.reduce((a, b) => a + b) / values.length;
  if (mean == 0) return 0;
  final variance =
      values
          .map((value) => math.pow(value - mean, 2).toDouble())
          .reduce((a, b) => a + b) /
      (values.length - 1);
  return math.sqrt(variance) / mean.abs();
}

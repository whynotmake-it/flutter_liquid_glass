// The parser emits Markdown tables and diagnostic strings whose source form is
// clearer when kept intact; bracketed metric names are prose, not Dart links.
// ignore_for_file: cascade_invocations, comment_references
// ignore_for_file: lines_longer_than_80_chars, no_adjacent_strings_in_list

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
  // The harness continues past failing scenario runs and records them in
  // this directory instead, so the summary is always emitted — possibly
  // without any successful report at all.
  final failedRuns = _readFailedRuns(input);
  if (reports.isEmpty && failedRuns.isEmpty) {
    throw StateError('No benchmark scenario reports found.');
  }

  final baseline = reports
      .where((report) => report.scenario == 'baselineMotion')
      .firstOrNull;
  final fakeBaseline = reports
      .where((report) => report.scenario == 'fakeStatic')
      .firstOrNull;
  final minimumRepetitions = int.parse(options['minimum-repetitions'] ?? '1');
  final violations = _violations(
    reports,
    failedRuns,
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
        final baselineName = _comparisonScenario(report.scenario);
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
    'failedRuns': failedRuns
        .map(
          (run) => <String, Object?>{
            'scenario': run.scenario,
            'repetition': run.repetition,
            'reason': run.reason,
          },
        )
        .toList(),
    'reliability': _reliability(reports),
    'regressionViolations': violations,
  };

  final markdown = _markdown(
    reports,
    baseline,
    fakeBaseline,
    violations,
    failedRuns,
  );
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
    for (final violation in violations) {
      stderr.writeln('- $violation');
    }
    exitCode = 1;
  }
}

Map<String, String> _options(List<String> args) {
  final result = <String, String>{};
  for (var i = 0; i < args.length; i += 2) {
    if (!args[i].startsWith('--') || i + 1 >= args.length) {
      throw const FormatException('Expected --name value arguments.');
    }
    result[args[i].substring(2)] = args[i + 1];
  }
  return result;
}

typedef _FailedRun = ({String scenario, int repetition, String reason});

/// Reads scenario runs the harness recorded as failed (one `<runKey>.txt`
/// per failure in the `failures` directory) so the summary can list them
/// instead of losing the whole run to the first failing scenario.
List<_FailedRun> _readFailedRuns(Directory input) {
  final failures = Directory('${input.path}/failures');
  if (!failures.existsSync()) return const [];
  final runs = <_FailedRun>[];
  for (final file in failures.listSync().whereType<File>()) {
    if (!file.path.endsWith('.txt')) continue;
    final name = file.uri.pathSegments.last.replaceFirst('.txt', '');
    final match = RegExp(r'^(.+)\.r(\d+)$').firstMatch(name);
    if (match == null) continue;
    runs.add((
      scenario: match.group(1)!,
      repetition: int.parse(match.group(2)!),
      reason: file.readAsStringSync().trim(),
    ));
  }
  runs.sort((a, b) {
    final byScenario = a.scenario.compareTo(b.scenario);
    return byScenario != 0 ? byScenario : a.repetition.compareTo(b.repetition);
  });
  return runs;
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
  final measurementWindows = _readMeasurementWindows(
    File('${input.path}/traces/$runKey.signposts.xml'),
    File('${input.path}/logs/$runKey.trace-app.log'),
    File('${input.path}/traces/$runKey.toc.xml'),
    scenario,
    measureSeconds,
  );
  final gpuResult = _readGpuIntervals(
    File('${input.path}/traces/$runKey.gpu.xml'),
    measurementWindows: measurementWindows,
  );
  final inProcessGpuResult = _readInProcessGpu(
    json['commandBufferGpu'],
    frameCount: frames.length,
  );
  return _Report(
    scenario: scenario,
    runKey: runKey,
    repetition: (json['repetition'] as num?)?.toInt() ?? 1,
    expectedMeasureSeconds: measureSeconds,
    measurementWindows: measurementWindows,
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
    gpu: gpuResult.metrics,
    gpuUnavailableReason: gpuResult.unavailableReason,
    inProcessGpu: inProcessGpuResult.metrics,
    inProcessGpuUnavailableReason: inProcessGpuResult.unavailableReason,
    metal: _readMetalResources(
      File(
        '${input.path}/traces/$runKey.metal-resources.xml',
      ),
      measurementWindows: measurementWindows,
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

/// Outcome of reading the in-process command-buffer GPU channel from a run's
/// JSON report. [metrics] is null for older artifacts (no channel at all) or
/// when the payload is degenerate; [unavailableReason] is set when the app
/// reported the channel explicitly unavailable (for example no Metal device
/// or a failed interpose).
typedef _InProcessGpuResult = ({
  _InProcessGpu? metrics,
  String? unavailableReason,
});

_InProcessGpuResult _readInProcessGpu(Object? json, {required int frameCount}) {
  if (json is! Map<String, dynamic>) {
    return (metrics: null, unavailableReason: null);
  }
  if (json['available'] != true) {
    return (
      metrics: null,
      unavailableReason: json['reason'] as String? ?? 'unavailable',
    );
  }
  final busyMs = (json['busyMilliseconds'] as num?)?.toDouble();
  final windowMs = (json['windowMilliseconds'] as num?)?.toDouble();
  if (busyMs == null || windowMs == null || busyMs < 0 || windowMs <= 0) {
    return (
      metrics: null,
      unavailableReason: 'degenerate in-process GPU payload',
    );
  }
  return (
    metrics: _InProcessGpu(
      busyMs: busyMs,
      windowMs: windowMs,
      bufferCount: (json['bufferCount'] as num?)?.toInt() ?? 0,
      frameCount: frameCount,
      bucketBusyMs:
          (json['bucketBusyMilliseconds'] as List<dynamic>? ?? const [])
              .whereType<num>()
              .map((value) => value.toDouble())
              .toList(),
    ),
    unavailableReason: null,
  );
}

/// Outcome of reading a Metal GPU interval table. [metrics] is null whenever
/// no sound measurement exists; [unavailableReason] is set when intervals and
/// frame-counted windows were captured but the capture itself failed the
/// uniformity check, which distinguishes a rejected capture from a missing
/// trace (the latter stays a hard failure for required scenarios).
typedef _GpuReadResult = ({_GpuMetrics? metrics, String? unavailableReason});

/// A sound capture emits a near-constant number of GPU intervals per frame
/// because every frame issues the same render passes. When the GPU
/// instrument's event rate saturates the kernel kdebug buffer, events drop
/// silently with a run-varying loss factor and intervals-per-frame diverges
/// between half-second windows. Calibrated on historical artifacts: the
/// known-unsound independent16Motion capture (~6,600 interval events/s,
/// 2.576 s retained of a 60 s recording) scores CV 1.05, historically
/// consistent grouped16Motion captures score 0.18-0.24, and captures already
/// showing partial loss score 0.31-0.51. The threshold rejects a capture from
/// the first sign of loss; a false rejection only marks GPU data unavailable
/// while raster and footprint gates still apply.
const _captureUniformityMaxCv = .30;

/// Fewer windows than this cannot distinguish event loss from animation-phase
/// variation, so the capture is reported unavailable instead of judged.
const _captureUniformityMinWindows = 3;

_GpuReadResult _readGpuIntervals(
  File file, {
  required List<_MeasurementWindow> measurementWindows,
}) {
  if (!file.existsSync()) {
    return (
      metrics: null,
      unavailableReason: 'trace GPU table is missing',
    );
  }
  if (measurementWindows.isEmpty) {
    return (
      metrics: null,
      unavailableReason: 'capture unavailable: no validated measurement window overlapped the retained trace',
    );
  }
  final xml = file.readAsStringSync();
  final targetPid = measurementWindows.first.processPid;
  final processMatch = RegExp(
    '<process id="(\\d+)" fmt="[^"]+ \\($targetPid\\)">',
  ).firstMatch(xml);
  if (processMatch == null) {
    return (
      metrics: null,
      unavailableReason: 'trace GPU table has no attached benchmark process',
    );
  }
  final processId = processMatch.group(1)!;

  final durations = <String, int>{
    for (final match in RegExp(
      r'<duration id="(\d+)"[^>]*>(\d+)</duration>',
    ).allMatches(xml))
      match.group(1)!: _parseTraceInt64(match.group(2)!),
  };
  final starts = <String, int>{
    for (final match in RegExp(
      r'<start-time id="(\d+)"[^>]*>(\d+)</start-time>',
    ).allMatches(xml))
      match.group(1)!: _parseTraceInt64(match.group(2)!),
  };
  final intervals = <(int, int)>[];
  for (final match in RegExp(
    '<row>(.*?)</row>',
    dotAll: true,
  ).allMatches(xml)) {
    final row = match.group(1)!;
    if (!row.contains('<process ref="$processId"/>') &&
        !row.contains('<process id="$processId" ')) {
      continue;
    }
    final start = _valueOrReference(row, 'start-time', starts);
    final duration = _rowIntervalDuration(row, durations);
    // Rolling-window clipping can corrupt a row into a negative duration
    // (exported as a wrapped u64); such rows must not enter the union.
    if (start != null && duration != null && duration > 0) {
      intervals.add((start, start + duration));
    }
  }
  if (intervals.isEmpty) {
    return (
      metrics: null,
      unavailableReason: 'trace GPU table has no benchmark-process intervals',
    );
  }
  intervals.sort((a, b) => a.$1.compareTo(b.$1));
  final windows = _mergeWindows(measurementWindows);
  final measuredIntervals = <(int, int)>[
    for (final interval in intervals)
      for (final window in windows)
        if (interval.$2 > window.$1 && interval.$1 < window.$2)
          (
            math.max(interval.$1, window.$1),
            math.min(interval.$2, window.$2),
          ),
  ]..sort((a, b) => a.$1.compareTo(b.$1));
  if (measuredIntervals.isEmpty) {
    return (
      metrics: null,
      unavailableReason: 'capture unavailable: no GPU intervals overlapped the validated measurement windows',
    );
  }
  final rejection = _captureUniformityRejection(intervals, measurementWindows);
  if (rejection != null) {
    return (metrics: null, unavailableReason: rejection);
  }
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
  final spanNanos = windows.fold<int>(
    0,
    (total, window) => total + (window.$2 - window.$1),
  );
  // Per-frame GPU time is the repeatability metric: ProMotion varies the
  // refresh rate under tracing, which scales busy% without any renderer
  // change. Frame counts only exist when every window reported them.
  final windowFrameCounts = measurementWindows.map((w) => w.frameCount);
  final totalFrames = windowFrameCounts.every((count) => count != null)
      ? windowFrameCounts.fold<int>(0, (sum, count) => sum + count!)
      : null;
  return (
    metrics: _GpuMetrics(
      intervalCount: measuredIntervals.length,
      busyMs: unionNanos / 1000000,
      observedSpanMs: spanNanos / 1000000,
      frameCount: totalFrames == 0 ? null : totalFrames,
      intervalMs: measuredIntervals
          .map((interval) => (interval.$2 - interval.$1) / 1000000)
          .toList(),
    ),
    unavailableReason: null,
  );
}

/// Returns a rejection reason when the retained capture shows silent kdebug
/// event loss, or null when the capture is sound. Only frame-counted logged
/// windows can be checked: signpost-derived windows carry no frame counts, so
/// older artifacts keep their previous (trusted) behavior.
String? _captureUniformityRejection(
  List<(int, int)> intervals,
  List<_MeasurementWindow> measurementWindows,
) {
  if (measurementWindows.any((window) => window.frameCount == null)) {
    return null;
  }
  if (measurementWindows.length < _captureUniformityMinWindows) {
    return 'capture unavailable: ${measurementWindows.length} frame-counted '
        'measurement window(s) retained; at least '
        '$_captureUniformityMinWindows are required to verify uniformity';
  }
  final intervalsPerFrame = <double>[];
  var zeroIntervalWindows = 0;
  for (final window in measurementWindows) {
    var count = 0;
    for (final interval in intervals) {
      if (interval.$2 > window.startNanos && interval.$1 < window.endNanos) {
        count++;
      }
    }
    if (count == 0) zeroIntervalWindows++;
    intervalsPerFrame.add(count / window.frameCount!);
  }
  if (zeroIntervalWindows > 0 &&
      zeroIntervalWindows < measurementWindows.length) {
    return 'capture rejected: $zeroIntervalWindows of '
        '${measurementWindows.length} measurement windows retained zero GPU '
        'intervals while others retained some (kdebug buffer starvation)';
  }
  final cv = _coefficientOfVariation(intervalsPerFrame);
  if (cv > _captureUniformityMaxCv) {
    return 'capture rejected: intervals-per-frame CV '
        '${(cv * 100).toStringAsFixed(1)}% exceeds the '
        '${(_captureUniformityMaxCv * 100).round()}% uniformity limit '
        '(silent kdebug event loss)';
  }
  return null;
}

typedef _MeasurementWindow = ({
  int startNanos,
  int endNanos,
  int processPid,
  int? frameCount,
});

List<_MeasurementWindow> _readMeasurementWindows(
  File signpostFile,
  File traceAppLog,
  File traceToc,
  String scenario,
  double expectedSeconds,
) {
  final loggedWindows = _readLoggedMeasurementWindows(
    traceAppLog,
    traceToc,
    scenario,
    expectedSeconds,
  );
  // Logged windows carry per-window frame counts, which the GPU
  // repeatability gate needs to stay refresh-rate invariant; prefer them
  // whenever they do. Signpost windows are trace-clock exact but have no
  // frame counts, and the Metal System Trace template usually does not
  // record them at all.
  if (loggedWindows.isNotEmpty &&
      loggedWindows.every((window) => window.frameCount != null)) {
    return loggedWindows;
  }
  final signpostWindows = _readSignpostMeasurementWindows(
    signpostFile,
    scenario,
    expectedSeconds,
  );
  if (signpostWindows.isNotEmpty) return signpostWindows;
  return loggedWindows;
}

/// A single half-second workload window lands on an arbitrary phase of the
/// animated scenarios, so GPU busy measured inside one window varies far
/// beyond the harness's repeatability gate. Every plausible window inside the
/// retained trace is therefore returned and the GPU/Metal metrics integrate
/// over their union, which averages the animation phase out.
List<_MeasurementWindow> _readSignpostMeasurementWindows(
  File file,
  String scenario,
  double expectedSeconds,
) {
  if (!file.existsSync()) return const [];
  final xml = file.readAsStringSync();
  if (!xml.contains('<schema name="os-signpost">')) return const [];
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
    '<row>(.*?)</row>',
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
          frameCount: null,
        ));
      }
    }
  }
  // Degenerate intervals synthesized while the Metal stream lazily
  // initializes are noise; keep only plausible workload windows.
  windows.removeWhere((window) {
    final durationSeconds = (window.endNanos - window.startNanos) / 1000000000;
    return durationSeconds < .45 || durationSeconds > expectedSeconds * 1.1;
  });
  windows.sort((a, b) => a.startNanos.compareTo(b.startNanos));
  return windows;
}

List<_MeasurementWindow> _readLoggedMeasurementWindows(
  File traceAppLog,
  File traceToc,
  String scenario,
  double expectedSeconds,
) {
  if (!traceAppLog.existsSync() || !traceToc.existsSync()) return const [];
  final toc = traceToc.readAsStringSync();
  final startText = RegExp(
    '<start-date>([^<]+)</start-date>',
  ).firstMatch(toc)?.group(1);
  final durationText = RegExp(
    '<duration>([^<]+)</duration>',
  ).firstMatch(toc)?.group(1);
  final processPidText = RegExp(
    r'<process type="attached"[^>]*name="liquid_glass_renderer_example"[^>]*pid="(\d+)"',
  ).firstMatch(toc)?.group(1);
  if (startText == null || durationText == null || processPidText == null) {
    return const [];
  }
  final traceStart = DateTime.tryParse(startText);
  final traceDurationSeconds = double.tryParse(durationText);
  if (traceStart == null || traceDurationSeconds == null) return const [];

  final escapedScenario = RegExp.escape(scenario);
  final events = RegExp(
    'LIQUID_GLASS_BENCHMARK_MEASURE_(BEGIN|END):$escapedScenario:(\\d+)(?::(\\d+))?',
  ).allMatches(traceAppLog.readAsStringSync());
  int? pendingBeginMicros;
  final windows = <_MeasurementWindow>[];
  final traceStartMicros = traceStart.microsecondsSinceEpoch;
  final traceEndNanos = (traceDurationSeconds * 1000000000).round();
  for (final event in events) {
    final epochMicros = int.parse(event.group(2)!);
    if (event.group(1) == 'BEGIN') {
      pendingBeginMicros = epochMicros;
      continue;
    }
    final beginMicros = pendingBeginMicros;
    pendingBeginMicros = null;
    if (beginMicros == null || epochMicros <= beginMicros) continue;
    final rawStartNanos = (beginMicros - traceStartMicros) * 1000;
    final rawEndNanos = (epochMicros - traceStartMicros) * 1000;
    final startNanos = math.max(0, rawStartNanos);
    final endNanos = math.min(traceEndNanos, rawEndNanos);
    final durationSeconds = (endNanos - startNanos) / 1000000000;
    if (durationSeconds < .45 || durationSeconds > expectedSeconds * 1.1) {
      continue;
    }
    windows.add((
      startNanos: startNanos,
      endNanos: endNanos,
      processPid: int.parse(processPidText),
      frameCount: event.group(3) == null ? null : int.parse(event.group(3)!),
    ));
  }
  windows.sort((a, b) => a.startNanos.compareTo(b.startNanos));
  return windows;
}

/// Merges overlapping or touching measurement windows into disjoint
/// `(start, end)` spans so GPU busy integrates over each retained nanosecond
/// exactly once.
List<(int, int)> _mergeWindows(List<_MeasurementWindow> windows) {
  final sorted = [...windows]
    ..sort((a, b) => a.startNanos.compareTo(b.startNanos));
  final merged = <(int, int)>[];
  for (final window in sorted) {
    if (merged.isNotEmpty && window.startNanos <= merged.last.$2) {
      merged.last = (
        merged.last.$1,
        math.max(merged.last.$2, window.endNanos),
      );
    } else {
      merged.add((window.startNanos, window.endNanos));
    }
  }
  return merged;
}

Map<String, int> _numericReferences(String xml, String tag) => <String, int>{
  for (final match in RegExp(
    '<$tag id="(\\d+)"[^>]*>(\\d+)</$tag>',
  ).allMatches(xml))
    match.group(1)!: _parseTraceInt64(match.group(2)!),
};

/// xctrace serializes numeric table values as unsigned 64-bit integers, so a
/// negative value (for example a duration corrupted by rolling-window
/// clipping) arrives near 2^64 and overflows Dart's signed 63-bit int.
/// Reinterpret such values as two's-complement signed 64-bit; callers reject
/// non-positive durations and out-of-window timestamps.
int _parseTraceInt64(String text) {
  final parsed = int.tryParse(text);
  if (parsed != null) return parsed;
  return (BigInt.parse(text) - (BigInt.one << 64)).toInt();
}

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
  required List<_MeasurementWindow> measurementWindows,
}) {
  if (!file.existsSync() || measurementWindows.isEmpty) return null;
  final xml = file.readAsStringSync();
  if (!xml.contains('<schema name="metal-resource-allocations">')) {
    return null;
  }
  final targetPid = measurementWindows.first.processPid;
  final processMatch = RegExp(
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
      match.group(1)!: _parseTraceInt64(match.group(2)!),
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
    '<row>(.*?)</row>',
    dotAll: true,
  ).allMatches(xml)) {
    final row = match.group(1)!;
    if (!row.contains('<process ref="$processId"/>') &&
        !row.contains('<process id="$processId" ')) {
      continue;
    }
    final eventTime = _valueOrReference(row, 'start-time', starts);
    if (eventTime == null ||
        !measurementWindows.any(
          (window) =>
              eventTime >= window.startNanos && eventTime < window.endNanos,
        )) {
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
        : _parseTraceInt64(lastSize.group(1)!);
    if (size == null || size < 0) continue;
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

/// The metal-gpu-intervals schema contains two duration-typed columns: the
/// interval's own Duration and the CPU-to-GPU start latency. Both serialize
/// as <duration> elements in schema column order, so a value-first search
/// would mistake an inline latency for the interval duration whenever the
/// real duration is exported as a reference. The interval duration is always
/// the first duration element in the row.
int? _rowIntervalDuration(String row, Map<String, int> references) {
  final match = RegExp(
    r'<duration\s+ref="(\d+)"/>|<duration(?:\s+[^>]*)?>(\d+)</duration>',
  ).firstMatch(row);
  if (match == null) return null;
  final reference = match.group(1);
  if (reference != null) return references[reference];
  return _parseTraceInt64(match.group(2)!);
}

int? _valueOrReference(String row, String tag, Map<String, int> references) {
  final value = RegExp(
    '<$tag(?: id="\\d+")?[^>]*>(\\d+)</$tag>',
  ).firstMatch(row);
  if (value != null) return _parseTraceInt64(value.group(1)!);
  final reference = RegExp('<$tag ref="(\\d+)"/>').firstMatch(row);
  return reference == null ? null : references[reference.group(1)];
}

String _markdown(
  List<_Report> reports,
  _Report? baseline,
  _Report? fakeBaseline,
  List<String> violations,
  List<_FailedRun> failedRuns,
) {
  final out = StringBuffer()
    ..writeln('## Liquid Glass native performance')
    ..writeln()
    ..writeln(
      '| Scenario | Frames | Raster p95 / p99 | Total p95 | GPU busy / per-frame (in-process) | Traced GPU busy / per-frame / interval p95 | Metal alloc/free / allocated | Footprint peak | Peak over pre | Settled − pre | Max sample step |',
    )
    ..writeln('|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|');
  for (final report in reports) {
    final inProcessGpuCell = report.inProcessGpu != null
        ? '${report.inProcessGpu!.busyPercent.toStringAsFixed(1)}% / ${report.inProcessGpu!.msPerFrame == null ? 'unavailable' : _ms(report.inProcessGpu!.msPerFrame!)}'
        : 'unavailable';
    final gpuCell = report.gpu != null
        ? '${report.gpu!.utilizationPercent.toStringAsFixed(1)}% / ${report.gpu!.gpuTimeMsPerFrame == null ? 'unavailable' : _ms(report.gpu!.gpuTimeMsPerFrame!)} / ${_ms(report.gpu!.p95IntervalMs)}'
        : report.gpuUnavailableReason != null
        ? 'unavailable (capture rejected)'
        : 'unavailable';
    out.writeln(
      '| `${report.scenario}` r${report.repetition} | ${report.frameTotalMs.length} | ${_ms(report.p95Raster)} / ${_ms(report.p99Raster)} | ${_ms(report.p95Total)} | $inProcessGpuCell | $gpuCell | ${report.metal == null ? 'unavailable' : '${report.metal!.allocationCount}/${report.metal!.deallocationCount} / ${_mb(report.metal!.allocatedMb)}'} | ${_mb(report.peakFootprint)} | ${_signedMb(report.peakAbovePreMeasure)} | ${_signedMb(report.retainedFootprintDelta)} | ${_signedMb(report.maxFootprintStep)} |',
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
    final inProcessGpuFrameTimes = entry.value
        .map((report) => report.inProcessGpu?.msPerFrame)
        .nonNulls
        .toList();
    final inProcessGpuSummary = inProcessGpuFrameTimes.isEmpty
        ? 'GPU/frame unavailable'
        : 'GPU/frame median ${_ms(_median(inProcessGpuFrameTimes))}, CV ${(_coefficientOfVariation(inProcessGpuFrameTimes) * 100).toStringAsFixed(1)}%';
    final gpu = entry.value
        .map((report) => report.gpu?.utilizationPercent)
        .nonNulls
        .toList();
    final rejectedRuns = entry.value
        .where((report) => report.gpuUnavailableReason != null)
        .length;
    final tracedRuns = entry.value
        .where(
          (report) => report.gpu != null || report.gpuUnavailableReason != null,
        )
        .length;
    final gpuSummary = rejectedRuns == 0
        ? 'traced GPU busy median ${gpu.isEmpty ? 'unavailable' : '${_median(gpu).toStringAsFixed(1)}%'}, CV ${gpu.isEmpty ? 'unavailable' : '${(_coefficientOfVariation(gpu) * 100).toStringAsFixed(1)}%'}'
        : 'traced GPU unavailable (capture rejected in $rejectedRuns/${entry.value.length} runs)';
    out.writeln(
      '- `${entry.key}` (${entry.value.length} runs): raster p95 median ${_ms(_median(raster))}, CV ${(_coefficientOfVariation(raster) * 100).toStringAsFixed(1)}%; $inProcessGpuSummary; footprint peak median ${_mb(_median(footprint))}, CV ${(_coefficientOfVariation(footprint) * 100).toStringAsFixed(1)}%${tracedRuns == 0 ? '' : '; $gpuSummary'}.',
    );
  }
  final rejections = reports
      .where((report) => report.gpuUnavailableReason != null)
      .toList();
  final tracedCount = reports
      .where(
        (report) => report.gpu != null || report.gpuUnavailableReason != null,
      )
      .length;
  if (tracedCount > 0) {
    out
      ..writeln()
      ..writeln('### GPU capture soundness')
      ..writeln();
    if (rejections.isEmpty) {
      out.writeln(
        'Every traced run passed the intervals-per-frame uniformity check '
        '(CV ≤ ${(_captureUniformityMaxCv * 100).round()}% across '
        'frame-counted half-second windows).',
      );
    } else {
      out
        ..writeln(
          'The intervals-per-frame uniformity check rejects traces whose '
          'kernel kdebug buffer silently dropped events (the GPU instrument '
          'emits ~6,600 events/s on the sixteen-independent-layer workload; '
          'a saturated buffer retained only 2.576 s of a 60 s recording). '
          'Rejected runs report no GPU metrics. GPU numbers are '
          'informational attribution only and are never enforced.',
        )
        ..writeln();
      for (final report in rejections) {
        out.writeln(
          '- `${report.scenario}` r${report.repetition}: ${report.gpuUnavailableReason}',
        );
      }
    }
  }
  final unstable = reports
      .where(
        (report) =>
            !report.preMeasureMemoryStable || !report.cooldownMemoryStable,
      )
      .toList();
  if (unstable.isNotEmpty) {
    out
      ..writeln()
      ..writeln('### Memory stability (informational)')
      ..writeln()
      ..writeln(
        'Pre-measurement and cooldown footprint stability no longer gate '
        'runs; unstable runs are listed here for context because their '
        'footprint numbers may carry transient allocation noise.',
      )
      ..writeln();
    for (final report in unstable) {
      final reasons = <String>[
        if (!report.preMeasureMemoryStable)
          'pre-measurement footprint not stable '
              '(${_signedMb(report.preMeasureMemorySlopeMbPerSecond ?? double.nan)}/s)',
        if (!report.cooldownMemoryStable)
          'cooldown footprint did not settle '
              '(${_signedMb(report.cooldownSlopeMbPerSecond)}/s)',
      ];
      out.writeln(
        '- `${report.scenario}` r${report.repetition}: ${reasons.join('; ')}.',
      );
    }
  }
  if (failedRuns.isNotEmpty) {
    out
      ..writeln()
      ..writeln('### Scenario failures')
      ..writeln()
      ..writeln(
        'These runs failed without aborting the benchmark; their scenarios '
        'are missing the corresponding repetitions above.',
      )
      ..writeln();
    for (final failure in failedRuns) {
      out.writeln(
        '- `${failure.scenario}` r${failure.repetition}: ${failure.reason}',
      );
    }
  }
  out
    ..writeln()
    ..writeln('### Attribution signals')
    ..writeln();
  if (baseline != null) {
    for (final report in reports.where(
      (r) => r != baseline && r != fakeBaseline,
    )) {
      final comparisonName = _comparisonScenario(report.scenario);
      final comparison = reports
          .where((candidate) => candidate.scenario == comparisonName)
          .firstOrNull;
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
      '- Instruments attaches to the exact post-warmup target PID while the app emits adjacent half-second workload intervals. The parser intersects a logged interval with the retained Metal timeline and requires at least 0.45 s of exact overlap. GPU intervals are PID-filtered and clipped to that window. Metal allocation/free events are counted only inside it; raw XML/trace artifacts preserve resource lifetimes and backtraces. Trace-derived data is attribution-only and is never treated as zero or enforced.',
    )
    ..writeln()
    ..writeln(
      '_Memory is Mach `phys_footprint`, not Dart heap. Retained memory is the settled native sample minus the post-warm-up pre-measurement sample. Percentiles are per-frame Flutter engine timings from profile-mode Impeller runs. In-process GPU busy is the union of Metal command-buffer execution spans observed by the Runner over the measure window; per-frame GPU divides that union by rendered frames._',
    );
  out
    ..writeln()
    ..writeln('### Regression gates')
    ..writeln();
  if (violations.isEmpty) {
    out.writeln(
      '- Passed: p99 raster, retained footprint, allocation-step, '
      'repeatability, and completeness limits. In-process GPU timing is '
      'informational while its noise floor is calibrated; xctrace GPU and '
      'Metal trace metrics are attribution-only and never gate.',
    );
  } else {
    for (final violation in violations) {
      out.writeln('- ❌ $violation');
    }
  }
  return out.toString();
}

String _comparisonScenario(String scenario) => switch (scenario) {
  'fakeLightingOnly' => 'realLightingOnly',
  'fakeBlurOnly' => 'realBlurOnly',
  'realHighBlurOnly' => 'realBlurOnly',
  'fakeHighBlurOnly' => 'fakeBlurOnly',
  'fakeSaturationOnly' => 'realSaturationOnly',
  'fakeBlurSaturation' => 'realBlurSaturation',
  'fakeToolbarMaterial' => 'realToolbarMaterial',
  'fakeGrouped4Motion' => 'grouped4Motion',
  'fakeUngrouped4Motion' => 'fakeGrouped4Motion',
  _ when scenario.startsWith('fake') => 'fakeStatic',
  _ => 'baselineMotion',
};

/// Enforced gates: raster p95/p99, native footprint (peak, retained delta,
/// per-sample step), raster/footprint repeatability, and run completeness.
/// Traced (xctrace) GPU busy and Metal allocation metrics are informational
/// only and never enforced: the kdebug rolling buffer retains a fixed event
/// count, not a fixed duration, so xctrace GPU capture density varies per
/// run by design and cannot gate. Memory pre/cooldown stability is likewise
/// informational metadata, not a gate.
///
/// The in-process command-buffer GPU channel is gate-quality but stays
/// informational until its noise floor is calibrated: set
/// [_inProcessGpuFrameCvLimit] to a finite value (for example .15) to
/// enforce its cross-repetition repeatability exactly like raster and
/// footprint.
const double? _inProcessGpuFrameCvLimit = null;

List<String> _violations(
  List<_Report> reports,
  List<_FailedRun> failedRuns, {
  required int minimumRepetitions,
}) {
  final violations = <String>[];
  for (final failure in failedRuns) {
    violations.add(
      '${failure.scenario} r${failure.repetition} failed: ${failure.reason}',
    );
  }
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
      if (rasterCv > .15 || footprintCv > .15) {
        violations.add(
          '${entry.key} is not repeatable enough (raster CV ${(rasterCv * 100).toStringAsFixed(1)}%, footprint CV ${(footprintCv * 100).toStringAsFixed(1)}%; limit 15%).',
        );
      }
      final inProcessGpuFrameTimes = entry.value
          .map((report) => report.inProcessGpu?.msPerFrame)
          .nonNulls
          .toList();
      if (_inProcessGpuFrameCvLimit case final limit?
          when inProcessGpuFrameTimes.length >= 3) {
        final gpuCv = _coefficientOfVariation(inProcessGpuFrameTimes);
        if (gpuCv > limit) {
          violations.add(
            '${entry.key} in-process GPU/frame is not repeatable enough (CV ${(gpuCv * 100).toStringAsFixed(1)}%; limit ${(limit * 100).toStringAsFixed(0)}%).',
          );
        }
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
    required this.measurementWindows,
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
    required this.gpuUnavailableReason,
    required this.inProcessGpu,
    required this.inProcessGpuUnavailableReason,
    required this.metal,
  });
  final String scenario;
  final String runKey;
  final int repetition;
  final double expectedMeasureSeconds;
  final List<_MeasurementWindow> measurementWindows;
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

  /// Why a captured trace yielded no GPU metrics despite containing
  /// intervals: the capture failed the uniformity check or retained too few
  /// frame-counted windows. Null when GPU metrics are available or when the
  /// trace itself is missing (a hard failure for required scenarios).
  final String? gpuUnavailableReason;

  /// The in-process command-buffer GPU channel, null for older artifacts or
  /// unavailable/degenerate payloads (see [inProcessGpuUnavailableReason]).
  final _InProcessGpu? inProcessGpu;
  final String? inProcessGpuUnavailableReason;
  final _MetalMetrics? metal;

  double get traceMeasureSeconds {
    var totalNanos = 0;
    for (final window in _mergeWindows(measurementWindows)) {
      totalNanos += window.$2 - window.$1;
    }
    return totalNanos / 1000000000;
  }

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
    'nativeTraceMeasureSeconds': measurementWindows.isEmpty
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
    'gpuUnavailableReason': gpuUnavailableReason,
    'inProcessGpu': inProcessGpu?.toJson(),
    'inProcessGpuUnavailableReason': inProcessGpuUnavailableReason,
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

/// In-process GPU timing collected by the Runner from Metal command-buffer
/// completion timestamps (run JSON `commandBufferGpu`, schemaVersion >= 5).
/// Busy time is the union of buffer execution spans, so it slightly
/// overcounts when a buffer idles mid-span but never double-counts
/// concurrent buffers. Unlike the xctrace channel there is no kernel event
/// buffer to overflow: every submitted buffer in the measure window is
/// covered, which makes this the enforceable GPU metric once calibrated.
class _InProcessGpu {
  const _InProcessGpu({
    required this.busyMs,
    required this.windowMs,
    required this.bufferCount,
    required this.frameCount,
    required this.bucketBusyMs,
  });

  final double busyMs;
  final double windowMs;
  final int bufferCount;

  /// Frames the Flutter engine reported for the same measure window.
  final int frameCount;

  /// Busy milliseconds per fixed 100 ms bucket, showing phase spread inside
  /// the window.
  final List<double> bucketBusyMs;

  double get busyPercent => busyMs / windowMs * 100;

  /// GPU time per rendered frame: refresh-rate invariant, the preferred
  /// cross-run comparison metric.
  double? get msPerFrame => frameCount == 0 ? null : busyMs / frameCount;
  double get bucketBusyP95Ms => _percentile(bucketBusyMs, .95);

  Map<String, Object?> toJson() => <String, Object?>{
    'busyMs': busyMs,
    'windowMs': windowMs,
    'busyPercent': busyPercent,
    'bufferCount': bufferCount,
    'frameCount': frameCount,
    'gpuTimeMsPerFrame': msPerFrame,
    'bucketBusyP95Ms': bucketBusyP95Ms,
  };
}

class _GpuMetrics {
  const _GpuMetrics({
    required this.intervalCount,
    required this.busyMs,
    required this.observedSpanMs,
    required this.frameCount,
    required this.intervalMs,
  });
  final int intervalCount;
  final double busyMs;
  final double observedSpanMs;

  /// Frames rendered inside the measurement windows, reported by the traced
  /// app. Null for signpost-derived windows or older artifacts.
  final int? frameCount;
  final List<double> intervalMs;
  double get totalIntervalMs => intervalMs.fold(0, (sum, value) => sum + value);
  double get p50IntervalMs => _percentile(intervalMs, .5);
  double get p95IntervalMs => _percentile(intervalMs, .95);
  double get p99IntervalMs => _percentile(intervalMs, .99);
  double get maxIntervalMs =>
      intervalMs.isEmpty ? 0 : intervalMs.reduce(math.max);
  double get utilizationPercent =>
      observedSpanMs == 0 ? 0 : busyMs / observedSpanMs * 100;

  /// GPU time per rendered frame. Unlike [utilizationPercent] this is
  /// independent of the refresh rate ProMotion selects under tracing, so it
  /// is the preferred informational GPU metric when frame counts exist.
  double? get gpuTimeMsPerFrame =>
      frameCount == null || frameCount == 0 ? null : busyMs / frameCount!;
  Map<String, Object?> toJson() => <String, Object?>{
    'intervalCount': intervalCount,
    'busyMs': busyMs,
    'totalIntervalMs': totalIntervalMs,
    'observedSpanMs': observedSpanMs,
    'utilizationPercent': utilizationPercent,
    'frameCount': frameCount,
    'gpuTimeMsPerFrame': gpuTimeMsPerFrame,
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
      final gpuFrameTimes = entry.value
          .map((report) => report.gpu?.gpuTimeMsPerFrame)
          .nonNulls
          .toList();
      final inProcessGpuFrameTimes = entry.value
          .map((report) => report.inProcessGpu?.msPerFrame)
          .nonNulls
          .toList();
      final inProcessGpuBusy = entry.value
          .map((report) => report.inProcessGpu?.busyPercent)
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
        'gpuFrameTimeMedianMs': gpuFrameTimes.isEmpty
            ? null
            : _median(gpuFrameTimes),
        'gpuFrameTimeCoefficientOfVariation': gpuFrameTimes.isEmpty
            ? null
            : _coefficientOfVariation(gpuFrameTimes),
        'inProcessGpuFrameTimeMedianMs': inProcessGpuFrameTimes.isEmpty
            ? null
            : _median(inProcessGpuFrameTimes),
        'inProcessGpuFrameTimeCoefficientOfVariation':
            inProcessGpuFrameTimes.isEmpty
            ? null
            : _coefficientOfVariation(inProcessGpuFrameTimes),
        'inProcessGpuBusyMedianPercent': inProcessGpuBusy.isEmpty
            ? null
            : _median(inProcessGpuBusy),
        'inProcessGpuBusyCoefficientOfVariation': inProcessGpuBusy.isEmpty
            ? null
            : _coefficientOfVariation(inProcessGpuBusy),
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

import 'dart:async';
import 'dart:convert';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Frames-timing probe used by performance audits. Enabled with
/// `--dart-define=LIQUID_GLASS_EXAMPLE_PERFORMANCE_PROBE=true`.
class PerformanceProbe extends StatefulWidget {
  const PerformanceProbe({super.key});

  @override
  State<PerformanceProbe> createState() => _PerformanceProbeState();
}

class _PerformanceProbeState extends State<PerformanceProbe> {
  final _timings = <FrameTiming>[];
  Timer? _timer;
  var _window = 0;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_collect);
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _flush());
  }

  @override
  void dispose() {
    _timer?.cancel();
    SchedulerBinding.instance.removeTimingsCallback(_collect);
    _flush();
    super.dispose();
  }

  void _collect(List<FrameTiming> timings) => _timings.addAll(timings);

  void _flush() {
    final timings = List<FrameTiming>.of(_timings);
    _timings.clear();
    if (timings.isEmpty) return;
    _window += 1;
    debugPrint(
      'LIQUID_GLASS_WORKBENCH_WINDOW:${jsonEncode(<String, Object?>{
        'window': _window,
        'frameCount': timings.length,
        'buildP95Micros': _framePercentile(
          timings,
          .95,
          (timing) => timing.buildDuration,
        ),
        'rasterP50Micros': _framePercentile(
          timings,
          .5,
          (timing) => timing.rasterDuration,
        ),
        'rasterP95Micros': _framePercentile(
          timings,
          .95,
          (timing) => timing.rasterDuration,
        ),
      })}',
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

int _framePercentile(
  List<FrameTiming> timings,
  double percentile,
  Duration Function(FrameTiming timing) select,
) {
  final values =
      timings
          .map((timing) => select(timing).inMicroseconds)
          .toList(growable: false)
        ..sort();
  return values[((values.length - 1) * percentile).round()];
}

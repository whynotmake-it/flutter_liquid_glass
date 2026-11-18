// The gallery's device check: a person with a phone we have never held runs
// the grid with one tap and sends back a file. No computer, no touches.
//
// What a phone tells an app: frame times, the frame rate, a rough time of the
// GPU's work (see GridRunner), its thermal status and, on Android, the
// battery's temperature and current. No GPU counters and no rail power.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/perf/grid.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const _channel = MethodChannel('bench/device');

Future<T?> _device<T>(String method, [Object? arguments]) async {
  try {
    return await _channel.invokeMethod<T>(method, arguments);
  } on MissingPluginException {
    return null;
  }
}

Future<Map<String, Object?>?> _thermal() async =>
    (await _device<Map<Object?, Object?>>('thermal'))?.cast<String, Object?>();

/// Replaces the running app with the check, so that nothing of the app stays
/// behind what it measures, and with [leave]'s app when it ends.
void runDeviceCheck({required VoidCallback leave}) =>
    runApp(_DeviceCheckApp(leave: leave));

class _DeviceCheckApp extends StatefulWidget {
  const _DeviceCheckApp({required this.leave});

  final VoidCallback leave;

  @override
  State<_DeviceCheckApp> createState() => _DeviceCheckAppState();
}

enum _Stage { intro, running, done }

class _DeviceCheckAppState extends State<_DeviceCheckApp> {
  static const _sustained = GridCell(GridContent.photos, GridGlass.chrome);

  final _controller = GridStageController();
  var _stage = _Stage.intro;
  var _status = '';
  Map<String, Object?>? _report;
  String? _sent;

  final _renderer = ValueNotifier<GlassRenderer>(const LiquidGlassRenderer());

  // The app's home stays one route, so what it shows changes below it.
  final _changed = ValueNotifier<int>(0);

  void _update(VoidCallback change) {
    change();
    _changed.value++;
  }

  @override
  void dispose() {
    _renderer.dispose();
    _changed.dispose();
    super.dispose();
  }

  void _setGlass({required bool on}) => _renderer.value = on
      ? const LiquidGlassRenderer()
      : const FlatGlassRenderer();

  Future<void> _start() async {
    _update(() {
      _stage = _Stage.running;
      _sent = null;
    });
    await _device<void>('keepOn', true);
    final runner = GridRunner(stage: _controller, setGlass: _setGlass);
    Map<String, Object?> report;
    try {
      report = await _run(runner);
    } on Object catch (error, stack) {
      report = {'failed': '$error', 'stack': '$stack'};
    }
    runner.stop();
    await _device<void>('keepOn', false);
    _update(() {
      _report = report;
      _stage = _Stage.done;
    });
  }

  Future<Map<String, Object?>> _run(GridRunner runner) async {
    runner.start();
    final view = View.of(context);
    final refresh = view.display.refreshRate;
    final thermalBefore = await _thermal();
    final cells = <Map<String, Object?>>[];
    for (final (index, cell) in gridCells.indexed) {
      _say('Scene ${index + 1} of ${gridCells.length}');
      cells.add(
        await runner.runCell(
          cell,
          pairs: 6,
          proxyRounds: 20,
          snapshot: true,
        ),
      );
    }
    _say('Warming up: a minute of the same scene');
    final sustained = await runner.sustain(
      _sustained,
      seconds: 60,
      stepSeconds: 5,
      sample: _thermal,
    );
    return {
      'version': 1,
      'device': await _device<Map<Object?, Object?>>('passport'),
      'os': Platform.operatingSystemVersion,
      'platform': Platform.operatingSystem,
      'refresh': refresh,
      'screen': [
        view.physicalSize.width,
        view.physicalSize.height,
        view.devicePixelRatio,
      ],
      'errors': runner.errors,
      'thermal_before': thermalBefore,
      'thermal_after': await _thermal(),
      'cells': cells,
      'sustained': sustained,
    };
  }

  void _say(String status) {
    _update(() => _status = status);
  }

  Future<void> _send() async {
    final text = jsonEncode(_report);
    final shared = await _device<bool>('share', {
      'name': 'glass-check-${DateTime.now().millisecondsSinceEpoch}.json',
      'text': text,
    });
    if (shared ?? false) {
      _update(() => _sent = 'Saved in Downloads too.');
      return;
    }
    final small = {
      ..._report!,
      if (_report!['cells'] case final List<Object?> cells)
        'cells': [
          for (final cell in cells)
            {
              for (final MapEntry(:key, :value)
                  in (cell! as Map<Object?, Object?>).entries)
                if (key != 'snapshot') '$key': value,
            },
        ],
    };
    await Clipboard.setData(ClipboardData(text: jsonEncode(small)));
    _update(() => _sent = 'Copied to the clipboard, without the pictures.');
  }

  @override
  Widget build(BuildContext context) => GridApp(
    renderer: _renderer,
    home: ListenableBuilder(
      listenable: _changed,
      builder: (context, _) =>
          _stage == _Stage.running ? _running(context) : _still(context),
    ),
  );

  Widget _running(BuildContext context) => PopScope(
    canPop: false,
    child: Stack(
      fit: StackFit.expand,
      children: [
        GridStage(controller: _controller),
        Center(
          child: RepaintBoundary(
            child: IgnorePointer(
              child: ColoredBox(
                color: const Color(0xCC000000),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _status,
                    style: const TextStyle(color: Color(0xFFFFFFFF)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _still(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (_, _) => widget.leave(),
    child: switch (_stage) {
      _Stage.intro => _message(
        title: 'Device check',
        text:
            'Measures how this phone draws glass, in about six minutes. Put '
            'it on a table and leave it: nothing needs a touch, the phone may '
            'get warm, and closing the app stops the check.'
            '${Platform.isIOS ? ' Set Auto-Lock to Never first.' : ''}',
        action: GlassButton(onPressed: _start, child: const Text('Start')),
      ),
      _ => _message(
        title: 'Done',
        text: _summary(_report!),
        action: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            GlassButton(onPressed: _send, child: const Text('Send the report')),
            if (_sent case final sent?) Text(sent),
            GlassButton(onPressed: _start, child: const Text('Run again')),
            GlassButton(
              onPressed: widget.leave,
              child: const Text('Back to the gallery'),
            ),
          ],
        ),
      ),
    },
  );

  Widget _message({
    required String title,
    required String text,
    required Widget action,
  }) => GlassPageScaffold(
    navigationBar: GlassNavigationBar(title: Text(title)),
    child: ListView(
      padding: const EdgeInsets.fromLTRB(20, 120, 20, 40),
      children: [
        Text(text),
        const SizedBox(height: 24),
        Center(child: action),
      ],
    ),
  );
}

String _summary(Map<String, Object?> report) {
  if (report['failed'] case final failed?) {
    return 'The check failed: $failed\nThe report says where.';
  }
  final lines = <String>[];
  double value(Map<Object?, Object?> cell, String metric, String key) =>
      ((cell[metric]! as Map)[key] as num?)?.toDouble() ?? 0;
  String ms(double v) => v.toStringAsFixed(1);
  for (final cell in (report['cells']! as List).cast<Map<Object?, Object?>>()) {
    if (cell['frames_a'] == 0) continue;
    final proxy = cell['proxy'] as Map?;
    lines.add(
      '${cell['cell']}: ${value(cell, 'fps', 'b').round()} fps with glass, '
      'UI +${ms(value(cell, 'build_ms', 'delta'))} ms, '
      'raster +${ms(value(cell, 'raster_ms', 'delta'))} ms, '
      'GPU about +${ms(((proxy?['delta_ms'] as num?) ?? 0).toDouble())} ms '
      '(give or take ${ms(((proxy?['se_ms'] as num?) ?? 0).toDouble())})',
    );
  }
  final sustained = (report['sustained']! as List)
      .cast<Map<Object?, Object?>>();
  if (sustained.isNotEmpty) {
    lines.add(
      'After a minute: ${(sustained.first['fps']! as num).round()} fps became '
      '${(sustained.last['fps']! as num).round()} fps.',
    );
  }
  if (report['errors'] case final int errors when errors > 0) {
    lines.add('The app reported $errors errors, so these numbers mean little.');
  }
  return lines.join('\n');
}

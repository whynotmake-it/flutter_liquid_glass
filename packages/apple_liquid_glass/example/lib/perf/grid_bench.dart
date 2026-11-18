// The grid bench as its own app, driven from the Mac (tool/bench/grid.py).
//
// Prints `GLASS_BENCH_AB <cell> <arm> <n> <wall> <frames>` so the Mac can split
// the phone's counters by window, and `GRID_CELL <json>` and `GRID_RUN <json>`
// with what the app itself can see.
//
// One APK serves every run: the Mac sets the Android properties debug.grid.cfg
// and debug.grid.cfg2 before the launch, `key=value` pairs split by `;`:
// window (ms), pairs, settle (ms), cells (names, comma separated), proxy
// (rounds, 0 for none), samples, flat (1 holds the flat renderer). A is flat,
// B glass.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/perf/grid.dart';
import 'package:flutter/widgets.dart';

final _config = <String, String>{};

String _text(String key, String fallback) => _config[key] ?? fallback;

int _number(String key, int fallback) =>
    int.tryParse(_config[key] ?? '') ?? fallback;

Future<void> _readConfig() async {
  if (!Platform.isAndroid) return;
  // An Android property holds 91 characters.
  for (final name in const ['debug.grid.cfg', 'debug.grid.cfg2']) {
    final result = await Process.run('getprop', [name]);
    for (final pair in (result.stdout as String).trim().split(';')) {
      final at = pair.indexOf('=');
      if (at > 0) _config[pair.substring(0, at)] = pair.substring(at + 1);
    }
  }
}

final _renderer = ValueNotifier<GlassRenderer>(const LiquidGlassRenderer());
final _stage = GridStageController();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _readConfig();
  if (_number('flat', 0) == 1) _renderer.value = const FlatGlassRenderer();
  unawaited(precacheGlass());
  runApp(
    GridApp(
      renderer: _renderer,
      home: GridStage(controller: _stage),
    ),
  );
  unawaited(_run());
}

Future<void> _run() async {
  final runner = GridRunner(
    stage: _stage,
    setGlass: ({required on}) => _renderer.value = on
        ? const LiquidGlassRenderer()
        : const FlatGlassRenderer(),
  );
  try {
    runner.start();
    await Future<void>.delayed(const Duration(seconds: 4));
    final only = _text('cells', '');
    final names = only.isEmpty ? null : only.split(',').toSet();
    final started = DateTime.now();
    for (final cell in gridCells) {
      if (names != null && !names.contains(cell.name)) continue;
      final result = await runner.runCell(
        cell,
        windowMs: _number('window', 1000),
        pairs: _number('pairs', 8),
        settleMs: _number('settle', 1500),
        proxyRounds: _number('proxy', 0),
        proxySamples: _number('samples', 3),
      );
      debugPrint('GRID_CELL ${jsonEncode(result)}');
    }
    final view = WidgetsBinding.instance.platformDispatcher.implicitView!;
    debugPrint(
      'GRID_RUN ${jsonEncode({
        'window_ms': _number('window', 1000),
        'pairs': _number('pairs', 8),
        'seconds': DateTime.now().difference(started).inSeconds,
        'errors': runner.errors,
        'os': Platform.operatingSystemVersion,
        'screen': [
          view.physicalSize.width,
          view.physicalSize.height,
          view.devicePixelRatio,
        ],
        'refresh': view.display.refreshRate,
      })}',
    );
  } on Object catch (error, stack) {
    debugPrint('GRID_FAILED $error\n$stack');
  }
  debugPrint('GLASS_BENCH done');
}

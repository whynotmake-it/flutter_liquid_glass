import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// The fragment programs glass draws with, loaded once per asset key and
/// kept for the life of the process.
abstract final class GlassShaderPrograms {
  static final Map<String, ui.FragmentProgram> _programs = {};
  static final Set<String> _failed = {};
  static final Map<String, ui.FragmentShader> _shared = {};

  /// Loads the program of [assetKey].
  ///
  /// Once the returned future completes, [cached] holds it, unless loading
  /// failed: that is reported through [FlutterError] once, and the program is
  /// not asked for again.
  static Future<void> precacheShader(String assetKey) {
    if (_programs.containsKey(assetKey) || _failed.contains(assetKey)) {
      return Future<void>.value();
    }
    return ui.FragmentProgram.fromAsset(assetKey).then(
      (program) => _programs[assetKey] = program,
      onError: (Object error, StackTrace stackTrace) {
        if (!_failed.add(assetKey)) return;
        FlutterError.reportError(
          FlutterErrorDetails(exception: error, stack: stackTrace),
        );
      },
    );
  }

  /// Loads the programs of [assetKeys] (see [precacheShader]).
  static Future<void> precacheShaders(List<String> assetKeys) =>
      Future.wait(assetKeys.map(precacheShader));

  /// The program of [assetKey], once it has loaded.
  static ui.FragmentProgram? cached(String assetKey) => _programs[assetKey];

  /// The program of [assetKey], once it has loaded; until then null, and it
  /// starts loading it ([precacheShader]).
  static ui.FragmentProgram? load(String assetKey) {
    final program = _programs[assetKey];
    if (program == null) unawaited(precacheShader(assetKey));
    return program;
  }

  /// The one shader of the program of [assetKey], shared by every draw that
  /// sets each uniform it reads, once the program has loaded ([load]).
  static ui.FragmentShader? sharedShader(String assetKey) {
    if (_shared[assetKey] case final shader?) return shader;
    final program = load(assetKey);
    if (program == null) return null;
    return _shared[assetKey] = program.fragmentShader();
  }
}

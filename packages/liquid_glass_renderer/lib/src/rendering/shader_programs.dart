import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

/// The fragment programs glass draws with, loaded once per asset key and
/// kept for the life of the process.
abstract final class GlassShaderPrograms {
  static final Map<String, ui.FragmentProgram> _programs = {};

  /// Loads the program of [assetKey].
  ///
  /// Once the returned future completes, [cached] holds it, unless loading
  /// failed (reported through [FlutterError]).
  static Future<void> precacheShader(String assetKey) {
    if (_programs.containsKey(assetKey)) return Future<void>.value();
    return ui.FragmentProgram.fromAsset(assetKey).then(
      (program) => _programs[assetKey] = program,
      onError: (Object error, StackTrace stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(exception: error, stack: stackTrace),
        );
      },
    );
  }

  /// Loads the programs of [assetKeys] (see [precacheShader]).
  static Future<void> precacheShaders(List<String> assetKeys) =>
      Future.wait(assetKeys.map(precacheShader));

  /// Whether the program of [assetKey] has loaded.
  static bool isCached(String assetKey) => _programs.containsKey(assetKey);

  /// The program of [assetKey], once it has loaded.
  static ui.FragmentProgram? cached(String assetKey) => _programs[assetKey];
}

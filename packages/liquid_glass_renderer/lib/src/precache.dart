import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:liquid_glass_renderer/src/internal/final_shader_variant.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/multi_shader_builder.dart';
import 'package:liquid_glass_renderer/src/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';

/// Implementation of [LiquidGlass.precache].
///
/// Without it the first glass on screen paints its fallback for a frame or
/// two while the programs load: fake glass without its surface shader, real
/// glass as fake glass. Await it before `runApp` to load these resources before
/// mounting the first glass layer.
///
/// Loads the fake-glass surface program everywhere, and the real-glass
/// programs plus the Flutter GPU geometry bundle where shader filters are
/// supported. GPU resources are loaded immediately, including on Android;
/// completion does not depend on rendering a frame. Acquiring the engine's GPU
/// context may add startup time. Drawing can still incur first-use GPU work.
/// Failures are reported through
/// [FlutterError] and never thrown; the layers fall back the same way they
/// would without precaching.
Future<void> precacheLiquidGlass() {
  final shaders = Future.wait<void>([
    MultiShaderBuilder.precacheShaders([ShaderKeys.fakeGlassSurface]),
    if (!kIsWeb && ui.ImageFilter.isShaderFilterSupported)
      MultiShaderBuilder.precacheShaders(FinalShaderVariant.assetKeys),
  ]);
  return Future.wait<void>([
    shaders,
    if (!kIsWeb && ui.ImageFilter.isShaderFilterSupported)
      _guard(() async {
        final renderer = await FlutterGpuGeometryRenderer.fromAsset(
          ShaderKeys.gpuGeometryShaderBundle,
        );
        renderer.dispose();
      }),
  ]);
}

Future<void> _guard(Future<void> Function() load) async {
  try {
    await load();
  } on Object catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'liquid_glass_renderer',
        context: ErrorDescription('while precaching liquid glass shaders'),
      ),
    );
  }
}

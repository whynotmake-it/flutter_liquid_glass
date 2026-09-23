import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/multi_shader_builder.dart';
import 'package:liquid_glass_renderer/src/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';

/// Implementation of [LiquidGlass.precache].
///
/// Without it the first glass on screen paints its fallback for a frame or
/// two while the programs load: fake glass without its surface shader, real
/// glass as fake glass. Call it once, for example before `runApp` or on a
/// splash screen, and glass renders fully from its first frame.
///
/// Loads the fake-glass surface program everywhere, and the real-glass
/// programs plus the Flutter GPU geometry bundle where shader filters are
/// supported. On Android, the GPU part initializes the widgets binding if
/// needed and awaits the first rasterized frame, because the Impeller
/// context is unavailable before the first surface frame; calling it before
/// `runApp` therefore lets the GPU portion complete after the first frame.
/// Failures are reported through
/// [FlutterError] and never thrown; the layers fall back the same way they
/// would without precaching.
Future<void> precacheLiquidGlass() {
  final shaders = Future.wait<void>([
    MultiShaderBuilder.precacheShaders([ShaderKeys.fakeGlassSurface]),
    if (!kIsWeb && ui.ImageFilter.isShaderFilterSupported)
      MultiShaderBuilder.precacheShaders([
        ShaderKeys.liquidGlassRender,
        ShaderKeys.liquidGlassMaterialRender,
        ShaderKeys.liquidGlassTintRender,
      ]),
  ]);
  return Future.wait<void>([
    shaders,
    if (!kIsWeb && ui.ImageFilter.isShaderFilterSupported)
      _guard(() async {
        await FlutterGpuGeometryRenderer.waitUntilGpuContextAvailable();
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

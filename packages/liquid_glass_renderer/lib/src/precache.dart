import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/multi_shader_builder.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';

/// Loads and compiles every shader the renderer can use on this platform.
///
/// Without it the first glass on screen paints its fallback for a frame or
/// two while the programs load: fake glass without its surface shader, real
/// glass as fake glass. Call it once, for example before `runApp` or on a
/// splash screen, and glass renders fully from its first frame.
///
/// Loads the fake-glass surface program everywhere, and the real-glass
/// programs plus the Flutter GPU geometry bundle where shader filters are
/// supported. Failures are reported through [FlutterError] and
/// never thrown; the layers fall back the same way they would without
/// precaching.
Future<void> precacheLiquidGlassShaders() async {
  await Future.wait<void>([
    MultiShaderBuilder.precacheShaders([ShaderKeys.fakeGlassSurface]),
    if (!kIsWeb && ui.ImageFilter.isShaderFilterSupported) ...[
      MultiShaderBuilder.precacheShaders([
        ShaderKeys.liquidGlassRender,
        ShaderKeys.liquidGlassMaterialRender,
        ShaderKeys.liquidGlassTintRender,
      ]),
      _guard(() async {
        final renderer = await FlutterGpuGeometryRenderer.fromAsset(
          ShaderKeys.gpuGeometryShaderBundle,
        );
        renderer.dispose();
      }),
    ],
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

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/rendering/final_shader_variant.dart';
import 'package:liquid_glass_renderer/src/rendering/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/shader_programs.dart';
import 'package:liquid_glass_renderer/src/rendering/shaders.dart';
import 'package:liquid_glass_renderer/src/rendering/warm_up.dart';

/// Loads every glass program and the Flutter GPU geometry bundle, and with
/// [warmUp] draws each pipeline once offscreen; `LiquidGlass.precache` calls
/// it.
///
/// The warm-up runs only when every full-glass program and the geometry
/// bundle loaded. Failures are reported through `FlutterError` and never
/// thrown. The returned [LiquidGlassSupport] says whether full glass draws on
/// this device.
Future<LiquidGlassSupport> precacheLiquidGlass({bool warmUp = false}) async {
  final fullGlass = !kIsWeb && ui.ImageFilter.isShaderFilterSupported;
  final finalShaders = FinalShaderVariant.assetKeys;
  FlutterGpuGeometryRenderer? renderer;
  final results = await Future.wait<bool>([
    GlassShaderPrograms.precacheShaders([
      ...ShaderKeys.fakeSurfaceAssets,
      ShaderKeys.bentContent,
    ]).then((_) => true),
    if (fullGlass) ...[
      GlassShaderPrograms.precacheShaders([
        ...finalShaders,
        ShaderKeys.backdropFrost,
        ShaderKeys.backdropFrostAxis,
        ShaderKeys.backdropFrostSquare,
        ShaderKeys.backdropHazeStrip,
        ShaderKeys.backdropHazeMix,
      ]).then((_) => finalShaders.every(GlassShaderPrograms.isCached)),
      _guard(() async {
        renderer = await FlutterGpuGeometryRenderer.fromAsset(
          ShaderKeys.gpuGeometryShaderBundle,
        );
      }),
    ],
  ]);
  try {
    if (!fullGlass) {
      return const LiquidGlassSupport(
        deviceClass: LiquidGlassDeviceClass.noShaderFilters,
        unavailableReason: 'Impeller shader filters are unavailable.',
      );
    }
    if (!results.every((loaded) => loaded)) {
      return const LiquidGlassSupport(
        deviceClass: LiquidGlassDeviceClass.unknown,
        unavailableReason:
            'A full-glass program or the Flutter GPU geometry bundle did not '
            'load; the error was reported through FlutterError.',
      );
    }
    final loaded = renderer!;
    if (warmUp) {
      await (_warmUp ??= _guard(() => warmLiquidGlassPipelines(loaded)));
    }
    return LiquidGlassSupport(deviceClass: loaded.deviceClass);
  } finally {
    renderer?.dispose();
  }
}

// The pipelines a warm-up creates last as long as the process.
Future<bool>? _warmUp;

Future<bool> _guard(Future<void> Function() load) async {
  try {
    await load();
    return true;
  } on Object catch (error, stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'liquid_glass_renderer',
        context: ErrorDescription('while precaching liquid glass shaders'),
      ),
    );
    return false;
  }
}

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:alchemist/alchemist.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/shaders.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  isLocalTest = true;
  if (!_expectFallback && !_drawsGlass()) {
    throw StateError(
      'The renderer tests draw with Impeller and Flutter GPU, which this '
      'run has off. Run them with '
      '`flutter test --enable-impeller --enable-flutter-gpu`, as melos.yaml '
      'does, or with --dart-define=EXPECT_FLUTTER_GPU_FALLBACK=true for the '
      'fallback.',
    );
  }

  await LiquidGlass.precache();
  // A golden is the same whichever tests ran before it.
  setUp(FlutterGpuGeometryRenderer.debugResetPages);

  await AlchemistConfig.runWithConfig(
    config: AlchemistConfig(
      ciGoldensConfig: const CiGoldensConfig(enabled: false),
      platformGoldensConfig: PlatformGoldensConfig(
        platforms: {HostPlatform.macOS},
      ),
    ),
    run: testMain,
  );

  await _publishSnaptestDocs();
}

Future<void> _publishSnaptestDocs() async {
  final tests = Directory('test');
  if (!tests.existsSync()) return;
  final destination = Directory('doc/generated');
  await for (final entity in tests.list(recursive: true)) {
    if (entity is! File ||
        !entity.path.contains('/.snaptest/docs/') ||
        !entity.path.endsWith('.png')) {
      continue;
    }
    await destination.create(recursive: true);
    final name = entity.uri.pathSegments.last;
    await entity.copy('${destination.path}/$name');
  }
}

const _expectFallback = bool.fromEnvironment('EXPECT_FLUTTER_GPU_FALLBACK');

// Whether this run can draw real glass: Impeller's shader filters and a
// Flutter GPU context.
bool _drawsGlass() {
  if (!ui.ImageFilter.isShaderFilterSupported) return false;
  try {
    return gpu.gpuContext.defaultColorFormat != gpu.PixelFormat.unknown;
  } on Object {
    return false;
  }
}

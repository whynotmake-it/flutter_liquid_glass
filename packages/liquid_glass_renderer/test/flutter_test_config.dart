import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:alchemist/alchemist.dart';
import 'package:liquid_glass_renderer/src/internal/multi_shader_builder.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  isLocalTest = true;

  await MultiShaderBuilder.precacheShaders([
    if (ImageFilter.isShaderFilterSupported) ...[
      ShaderKeys.liquidGlassRender,
    ],
  ]);

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

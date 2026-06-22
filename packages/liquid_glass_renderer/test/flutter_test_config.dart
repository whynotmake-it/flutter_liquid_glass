import 'dart:async';
import 'dart:ui';

import 'package:alchemist/alchemist.dart';
import 'package:liquid_glass_renderer/src/internal/multi_shader_builder.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  isLocalTest = true;

  await MultiShaderBuilder.precacheShaders([
    ShaderKeys.fakeGlassColor,
    if (ImageFilter.isShaderFilterSupported) ...[
      ShaderKeys.liquidGlassRender,
    ],
  ]);

  return AlchemistConfig.runWithConfig(
    config: AlchemistConfig(
      ciGoldensConfig: const CiGoldensConfig(enabled: false),
      platformGoldensConfig: PlatformGoldensConfig(
        platforms: {HostPlatform.macOS},
      ),
    ),
    run: testMain,
  );
}

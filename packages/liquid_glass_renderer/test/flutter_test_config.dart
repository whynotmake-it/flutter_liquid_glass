import 'dart:async';

import 'package:alchemist/alchemist.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await ShaderBuilder.precacheShader(liquidGlassShader);
  await ShaderBuilder.precacheShader(arbitraryShader);

  return AlchemistConfig.runWithConfig(
    config: AlchemistConfig(
      ciGoldensConfig: const CiGoldensConfig(),
      platformGoldensConfig: PlatformGoldensConfig(
        platforms: {HostPlatform.macOS},
      ),
    ),
    run: testMain,
  );
}

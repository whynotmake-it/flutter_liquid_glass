import 'dart:async';

import 'package:alchemist/alchemist.dart';
import 'package:liquid_glass_renderer/src/internal/multi_shader_builder.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await MultiShaderBuilder.precacheShaders([
    ShaderKeys.blendedGeometry,
    ShaderKeys.liquidGlassRender,
    ShaderKeys.lighting,
    ShaderKeys.liquidGlassFilterShader,
    ShaderKeys.glassify,
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

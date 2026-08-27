import 'dart:async';

import 'package:alchemist/alchemist.dart';
import 'package:liquid_glass_renderer/src/internal/multi_shader_builder.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  isLocalTest = true;

  await MultiShaderBuilder.precacheShaders([
    ShaderKeys.fakeGlassColor,
    ShaderKeys.blendedGeometry,
    ShaderKeys.liquidGlassRender,
    ShaderKeys.liquidGlassFilterShader,
    ShaderKeys.glassify,
  ]);

  return AlchemistConfig.runWithConfig(
    config: AlchemistConfig(
      ciGoldensConfig: const CiGoldensConfig(enabled: false),
      platformGoldensConfig: PlatformGoldensConfig(
        // Flutter 3.44 validates test variants before applying tag filters.
        // Include Linux so the non-golden CI lane can discover (then exclude)
        // golden tests without Alchemist producing an empty variant.
        platforms: {HostPlatform.macOS, HostPlatform.linux},
      ),
    ),
    run: testMain,
  );
}

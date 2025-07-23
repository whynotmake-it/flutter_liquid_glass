import 'dart:async';

import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';
import 'package:snaptest/snaptest.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await ShaderBuilder.precacheShader(liquidGlassShader);
  await ShaderBuilder.precacheShader(arbitraryShader);

  await loadFontsAndIcons();

  SnaptestSettings.global = const SnaptestSettings.rendered(
    devices: [WidgetTesterDevice()],
  );

  await testMain();
}

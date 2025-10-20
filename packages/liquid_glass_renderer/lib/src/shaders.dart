// ignore_for_file: public_member_api_docs

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:meta/meta.dart';

final String _shadersRoot =
    !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')
        ? ''
        : 'packages/liquid_glass_renderer/';

@internal
abstract class ShaderKeys {
  const ShaderKeys._();

  static final blendedGeometry =
      '${_shadersRoot}lib/assets/shaders/liquid_glass_geometry_blended.frag';

  static final liquidGlassRender =
      '${_shadersRoot}lib/assets/shaders/liquid_glass_final_render.frag';

  static final lighting =
      '${_shadersRoot}lib/assets/shaders/liquid_glass_lighting.frag';

  static final String liquidGlassFilterShader =
      '${_shadersRoot}lib/assets/shaders/liquid_glass_filter.frag';

  static final String glassify =
      '${_shadersRoot}lib/assets/shaders/liquid_glass_arbitrary.frag';

  @Deprecated('This shader is only for legacy reasons and reference.')
  static final legacyLiquidGlass =
      '${_shadersRoot}lib/assets/shaders/liquid_glass.frag';
}

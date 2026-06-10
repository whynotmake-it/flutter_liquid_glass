// ignore_for_file: public_member_api_docs

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:meta/meta.dart';

@visibleForTesting
bool isLocalTest = false;

final String _shadersRoot = !kIsWeb && isLocalTest
    ? ''
    : 'packages/liquid_glass_renderer/';

@internal
abstract class ShaderKeys {
  const ShaderKeys._();

  static final blendedGeometry =
      '${_shadersRoot}lib/assets/shaders/liquid_glass_geometry_blended.frag';

  static final liquidGlassRender =
      '${_shadersRoot}lib/assets/shaders/liquid_glass_final_render.frag';

  static final liquidGlassSpecular =
      '${_shadersRoot}lib/assets/shaders/liquid_glass_specular.frag';

  static final String liquidGlassFilterShader =
      '${_shadersRoot}lib/assets/shaders/liquid_glass_filter.frag';

  static final String fakeGlassColor =
      '${_shadersRoot}lib/assets/shaders/fake_glass_color.frag';

  @Deprecated('This shader is only for legacy reasons and reference.')
  static final legacyLiquidGlass =
      '${_shadersRoot}lib/assets/shaders/liquid_glass.frag';
}

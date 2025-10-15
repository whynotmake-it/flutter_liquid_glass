// ignore_for_file: public_member_api_docs

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:meta/meta.dart';

final String _shadersRoot =
    !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')
        ? ''
        : 'packages/liquid_glass_renderer/';

@internal
final String liquidGlassShader =
    '${_shadersRoot}lib/assets/shaders/liquid_glass.frag';

@internal
final String liquidGlassGeometryShader =
    '${_shadersRoot}lib/assets/shaders/liquid_glass_geometry_blended.frag';

@internal
final String liquidGlassRenderShader =
    '${_shadersRoot}lib/assets/shaders/liquid_glass_final_render.frag';

@internal
final String liquidGlassLightingShader =
    '${_shadersRoot}lib/assets/shaders/liquid_glass_lighting.frag';

@internal
final String liquidGlassFilterShader =
    '${_shadersRoot}lib/assets/shaders/liquid_glass_filter.frag';

@internal
final String arbitraryShader =
    '${_shadersRoot}lib/assets/shaders/liquid_glass_arbitrary.frag';

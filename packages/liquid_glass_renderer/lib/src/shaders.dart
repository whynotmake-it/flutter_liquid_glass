// ignore_for_file: public_member_api_docs

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';

final String _shadersRoot =
    !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')
        ? ''
        : 'packages/liquid_glass_renderer/';

@internal
final String liquidGlassShader =
    '${_shadersRoot}lib/assets/shaders/liquid_glass.frag';

@internal
final String arbitraryShader =
    '${_shadersRoot}lib/assets/shaders/liquid_glass_arbitrary.frag';

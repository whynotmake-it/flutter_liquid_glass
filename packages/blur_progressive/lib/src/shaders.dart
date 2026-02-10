// ignore_for_file: public_member_api_docs

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:meta/meta.dart';

final String _shadersRoot =
    !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')
        ? ''
        : 'packages/blur_progressive/';

@internal
abstract class ShaderKeys {
  const ShaderKeys._();

  static final progressiveBlur =
      '${_shadersRoot}lib/assets/shaders/progressive_blur.frag';
}

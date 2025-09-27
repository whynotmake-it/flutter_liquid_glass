// ignore_for_file: public_member_api_docs

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:meta/meta.dart';

final String _shadersRoot =
    !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')
        ? ''
        : 'packages/liquid_glass_renderer/';

// Internal asset paths
const String _liquidGlassShader = 'lib/assets/shaders/liquid_glass.frag';
const String _liquidGlassEmulatorShader = 'lib/assets/shaders/liquid_glass.emulator.frag';

const String _arbitraryShader = 'lib/assets/shaders/liquid_glass_arbitrary.frag';
const String _arbitraryEmulatorShader = 'lib/assets/shaders/liquid_glass_arbitrary.emulator.frag';

String _assetPath(String relative) => '$_shadersRoot$relative';

bool _isEmulator = false;

/// Force using the emulator-compatible shaders so LiquidGlass renders correctly
/// on emulators.
void forceLiquidGlassEmulatorRendering() => _isEmulator = true;

@internal
String get liquidGlassShader => _isEmulator
    ? _assetPath(_liquidGlassEmulatorShader)
    : _assetPath(_liquidGlassShader);

@internal
String get arbitraryShader => _isEmulator
    ? _assetPath(_arbitraryEmulatorShader)
    : _assetPath(_arbitraryShader);
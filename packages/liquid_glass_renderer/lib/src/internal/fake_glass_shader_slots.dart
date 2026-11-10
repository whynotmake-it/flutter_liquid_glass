import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:liquid_glass_renderer/src/internal/multi_shader_builder.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';

/// One FakeGlass surface [ui.FragmentShader] per draw.
///
/// WORKAROUND for the web (CanvasKit): there a drawn [ui.FragmentShader]
/// keeps reading its uniforms until the frame is rasterized. Flutter keeps
/// a fragment shader's uniforms in WASM memory and CanvasKit's
/// `RuntimeEffect.makeShader` does not copy uniforms it gets that way, so
/// every draw recorded with one shader object renders with the values that
/// object holds at raster time — the ones set last. Drawing the surface,
/// glint and border ring of every shape with one shader made each of them
/// use the last shape's size and pass (a second, wrongly sized glint ring on
/// top of the glass).
///
/// So each draw gets its own shader from the same program, keyed by what it
/// draws, and keeps it while it is drawn again each paint. Its uniforms are
/// only rewritten when the picture that drew it is recorded anew. Elsewhere
/// uniforms are captured when drawn, and the extra shaders cost little.
class FakeGlassShaderSlots {
  final Map<Object, ui.FragmentShader> _shaders = {};
  Set<Object>? _used;

  /// The shader for the draw [key]: its own instance of [base]'s program,
  /// or [base] itself while that program is not loaded.
  ui.FragmentShader shaderFor(Object key, ui.FragmentShader base) {
    _used?.add(key);
    if (_shaders[key] case final shader?) return shader;
    final program = MultiShaderBuilder.cachedProgram(
      ShaderKeys.fakeGlassSurface,
    );
    if (program == null) return base;
    return _shaders[key] = program.fragmentShader();
  }

  /// Starts a paint that draws all of this owner's surfaces; [endPaint]
  /// then disposes the shaders of the draws it no longer made.
  void beginPaint() => _used = {};

  /// See [beginPaint].
  void endPaint() {
    final used = _used;
    _used = null;
    if (used == null) return;
    _shaders.removeWhere((key, shader) {
      if (used.contains(key)) return false;
      shader.dispose();
      return true;
    });
  }

  /// Disposes every shader.
  void dispose() {
    for (final shader in _shaders.values) {
      shader.dispose();
    }
    _shaders.clear();
    _used = null;
  }

  /// How many shaders are held.
  @visibleForTesting
  int get debugCount => _shaders.length;
}

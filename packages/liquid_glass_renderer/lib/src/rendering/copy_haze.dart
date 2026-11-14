import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:liquid_glass_renderer/composer.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/rendering/copy_frost.dart';
import 'package:liquid_glass_renderer/src/rendering/pinned_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/shader_filter.dart';
import 'package:liquid_glass_renderer/src/rendering/shader_programs.dart';
import 'package:liquid_glass_renderer/src/rendering/shaders.dart';
import 'package:meta/meta.dart';

/// Whether glass draws its haze into the copies it reads: false frosts it
/// by the one blur that stands in for the haze, as where it reads the
/// backdrop live. For comparing the two; null and true draw the haze.
bool? debugGlassHaze;

/// The haze mixed into a copy at the copy's own pixels: two layers the copy
/// is drawn in. The inner one averages the copy into a strip under it
/// ([HazeStrip]); the outer one reads the copy's wide blur out of the strip
/// and mixes it into the copy.
///
/// The copy is read where it lies, in the layer that holds it, so a haze
/// reads no backdrop, draws the page once and takes two small passes of the
/// frame. The mix is iOS 27's, every channel on display values:
/// `m = c + lighten * (max(c, f) - c) + darken * (min(c, f) - c)` for the
/// copy `c` and its wide blur `f`, then `mix(m, f, cover)`.
///
/// NEAR: the wide blur is a bell as wide as the Gaussian over cells of the
/// copy, not the Gaussian over its pixels. At the copy's edge it weighs the
/// edge's own pixels again for what lies past it. A layer that a clip cuts
/// short of the strip is mixed with no haze.
@internal
final class CopyHaze {
  const CopyHaze._(this.size, this._passes);

  /// The size of the layers, in the copy's pixels: the copy and the strip
  /// under it.
  final ui.Size size;

  // The filters, outermost first.
  final List<ui.ImageFilter> _passes;

  /// Whether the haze's programs are loaded; where they are not, starts
  /// loading them.
  static bool get ready {
    final strip = _loaded(ShaderKeys.backdropHazeStrip);
    final mix = _loaded(ShaderKeys.backdropHazeMix);
    return strip && mix;
  }

  static bool _loaded(String key) {
    if (GlassShaderPrograms.isCached(key)) return true;
    unawaited(GlassShaderPrograms.precacheShader(key));
    return false;
  }

  /// The size of the layers that mix [haze] into a copy that fills [copy]
  /// of its layer's pixels, [pixels] of them a logical pixel.
  static ui.Size sizeOf(
    LiquidGlassHaze haze,
    ui.Size copy,
    double pixels,
  ) {
    final strip = HazeStrip(haze.sigma * pixels, copy);
    return ui.Size(
      max(copy.width, strip.across.toDouble()),
      copy.height + strip.rows,
    );
  }

  /// What mixes [haze] into a copy whose layer it fills [copy] pixels of
  /// from the top left, the copy itself lying at [rect] of them, [pixels] to
  /// a logical pixel; or null where there is nothing to mix or the programs
  /// are not loaded yet.
  static CopyHaze? of(
    LiquidGlassHaze haze, {
    required ui.Size copy,
    required ui.Rect rect,
    required double pixels,
  }) {
    if (haze.isNone || rect.isEmpty) return null;
    final key = (haze, copy, rect, pixels);
    if (_held[key] case final held?) return held;
    final stripShader = _shader(ShaderKeys.backdropHazeStrip);
    final mixShader = _shader(ShaderKeys.backdropHazeMix);
    if (stripShader == null || mixShader == null) return null;
    if (_held.length >= 32) _held.clear();

    final strip = HazeStrip(haze.sigma * pixels, copy);
    final reads = strip.cell / 2;
    final top = copy.height;
    final bounds = rect.deflate(0.5);

    _put(stripShader, 'uBounds', [
      bounds.left,
      bounds.top,
      bounds.right,
      bounds.bottom,
    ]);
    _put(stripShader, 'uStrip', [
      top,
      strip.cell.toDouble(),
      reads,
      1 / (reads * reads),
    ]);
    stripShader.setImageSampler(
      0,
      transparentPixel,
      filterQuality: ui.FilterQuality.low,
    );
    // Each shader holds other uniforms by the time a scene takes its
    // filter.
    final average = shaderFilterNow(stripShader);

    _put(mixShader, 'uRect', [rect.left, rect.top, rect.right, rect.bottom]);
    _put(mixShader, 'uStrip', [
      top,
      1 / strip.cell,
      strip.across.toDouble(),
      strip.down.toDouble(),
    ]);
    _put(mixShader, 'uReach', [1 / (strip.reach * strip.reach)]);
    _put(mixShader, 'uMix', [
      haze.lighten.clamp(0.0, 1.0),
      haze.darken.clamp(0.0, 1.0),
      haze.cover.clamp(0.0, 1.0),
    ]);
    mixShader.setImageSampler(
      0,
      transparentPixel,
      filterQuality: ui.FilterQuality.low,
    );
    final mix = shaderFilterNow(mixShader);

    return _held[key] = CopyHaze._(sizeOf(haze, copy, pixels), [mix, average]);
  }

  /// Pushes the haze's layers, each held to [size] from [origin]; what is
  /// drawn until [pop], inside the copy's part of them, comes out mixed
  /// with its wide blur. In a target whose pixels each stand for [scale] of
  /// the coordinates [builder] draws in, [size] is counted in the target's.
  void push(ui.SceneBuilder builder, ui.Offset origin, {int scale = 1}) {
    for (final pass in _passes) {
      PinnedLayers.push(builder, pass, origin, size * scale.toDouble());
    }
  }

  /// Ends what [push] began.
  void pop(ui.SceneBuilder builder) {
    for (var i = 0; i < _passes.length; i++) {
      builder.pop();
    }
  }
}

final _shaders = <String, ui.FragmentShader>{};

// The one shader of the program [key], or null before it is loaded.
ui.FragmentShader? _shader(String key) {
  if (_shaders[key] case final held?) return held;
  final made = GlassShaderPrograms.cached(key)?.fragmentShader();
  if (made != null) _shaders[key] = made;
  return made;
}

// Chrome over a scroll keeps a copy's place, so its haze too.
final _held = <Object, CopyHaze>{};

// Writes [values] into the uniform [name] of [shader].
void _put(ui.FragmentShader shader, String name, List<double> values) {
  final at = shader.getUniformFloat(name).shaderIndex;
  for (var i = 0; i < values.length; i++) {
    shader.setFloat(at + i, values[i]);
  }
}

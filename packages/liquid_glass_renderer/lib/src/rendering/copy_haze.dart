import 'dart:ui' as ui;

import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/plan/copy_place.dart';
import 'package:liquid_glass_renderer/src/plan/read_layout.dart';
import 'package:liquid_glass_renderer/src/rendering/copy_frost.dart';
import 'package:liquid_glass_renderer/src/rendering/pinned_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/shader_filter.dart';
import 'package:liquid_glass_renderer/src/rendering/shader_programs.dart';
import 'package:liquid_glass_renderer/src/rendering/shader_uniforms.dart';
import 'package:liquid_glass_renderer/src/rendering/shaders.dart';
import 'package:meta/meta.dart';

/// Whether glass draws its haze into the copies it reads: false frosts it
/// by the one blur that stands in for the haze, as where it reads the
/// backdrop, so a test can hold a copy against a backdrop read. Null and
/// true draw the haze.
bool? debugGlassHaze;

/// The haze mixed into a copy at the copy's own pixels: two layers the copy
/// is drawn in. The inner one averages the copy into a strip under it
/// ([HazeStrip]); the outer one reads the copy's wide blur out of the strip
/// and mixes it into the copy.
///
/// The mix is iOS 27's, every channel on display values:
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
    final strip = GlassShaderPrograms.load(ShaderKeys.backdropHazeStrip);
    final mix = GlassShaderPrograms.load(ShaderKeys.backdropHazeMix);
    return strip != null && mix != null;
  }

  /// What mixes [haze] into a copy laid out as [layout] says, or null
  /// where there is nothing to mix or the programs are not loaded yet.
  static CopyHaze? of(LiquidGlassFixedHaze haze, HazeLayout layout) {
    final (:copy, :rect, :pixels, :origin, :size) = layout;
    if (rect.isEmpty) return null;
    final strip = HazeStrip(haze.sigma * pixels, copy, origin: origin);
    final key = (haze, copy, rect, pixels, strip.phase);
    if (_held[key] case final held?) return held;
    final stripShader = GlassShaderPrograms.sharedShader(
      ShaderKeys.backdropHazeStrip,
    );
    final mixShader = GlassShaderPrograms.sharedShader(
      ShaderKeys.backdropHazeMix,
    );
    if (stripShader == null || mixShader == null) return null;
    if (_held.length >= 32) _held.clear();

    final reads = strip.cell / 2;
    final top = copy.height;
    final bounds = rect.deflate(0.5);

    putUniform(stripShader, 'uBounds', [
      bounds.left,
      bounds.top,
      bounds.right,
      bounds.bottom,
    ]);
    putUniform(stripShader, 'uStrip', [
      top,
      strip.cell.toDouble(),
      reads,
      1 / (reads * reads),
    ]);
    putUniform(stripShader, 'uPhase', [strip.phase.dx, strip.phase.dy]);
    stripShader.setImageSampler(
      0,
      transparentPixel,
      filterQuality: ui.FilterQuality.low,
    );
    // Each shader holds other uniforms by the time a scene takes its
    // filter.
    final average = shaderFilterNow(stripShader);

    putUniform(mixShader, 'uRect', [
      rect.left,
      rect.top,
      rect.right,
      rect.bottom,
    ]);
    putUniform(mixShader, 'uStrip', [
      top,
      1 / strip.cell,
      strip.across.toDouble(),
      strip.down.toDouble(),
    ]);
    putUniform(mixShader, 'uPhase', [
      strip.phase.dx / strip.cell,
      strip.phase.dy / strip.cell,
    ]);
    putUniform(mixShader, 'uReach', [1 / (strip.reach * strip.reach)]);
    putUniform(mixShader, 'uMix', [
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

    return _held[key] = CopyHaze._(size, [mix, average]);
  }

  /// Pushes the haze's layers, each held to [size] from [origin]; what is drawn
  /// until [pop], inside the copy's part of them, comes out mixed with its wide
  /// blur. In a target whose pixels each stand for [targetShare] of the
  /// coordinates [builder] draws in, [size] is counted in the target's.
  void push(ui.SceneBuilder builder, ui.Offset origin, {int targetShare = 1}) {
    for (final pass in _passes) {
      PinnedLayers.push(builder, pass, origin, size * targetShare.toDouble());
    }
  }

  /// Ends what [push] began.
  void pop(ui.SceneBuilder builder) {
    for (var i = 0; i < _passes.length; i++) {
      builder.pop();
    }
  }
}

// Chrome over a scroll keeps a copy's place, so its haze too.
final _held = <Object, CopyHaze>{};

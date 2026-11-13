import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/rendering/ancestor_clip.dart';
import 'package:liquid_glass_renderer/src/rendering/follower_transform.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_blur.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';
import 'package:meta/meta.dart';

/// Seeds an enclosing fractional-opacity surface with its backdrop.
///
/// A backdrop filter inside a fractional `Opacity` or `FadeTransition` only
/// sees that opacity pass, which starts transparent. An identity backdrop
/// filter first copies the real backdrop into it, so the glass inside blurs
/// and refracts what is actually behind it.
@internal
class GlassCompositionProbe {
  final _layer = LayerHandle<OpacitySeedLayer>();

  /// Whether the owner paints inside a fractional opacity pass that a live
  /// backdrop read needs seeded, also while [suppressed].
  bool get seeding => _wanted;
  bool _wanted = false;

  /// Leaves the pass unseeded while the owner reads no backdrop.
  bool get suppressed => _suppressed;
  bool _suppressed = false;
  set suppressed(bool value) {
    if (value == _suppressed) return;
    _suppressed = value;
    _layer.layer?.seeded = _wanted && !value;
  }

  /// Paints [painter] inside the seed layer, which seeds only while
  /// [syncOpacity] finds a fractional opacity above.
  void paint(
    PaintingContext context,
    Offset offset,
    PaintingContextCallback painter, {
    required RenderObject owner,
  }) {
    final layer = _layer.layer ??= OpacitySeedLayer()
      ..filter = identityColorFilter;
    syncOpacity(owner);
    context.pushLayer(layer, painter, offset);
  }

  /// Runs from paint and from the composer's pass, before the update pass.
  ///
  /// Seeds iff an ancestor between [owner] and the nearest enclosing
  /// [LiquidGlassRenderObject] has fractional native opacity and none is
  /// fully transparent.
  void syncOpacity(RenderObject owner) {
    final layer = _layer.layer;
    if (layer == null) return;
    var fractional = false;
    var blocked = false;
    // Glass nearby shares its path up, and a scroll polls all of it.
    final memo = FrameAncestors.current;
    List<RenderObject>? opaque;
    for (
      var ancestor = owner.parent;
      ancestor != null && ancestor is! LiquidGlassRenderObject;
      ancestor = ancestor.parent
    ) {
      final opacity = switch (ancestor) {
        RenderOpacity() => ancestor.opacity,
        RenderAnimatedOpacity() => ancestor.opacity.value,
        _ => null,
      };
      if (opacity != null) {
        final alpha = ui.Color.getAlphaFromOpacity(opacity);
        if (alpha == 0) {
          blocked = true;
          break;
        }
        if (alpha < 255) {
          fractional = true;
          opaque?.clear();
        }
      }
      if (memo != null && ancestor.isRepaintBoundary) {
        if (memo.opaqueAbove(ancestor)) break;
        (opaque ??= []).add(ancestor);
      }
    }
    if (memo != null && opaque != null && !blocked) {
      opaque.forEach(memo.noteOpaqueAbove);
    }
    _wanted = fractional && !blocked;
    layer.seeded = _wanted && !_suppressed;
  }

  /// Screen-space origin of the opacity pass [owner] paints into while
  /// [seeding]: Impeller bounds that pass by the enclosing clips, rounded out
  /// to device pixels. Zero when nothing clips.
  static Offset seededPassOrigin(RenderObject owner, double devicePixelRatio) {
    final clip = screenClipAbove(owner);
    if (clip == null) return Offset.zero;
    return Offset(
      (clip.left * devicePixelRatio).floorToDouble() / devicePixelRatio,
      (clip.top * devicePixelRatio).floorToDouble() / devicePixelRatio,
    );
  }

  /// Releases the retained seed layer.
  void dispose() => _layer.layer = null;
}

@internal
class OpacitySeedLayer extends BackdropFilterLayer {
  bool _seeded = false;
  bool get seeded => _seeded;
  set seeded(bool value) {
    if (value == _seeded) return;
    _seeded = value;
    markNeedsAddToScene();
  }

  @override
  void addToScene(ui.SceneBuilder builder) {
    if (_seeded) {
      super.addToScene(builder);
    } else {
      // Drop the native pass, but keep the retained children.
      engineLayer = null;
      addChildrenToScene(builder);
    }
  }
}

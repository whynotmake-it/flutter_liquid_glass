import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/internal/ancestor_clip.dart';
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
  final _layer = LayerHandle<_OpacitySeedLayer>();

  static const _identity = ColorFilter.matrix(<double>[
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);

  /// Whether the owner currently paints inside a seeded opacity pass.
  bool get seeding => _layer.layer?.seeded ?? false;

  /// Paints the original sequence, seeding only fractional-opacity surfaces.
  void paint(
    PaintingContext context,
    Offset offset,
    PaintingContextCallback painter, {
    required RenderObject owner,
  }) {
    final layer = _layer.layer ??= _OpacitySeedLayer()..filter = _identity;
    syncOpacity(owner);
    context.pushLayer(layer, painter, offset);
  }

  /// Updates before retained-layer dirtiness is propagated for this frame.
  ///
  /// Seeds iff an ancestor between [owner] and the nearest enclosing
  /// [LiquidGlassLayerRenderObject] has fractional native opacity and none is
  /// fully transparent.
  void syncOpacity(RenderObject owner) {
    final layer = _layer.layer;
    if (layer == null) return;
    var fractional = false;
    var blocked = false;
    for (
      var ancestor = owner.parent;
      ancestor != null && ancestor is! LiquidGlassLayerRenderObject;
      ancestor = ancestor.parent
    ) {
      final alpha = ui.Color.getAlphaFromOpacity(
        switch (ancestor) {
          RenderOpacity() => ancestor.opacity,
          RenderAnimatedOpacity() => ancestor.opacity.value,
          _ => 1.0,
        },
      );
      if (alpha == 0) {
        blocked = true;
        break;
      }
      if (alpha < 255) fractional = true;
    }
    layer.seeded = fractional && !blocked;
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

class _OpacitySeedLayer extends BackdropFilterLayer {
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

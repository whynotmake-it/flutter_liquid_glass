import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';
import 'package:meta/meta.dart';

/// Seeds enclosing fractional-opacity surfaces with their backdrop while
/// preserving the original child clips and opaque rendering path.
@internal
class GlassCompositionProbe {
  final _layer = LayerHandle<_OpacitySeedLayer>();

  static const _identity = ColorFilter.matrix([
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ]);

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
  /// [LiquidGlassLayerRenderObject] has fractional native opacity and none
  /// has fully transparent opacity.
  void syncOpacity(RenderObject owner) {
    if (_layer.layer == null) return;
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
    _layer.layer!.seeded = fractional && !blocked;
  }

  /// Releases the retained experimental layer.
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
      // Drop the old native pass, but keep the original retained children.
      engineLayer = null;
      addChildrenToScene(builder);
    }
  }
}

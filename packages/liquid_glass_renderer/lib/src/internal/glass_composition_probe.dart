import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/internal/retained_glass_opacity_probe.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';

/// Seeds enclosing fractional-opacity surfaces with their backdrop while
/// preserving the original child clips and opaque rendering path.
class GlassCompositionProbe {
  final _layer = LayerHandle<_OpacitySeedLayer>();

  /// Whether this owner currently supplies a backdrop-initialized surface.
  bool get hasActiveSeed => _layer.layer?.seeded ?? false;

  /// Native opacity outside this owner already supplies alpha. Its fractional
  /// state still determines which material composition is safe to submit.
  bool get hasFractionalAncestor => _fractionalAncestor;
  bool _fractionalAncestor = false;

  /// Existing temporary passes can be needed again by an unfinished fade.
  bool get hasUnfinishedAncestor => _unfinishedAncestor;
  bool _unfinishedAncestor = false;
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
  void syncOpacity(RenderObject owner) {
    if (_layer.layer == null) return;
    var fractional = false;
    var aboveOwner = false;
    _fractionalAncestor = false;
    _unfinishedAncestor = false;
    var visible = true;
    var ancestor = owner.parent;
    while (ancestor != null) {
      // A containing glass owner handles its shared outer opacity scope.
      // An opacity between the owners still needs its own initialization.
      if (ancestor is LiquidGlassLayerRenderObject) {
        // The enclosing owner initializes the backdrop, but a native fade
        // above it still changes the safe presentation of this inner owner.
        aboveOwner = true;
      }
      final opacity = switch (ancestor) {
        RenderOpacity() => ancestor.opacity,
        RenderAnimatedOpacity() => ancestor.opacity.value,
        _ => 1.0,
      };
      final alpha = ui.Color.getAlphaFromOpacity(opacity);
      _unfinishedAncestor |= !isSettledOpaqueGlassScope(ancestor);
      if (isSettledTransparentGlassScope(ancestor)) {
        _unfinishedAncestor = false;
        _fractionalAncestor = false;
        fractional = false;
        break;
      }
      if (alpha == 0) {
        visible = false;
        fractional = false;
        _fractionalAncestor = false;
      }
      // Full-optics capture follows native presentation alpha; raw endpoint
      // and animation status above still govern temporary resource lifetime.
      if (visible) {
        _fractionalAncestor |= alpha < 255;
        if (!aboveOwner) fractional |= alpha < 255;
      }
      ancestor = ancestor.parent;
    }
    _layer.layer!.seeded = fractional;
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

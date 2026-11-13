import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_shadow.dart';
import 'package:liquid_glass_renderer/src/rendering/render_liquid_glass_geometry.dart';

/// The transform from [shape]'s own coordinates into its layer's, given its
/// geometry's [geometryToLayer].
@internal
Matrix4 shapeTransformToLayer(ShapeGeometry shape, Matrix4 geometryToLayer) =>
    switch (shape.shapeToGeometry) {
      final toGeometry? => geometryToLayer.multiplied(toGeometry),
      null => geometryToLayer,
    };

/// What a glass layer's last painted frame committed to the retained layer
/// tree.
@internal
enum GlassFrameState {
  /// The frame drew no glass effect: no shapes are registered, none is
  /// visible, or none can be drawn by this effect. Foreground still retains
  /// its own paint, and the committed input snapshot lets ancestor motion
  /// stay on the compositor.
  empty,

  /// Every registered shape is hidden but drawable. The retained effect
  /// keeps the last active frame's encode, the GPU matte in particular, so
  /// the layer stays compositor-managed until a shape becomes visible
  /// again. The matte itself cannot be reused on un-hide: a visibility
  /// crossing rebuilds the geometry cache.
  idle,

  /// The frame drew the glass effect for at least one visible shape.
  active,
}

/// Grows [bounds] to include the exterior shadows of [shapes], whose
/// coordinates map into the layer through their transforms.
@internal
Rect expandForGlassShadows(
  Rect bounds,
  Iterable<(List<ShapeGeometry>, Matrix4)> shapes,
) {
  var result = bounds;
  for (final (geometryShapes, geometryToLayer) in shapes) {
    for (final shape in geometryShapes) {
      final shapeVisibility = shape.appearance.visibility.clamp(0.0, 1.0);
      if (shapeVisibility <= 0) continue;
      final shapeToLayer = shapeTransformToLayer(shape, geometryToLayer);
      for (final shadow in shape.shadows) {
        final localBounds = glassShadowRect(
          Offset.zero & shape.renderObject.paintSize,
          shadow,
          shapeVisibility,
        );
        result = result.expandToInclude(
          MatrixUtils.transformRect(shapeToLayer, localBounds),
        );
      }
    }
  }
  return result;
}

/// Whether every render object between [shape] and [layer] paints its child
/// on the way down, so [shape] shows up on screen when [layer] paints.
///
/// A shape stays registered with its layer while attached, including inside
/// an [Offstage], an [IndexedStack] child that is not shown, or an opacity of
/// zero, where Flutter does not paint it ([RenderObject.paintsChild]).
@internal
bool isGlassShapePainted(RenderObject shape, RenderObject layer) {
  var child = shape;
  while (child != layer) {
    final parent = child.parent;
    if (parent == null || !parent.paintsChild(child)) return false;
    child = parent;
  }
  return true;
}

bool _debugWarnedOpacityBetweenShapeAndLayer = false;

/// Warns once per app when an [RenderOpacity] or [RenderAnimatedOpacity] sits
/// between one of [shapes] and its glass [layer], which would fade only the
/// glass's children. Returns `true` so it can run inside an `assert`.
@internal
bool debugCheckOpacityBetweenShapesAndLayer(
  RenderObject layer,
  Iterable<RenderObject> shapes,
) {
  if (_debugWarnedOpacityBetweenShapeAndLayer) return true;
  for (final shape in shapes) {
    for (
      var ancestor = shape.parent;
      ancestor != null && !identical(ancestor, layer);
      ancestor = ancestor.parent
    ) {
      if (ancestor is RenderOpacity || ancestor is RenderAnimatedOpacity) {
        _debugWarnedOpacityBetweenShapeAndLayer = true;
        debugPrint(
          'liquid_glass_renderer: an Opacity or FadeTransition between '
          'a LiquidGlass and its LiquidGlassLayer only fades the '
          "glass's children, not the glass. Fade glass with "
          'LiquidGlassVisibility or LiquidGlassAppearance.visibility '
          'instead.',
        );
        return true;
      }
    }
  }
  return true;
}

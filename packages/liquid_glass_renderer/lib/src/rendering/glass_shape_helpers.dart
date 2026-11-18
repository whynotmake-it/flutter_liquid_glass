import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

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

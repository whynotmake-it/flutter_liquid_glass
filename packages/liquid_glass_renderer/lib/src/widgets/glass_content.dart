import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/rendering.dart';
import 'package:meta/meta.dart';

/// The content of a glass shape: [child] faded to [opacity], over the touch
/// light a `GlassGlow` below may raise. See [RenderLiquidGlassContent].
@internal
class GlassContent extends SingleChildRenderObjectWidget {
  /// Shows [child] at [opacity].
  const GlassContent({required this.opacity, super.child, super.key});

  /// How opaque the content is, in `[0, 1]`.
  final double opacity;

  @override
  RenderLiquidGlassContent createRenderObject(BuildContext context) =>
      RenderLiquidGlassContent(opacity: opacity);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLiquidGlassContent renderObject,
  ) {
    renderObject.opacity = opacity;
  }
}

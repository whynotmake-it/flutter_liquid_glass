import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_shadow.dart';

/// Casts [shadows] of a lone [shape] that fills its child, as
/// [LiquidGlassSilhouette.paintShadows] casts them.
@internal
class GlassShadow extends SingleChildRenderObjectWidget {
  /// Creates a new [GlassShadow] widget with the given [shape], [shadows] and
  /// [child].
  const GlassShadow({
    required this.shape,
    required this.shadows,
    required this.appearanceVisibility,
    required this.devicePixelRatio,
    required super.child,
    super.key,
  });

  /// The shape to paint shadows for.
  final LiquidShape shape;

  /// Per-shape materialization progress.
  final double appearanceVisibility;

  /// Pixel ratio the shadow layer's bounds are kept on stable buckets for.
  final double devicePixelRatio;

  /// The shadows the shape casts.
  final List<LiquidGlassShadow> shadows;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderGlassShadow(
      shape: shape,
      shadows: shadows,
      visibility: appearanceVisibility,
      devicePixelRatio: devicePixelRatio,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderGlassShadow renderObject,
  ) {
    renderObject
      ..shape = shape
      ..shadows = shadows
      ..visibility = appearanceVisibility
      ..devicePixelRatio = devicePixelRatio;
  }
}

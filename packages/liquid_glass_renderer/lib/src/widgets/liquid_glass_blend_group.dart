import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/src/rendering/geometry_render_link.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_blend_group.dart';
import 'package:liquid_glass_renderer/src/widgets/glass_host.dart';
import 'package:liquid_glass_renderer/src/widgets/glass_pixel_ratio.dart';
import 'package:liquid_glass_renderer/src/widgets/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/widgets/liquid_glass_layer.dart';
import 'package:liquid_glass_renderer/src/widgets/liquid_glass_render_scope.dart';

/// A widget that groups multiple liquid glass shapes for blending.
///
/// Every [LiquidGlass] below it blends with the others, down to the next
/// [LiquidGlassLayer] or [LiquidGlassBlendGroup] and not into the child of
/// another glass: a shape joins the nearest group above it.
///
/// This widget will expect a parent [LiquidGlassLayer] to render the liquid
/// glass effect on. Inside the child of another [LiquidGlass] it renders on
/// a layer of its own, as a [LiquidGlass] there does.
///
/// A group has any number of shapes, but one spot of the screen is drawn
/// from at most 16 of them: where more blend or lie within reach of each
/// other, the extra ones are not drawn there, and a debug build says so once
/// per layer. Glass that crowded goes on several layers.
class LiquidGlassBlendGroup extends StatefulWidget {
  /// Creates a new [LiquidGlassBlendGroup].
  const LiquidGlassBlendGroup({
    required this.child,
    this.blend = 20.0,
    super.key,
  });

  /// The amount of blending between shapes in this group.
  ///
  /// Roughly corresponds to distance of logical pixels at which shapes start to
  /// blend.
  final double blend;

  /// The child widget containing liquid glass shapes.
  final Widget child;

  @override
  State<LiquidGlassBlendGroup> createState() => _LiquidGlassBlendGroupState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DoubleProperty('blend', blend, defaultValue: 20.0));
  }
}

class _LiquidGlassBlendGroupState extends State<LiquidGlassBlendGroup> {
  final _geometryLink = GlassGroupLink();

  @override
  void dispose() {
    _geometryLink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final host = GlassHost.of(context);
    if (host != null && host.inBody) {
      return nestedGlassLayer(context, _buildGroup);
    }
    return _buildGroup(context);
  }

  Widget _buildGroup(BuildContext context) {
    final renderLink = GlassHost.of(context)?.link;
    if (renderLink == null) throw noLiquidGlassLayerError(context);
    return GlassHost.layer(
      link: renderLink,
      group: _geometryLink,
      child: _RawLiquidGlassBlendGroup(
        blend: widget.blend,
        link: _geometryLink,
        renderLink: renderLink,
        child: widget.child,
      ),
    );
  }
}

class _RawLiquidGlassBlendGroup extends SingleChildRenderObjectWidget {
  const _RawLiquidGlassBlendGroup({
    required this.blend,
    required this.renderLink,
    required this.link,
    super.child,
  });

  final double blend;
  final GeometryRenderLink renderLink;
  final GlassGroupLink link;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderLiquidGlassBlendGroup(
      renderLink: renderLink,
      devicePixelRatio: glassDevicePixelRatioOf(context),
      link: link,
      blend: blend,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLiquidGlassBlendGroup renderObject,
  ) {
    renderObject
      ..blend = blend
      ..devicePixelRatio = glassDevicePixelRatioOf(context)
      ..link = link;
  }
}

import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/rendering.dart';
import 'package:liquid_glass_renderer/src/widgets/inherited_geometry_render_link.dart';
import 'package:liquid_glass_renderer/src/widgets/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/widgets/liquid_glass_layer.dart';
import 'package:meta/meta.dart';

/// A widget that groups multiple liquid glass shapes for blending.
///
/// Any [LiquidGlass.grouped] widgets inside this group will blend together.
///
/// This widget will expect a parent [LiquidGlassLayer] to render the liquid
/// glass effect on.
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

  /// Retrieves the [GlassGroupLink] from the nearest ancestor
  /// [LiquidGlassBlendGroup], or null if none is found.
  @internal
  static GlassGroupLink? maybeOf(BuildContext context) =>
      _InheritedLiquidGlassBlendGroup.of(context)?.link;

  @override
  State<LiquidGlassBlendGroup> createState() => _LiquidGlassBlendGroupState();
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
    final renderLink = InheritedGeometryRenderLink.of(context);
    assert(
      renderLink != null,
      'No liquid glass renderer found in context. '
      'Make sure to wrap your liquid glass widgets in a LiquidGlassLayer.',
    );
    return _InheritedLiquidGlassBlendGroup(
      link: _geometryLink,
      renderLink: renderLink,
      child: _RawLiquidGlassBlendGroup(
        blend: widget.blend,
        link: _geometryLink,
        renderLink: renderLink!,
        child: widget.child,
      ),
    );
  }
}

class _InheritedLiquidGlassBlendGroup extends InheritedWidget {
  const _InheritedLiquidGlassBlendGroup({
    required this.link,
    required this.renderLink,
    required super.child,
  });

  final GlassGroupLink link;
  final GeometryRenderLink? renderLink;

  static _InheritedLiquidGlassBlendGroup? of(BuildContext context) {
    final inherited = context
        .dependOnInheritedWidgetOfExactType<_InheritedLiquidGlassBlendGroup>();
    // A nested layer owns a different backdrop sample. Its shapes must not
    // register in a blend group belonging to an outer layer.
    return inherited?.renderLink == InheritedGeometryRenderLink.of(context)
        ? inherited
        : null;
  }

  @override
  bool updateShouldNotify(_InheritedLiquidGlassBlendGroup oldWidget) =>
      oldWidget.link != link || oldWidget.renderLink != renderLink;
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
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
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
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context)
      ..link = link;
  }
}

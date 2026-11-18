import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/src/rendering/geometry_render_link.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_blend_group.dart';
import 'package:liquid_glass_renderer/src/widgets/liquid_glass_layer.dart';
import 'package:liquid_glass_renderer/src/widgets/liquid_glass_render_scope.dart';
import 'package:meta/meta.dart';

/// Where the glass below draws: on a layer, in one of its blend groups, or
/// inside the body of another glass.
@internal
class GlassHost extends InheritedWidget {
  /// Glass below draws on the layer [link] gathers, in [group] when there is
  /// one.
  const GlassHost.layer({
    required GeometryRenderLink this.link,
    required super.child,
    this.group,
    super.key,
  });

  /// Glass below lies in the body of another glass.
  const GlassHost.body({required super.child, super.key})
    : link = null,
      group = null;

  /// The link of the layer the glass below draws on, or null in a body.
  final GeometryRenderLink? link;

  /// The blend group the glass below joins, or null for none.
  final GlassGroupLink? group;

  /// Whether the glass below lies in the body of another glass.
  bool get inBody => link == null;

  /// The nearest host above [context], or null outside every layer.
  static GlassHost? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassHost>();

  @override
  bool updateShouldNotify(GlassHost oldWidget) =>
      link != oldWidget.link || group != oldWidget.group;
}

/// A layer of its own, with the settings of the layer the body around
/// [context] draws on, for glass in that body, which [builder] builds.
Widget nestedGlassLayer(BuildContext context, WidgetBuilder builder) {
  final scope = LiquidGlassRenderScope.of(context);
  return LiquidGlassLayer(
    settings: scope.settings,
    defaultAppearance: scope.defaultAppearance,
    fake: scope.fake,
    child: Builder(builder: builder),
  );
}

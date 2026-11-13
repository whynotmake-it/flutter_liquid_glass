import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:meta/meta.dart';

@internal
class LiquidGlassRenderScope extends InheritedWidget {
  /// Creates a new [LiquidGlassRenderScope].
  const LiquidGlassRenderScope({
    required this.settings,
    required this.defaultAppearance,
    required super.child,
    this.fake = false,
    super.key,
  });

  final LiquidGlassSettings settings;

  final LiquidGlassAppearance defaultAppearance;

  /// Whether the layer is consolidated fake glass: shapes register with it
  /// without backdrop filters of their own, and it paints each fake surface.
  final bool fake;

  static LiquidGlassRenderScope of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<LiquidGlassRenderScope>();
    assert(
      scope != null,
      'No liquid glass renderer found in context. '
      'Make sure to wrap your liquid glass widgets in a LiquidGlassLayer.',
    );
    return scope!;
  }

  /// Returns the nearest [LiquidGlassRenderScope] from the widget tree,
  /// or `null` if there is none.
  static LiquidGlassRenderScope? maybeOf(
    BuildContext context, {
    bool watch = true,
  }) {
    return watch
        ? context.dependOnInheritedWidgetOfExactType<LiquidGlassRenderScope>()
        : context.getInheritedWidgetOfExactType<LiquidGlassRenderScope>();
  }

  @override
  bool updateShouldNotify(LiquidGlassRenderScope oldWidget) =>
      oldWidget.settings != settings ||
      oldWidget.defaultAppearance != defaultAppearance ||
      oldWidget.fake != fake;
}

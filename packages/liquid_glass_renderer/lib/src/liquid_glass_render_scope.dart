import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:meta/meta.dart';

@internal
class LiquidGlassRenderScope extends InheritedWidget {
  /// Creates a new [LiquidGlassRenderScope].
  const LiquidGlassRenderScope({
    required this.settings,
    required super.child,
    this.useFake = false,
    this.consolidatesFakeBackdrop = false,
    this.consolidatesFakeSurface = false,
    this.backdropKey,
    super.key,
  });

  final LiquidGlassSettings settings;

  final bool useFake;

  /// Whether fake shapes register with the parent layer while omitting their
  /// individual backdrop filters.
  final bool consolidatesFakeBackdrop;

  /// Whether the parent layer paints each registered fake surface.
  final bool consolidatesFakeSurface;

  /// The backdrop capture shared by glass effects in this scope, if any.
  final BackdropKey? backdropKey;

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
    if (watch) {
      return context
          .dependOnInheritedWidgetOfExactType<LiquidGlassRenderScope>();
    } else {
      return context.getInheritedWidgetOfExactType<LiquidGlassRenderScope>();
    }
  }

  @override
  bool updateShouldNotify(covariant InheritedWidget oldWidget) {
    return oldWidget is! LiquidGlassRenderScope ||
        oldWidget.settings != settings ||
        oldWidget.useFake != useFake ||
        oldWidget.consolidatesFakeBackdrop != consolidatesFakeBackdrop ||
        oldWidget.consolidatesFakeSurface != consolidatesFakeSurface ||
        oldWidget.backdropKey != backdropKey;
  }
}

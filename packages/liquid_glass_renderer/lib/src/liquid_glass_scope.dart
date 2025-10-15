import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/glass_link.dart';
import 'package:meta/meta.dart';

@internal
class LiquidGlassScope extends InheritedWidget {
  /// Creates a new [LiquidGlassScope].
  const LiquidGlassScope({
    required this.settings,
    required super.child,
    required this.link,
    super.key,
  });

  final LiquidGlassSettings settings;

  final GlassLink link;

  static LiquidGlassScope of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<LiquidGlassScope>();
    assert(scope != null, 'No LiquidGlassScope found in context');
    return scope!;
  }

  @override
  bool updateShouldNotify(covariant InheritedWidget oldWidget) {
    return oldWidget is! LiquidGlassScope ||
        oldWidget.settings != settings ||
        oldWidget.link != link;
  }
}

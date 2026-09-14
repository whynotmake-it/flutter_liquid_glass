import 'package:flutter/widgets.dart';

/// Multiplies the material visibility of descendant glass shapes.
///
/// Values compose through the tree: a visibility of `0.5` nested beneath
/// `0.4` gives descendant glass an effective visibility multiplier of `0.2`.
/// This affects glass materialization only; ordinary child content remains
/// visible and interactive.
class LiquidGlassVisibility extends StatelessWidget {
  /// Creates a compositional visibility scope for descendant glass shapes.
  const LiquidGlassVisibility({
    required this.visibility,
    required this.child,
    super.key,
  });

  /// Visibility multiplier applied to descendant glass materials.
  final double visibility;

  /// Subtree containing glass shapes.
  final Widget child;

  /// Returns the accumulated visibility multiplier above [context].
  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_VisibilityScope>()?.value ??
      1;

  @override
  Widget build(BuildContext context) => _VisibilityScope(
    value: visibility.clamp(0.0, 1.0) * of(context),
    child: child,
  );
}

class _VisibilityScope extends InheritedWidget {
  const _VisibilityScope({required this.value, required super.child});

  final double value;

  @override
  bool updateShouldNotify(_VisibilityScope oldWidget) =>
      value != oldWidget.value;
}

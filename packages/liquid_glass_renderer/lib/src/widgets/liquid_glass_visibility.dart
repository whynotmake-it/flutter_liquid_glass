import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_appearance.dart';

/// Multiplies the material visibility of descendant glass shapes.
///
/// Values compose through the tree: a visibility of `0.5` nested beneath
/// `0.4` gives descendant glass an effective visibility multiplier of `0.2`.
/// As visibility falls, the glass transitions out (refraction goes to zero,
/// lighting and blur fade) and the glass's children fade with it. Children
/// stay mounted and interactive at every value.
///
/// It fades every shape below it; one shape's own visibility is
/// [LiquidGlassAppearance.visibility], and a shape shows the product of the
/// two.
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
    value: drawnVisibility(visibility) * of(context),
    child: child,
  );

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DoubleProperty('visibility', visibility));
  }
}

class _VisibilityScope extends InheritedWidget {
  const _VisibilityScope({required this.value, required super.child});

  final double value;

  @override
  bool updateShouldNotify(_VisibilityScope oldWidget) =>
      value != oldWidget.value;
}

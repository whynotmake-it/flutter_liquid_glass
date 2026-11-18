import 'package:flutter/widgets.dart';
import 'package:kinesis/widgets.dart';
import 'package:liquid_glass_renderer/painting.dart';

/// What a presentation that grows out of a control carries of it: the
/// outline of its body, its tint, its look, and its name.
///
/// A control publishes it with a [GlassSource] around its body.
@immutable
final class GlassSourceDescription {
  /// Describes a body of [shape], tinted [tint], whose [look] the
  /// presentation's glass carries as it grows, named [semanticLabel].
  const GlassSourceDescription({
    this.shape = LiquidRoundedSuperellipse.capsule,
    this.tint,
    this.look,
    this.semanticLabel,
  });

  /// The outline of the control's body.
  final LiquidShape shape;

  /// The color of the control's glass at rest, or null for untinted glass.
  final Color? tint;

  /// What the presentation's glass carries of the control as it grows out
  /// of it, such as its label without its glass; null for nothing.
  final Widget? look;

  /// What accessibility calls the control, which names the presentation;
  /// null for the presentation's own name.
  final String? semanticLabel;
}

/// The body of a control that a presentation around it, such as the menu
/// of a `GlassMenuAnchor`, grows out of: the presentation grows out of
/// [child]'s box and reads [description] when it opens.
///
/// A control puts it around its body and keeps its own input, focus,
/// states and semantics. Outside such a presentation it is [child] alone,
/// and inside another [GlassSource] it is [child] too: the outer one
/// describes the control. `GlassButton` and `RawGlassButton` describe
/// their glass this way; a control of your own does the same. Without one
/// the presentation grows untinted glass out of the box of everything it
/// wraps, as a capsule.
class GlassSource extends StatelessWidget {
  /// Describes [child] as [description].
  const GlassSource({
    required this.description,
    required this.child,
    super.key,
  });

  /// What the presentation carries of [child].
  final GlassSourceDescription description;

  /// The control's body.
  final Widget child;

  /// Whether a presentation above [context] grows out of the control
  /// there and presses it as it measures: a control then draws its body at
  /// rest, as `RawGlassButton` does.
  static bool isSourceAt(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassSourceScope>() != null;

  @override
  Widget build(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<GlassSourceScope>();
    if (scope == null ||
        context.getInheritedWidgetOfExactType<_Described>() != null) {
      return child;
    }
    return _Described(
      child: MotionSourceBox(source: scope.source, child: child),
    );
  }
}

/// Marks the body a [GlassSource] above already describes.
class _Described extends InheritedWidget {
  const _Described({required super.child});

  @override
  bool updateShouldNotify(_Described oldWidget) => false;
}

/// Puts the [source] a presentation grows out of above [child], for a
/// [GlassSource] in it to show; a `GlassMenuAnchor` puts one around its
/// control.
class GlassSourceScope extends InheritedWidget {
  /// Puts [source] above [child].
  const GlassSourceScope({
    required this.source,
    required super.child,
    super.key,
  });

  /// The source a [GlassSource] below shows.
  final MotionSource source;

  @override
  bool updateShouldNotify(GlassSourceScope oldWidget) =>
      !identical(source, oldWidget.source);
}

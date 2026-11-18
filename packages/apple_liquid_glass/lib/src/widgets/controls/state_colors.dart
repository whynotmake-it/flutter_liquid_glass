import 'package:apple_liquid_glass/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// The colors of a widget in [states]: a style's [WidgetStateProperty]
/// resolved in the states, then, when it gives a [GlassDynamicColor], at
/// [context].
@internal
final class StateColors {
  /// The colors of the widget at [context] in [states].
  const StateColors(this.context, this.states);

  /// Where dynamic colors resolve.
  final BuildContext context;

  /// The widget's states.
  final Set<WidgetState> states;

  /// [property] in [states], or [fallback] where it gives no color.
  Color call(WidgetStateProperty<Color?>? property, [Color? fallback]) =>
      GlassDynamicColor.resolve(
        (property?.resolve(states) ?? fallback)!,
        context,
      );

  /// [property] in [states], or null where it gives no color.
  Color? maybe(WidgetStateProperty<Color?>? property) =>
      GlassDynamicColor.maybeResolve(property?.resolve(states), context);
}

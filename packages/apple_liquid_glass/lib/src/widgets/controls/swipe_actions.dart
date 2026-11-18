import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/raw.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/painting.dart';

/// One trailing swipe action of a list row.
///
/// UIKit: `UIContextualAction`. SwiftUI: a `Button` in `swipeActions`.
/// Flutter: `SlidableAction` of flutter_slidable.
@immutable
final class GlassSwipeAction {
  /// Creates an action titled [title].
  const GlassSwipeAction({
    required this.title,
    required this.onPressed,
    this.icon,
    this.destructive = false,
    this.backgroundColor,
    this.foregroundColor,
  });

  /// What the action is called: its label when it has no [icon], and what
  /// accessibility reads.
  final String title;

  /// Shown in place of [title], usually an [Icon].
  final Widget? icon;

  /// Called when the action is pressed, or performed by a full swipe.
  final VoidCallback onPressed;

  /// Whether the action destroys, as a delete does (UIKit `.destructive`):
  /// systemRed by default.
  final bool destructive;

  /// The action's fill: systemRed for a destructive action, systemGray
  /// otherwise, by default.
  final Color? backgroundColor;

  /// The color of the action's label: white by default.
  final Color? foregroundColor;
}

/// A row that a finger swipes toward its trailing edge to show [trailing]
/// actions.
///
/// UIKit: `trailingSwipeActionsConfigurationForRowAt`. SwiftUI:
/// `swipeActions(edge: .trailing)`. Flutter: `Slidable` of
/// flutter_slidable.
///
/// The row follows the finger on a rubber band and settles open or closed
/// where the release projects; [trailing] sits against its trailing edge,
/// the first action outermost. With [fullSwipe] a swipe past most of the
/// row performs the first action, as UIKit's
/// `performsFirstActionWithFullSwipe`. A tap on the open row closes it,
/// and so does a scroll, or a swipe of another row of the same
/// `GlassListSection` or `GlassSliverListSection`. Accessibility offers
/// the actions as custom actions of the row, as UIKit does, which is also
/// how iOS's Full Keyboard Access reaches them (its actions command,
/// Tab-Z). A closed row's actions are no Tab stops; an open row's actions
/// are, before the row, and Space and Enter press the focused one. A
/// focused action draws Flutter's Cupertino focus ring inside its edge
/// and a mouse over it washes it, by the rule of the glass controls (an
/// approximation, not measured).
///
/// Its behavior is [RawGlassSwipeActions]'s; this draws the actions.
///
/// An action's label is 15 points, medium, with 15 points on each side.
///
/// Not measured: the springs, the widths, the label and the full-swipe
/// threshold are chosen by eye, as UIKit's swipe actions were not captured
/// on iOS 27.
class GlassSwipeActions extends StatelessWidget {
  /// Creates a row that shows [trailing] when swiped.
  const GlassSwipeActions({
    required this.trailing,
    required this.child,
    this.fullSwipe = true,
    super.key,
  });

  /// The actions, the first at the trailing edge.
  final List<GlassSwipeAction> trailing;

  /// Whether a full swipe performs the first action.
  final bool fullSwipe;

  /// The row.
  final Widget child;

  static const double _actionPadding = 15;

  /// The narrowest an action is.
  static const double minActionWidth = 74;

  static const TextStyle _actionTextStyle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w500,
  );

  @override
  Widget build(BuildContext context) {
    final actions = trailing;
    return RawGlassSwipeActions(
      actionLabels: [for (final action in actions) action.title],
      onAction: (i) => actions[i].onPressed(),
      fullSwipe: fullSwipe,
      overswipe: actions.isEmpty
          ? null
          : ColoredBox(color: _fillOf(actions.first, context)),
      actionBuilder: (context, details) =>
          _ActionButton(action: actions[details.index], states: details.states),
      child: child,
    );
  }
}

Color _fillOf(GlassSwipeAction action, BuildContext context) =>
    GlassDynamicColor.resolve(
      action.backgroundColor ??
          (action.destructive ? GlassColors.systemRed : GlassColors.systemGray),
      context,
    );

/// An action's fill and label; the core's zone for it takes its input and
/// speaks for it.
class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.action, required this.states});

  final GlassSwipeAction action;
  final ValueListenable<Set<WidgetState>> states;

  @override
  Widget build(BuildContext context) {
    final foreground = GlassDynamicColor.resolve(
      action.foregroundColor ?? const Color(0xFFFFFFFF),
      context,
    );
    return ColoredBox(
      color: _fillOf(action, context),
      child: GlassHighlightPaint.of(
        context,
        states: states,
        shape: const LiquidRoundedRectangle(radius: 0),
        inside: true,
        wash: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: GlassSwipeActions.minActionWidth,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: GlassSwipeActions._actionPadding,
            ),
            child: Center(
              widthFactor: 1,
              child: IconTheme.merge(
                data: IconThemeData(color: foreground),
                child:
                    action.icon ??
                    Text(
                      action.title,
                      maxLines: 1,
                      style: GlassTextScale.of(context).resolve(
                        GlassSwipeActions._actionTextStyle.copyWith(
                          color: foreground,
                        ),
                      ),
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

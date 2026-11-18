import 'dart:math' as math;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:apple_liquid_glass/src/widgets/presentations/popover.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';
import 'package:liquid_glass_renderer/painting.dart';

part 'package:apple_liquid_glass/src/widgets/presentations/alert_look.dart';
part 'package:apple_liquid_glass/src/widgets/presentations/alert_view.dart';

enum _Role { normal, cancel, destructive }

/// The look of alerts and action sheets; a null field leaves it to the
/// theme's style, then the default (iPhone 16 Pro, iOS 27).
@immutable
class GlassAlertStyle extends GlassStyle<GlassAlertStyle> {
  /// Creates a style.
  const GlassAlertStyle({
    this.titleTextStyle,
    this.messageTextStyle,
    this.actionTextStyle,
    this.actionColor,
    this.destructiveActionColor,
    this.defaultActionColor,
    this.actionFillColor,
    this.defaultActionFillColor,
  });

  /// The theme's [GlassAlertStyle] at [context], or null without one: the
  /// look between a widget's own style and its defaults.
  static GlassAlertStyle? maybeOf(BuildContext context) =>
      GlassTheme.styleOf<GlassAlertStyle>(context);

  /// The title, over the default 17 points in label, semibold above a
  /// message.
  final TextStyle? titleTextStyle;

  /// The message, over the default 15 points in secondaryLabel under a
  /// title, or the title's default (17 points in label) without one.
  final TextStyle? messageTextStyle;

  /// The action labels, over the default 17 points, medium; an alert
  /// measures [Text] labels in it to choose a row of two buttons over a
  /// column.
  final TextStyle? actionTextStyle;

  /// The label of an action; label by default.
  final Color? actionColor;

  /// The label of a destructive action; systemRed by default.
  final Color? destructiveActionColor;

  /// The label of the default action; white by default.
  final Color? defaultActionColor;

  /// The capsule behind an action; tertiarySystemFill by default.
  final Color? actionFillColor;

  /// The capsule behind the default action; the theme's primary color,
  /// then systemBlue, by default.
  final Color? defaultActionFillColor;

  /// This style over [other].
  @override
  GlassAlertStyle merge(GlassAlertStyle? other) {
    if (other == null) return this;
    return GlassAlertStyle(
      titleTextStyle:
          other.titleTextStyle?.merge(titleTextStyle) ?? titleTextStyle,
      messageTextStyle:
          other.messageTextStyle?.merge(messageTextStyle) ?? messageTextStyle,
      actionTextStyle:
          other.actionTextStyle?.merge(actionTextStyle) ?? actionTextStyle,
      actionColor: actionColor ?? other.actionColor,
      destructiveActionColor:
          destructiveActionColor ?? other.destructiveActionColor,
      defaultActionColor: defaultActionColor ?? other.defaultActionColor,
      actionFillColor: actionFillColor ?? other.actionFillColor,
      defaultActionFillColor:
          defaultActionFillColor ?? other.defaultActionFillColor,
    );
  }

  /// The style between this one and [other] at [t].
  @override
  GlassAlertStyle lerp(GlassAlertStyle other, double t) {
    if (identical(this, other)) return this;
    final color = GlassStyle.lerpNullable(GlassDynamicColor.lerp);
    final text = GlassStyle.lerpNullable(TextStyle.lerp);
    return GlassAlertStyle(
      titleTextStyle: text(titleTextStyle, other.titleTextStyle, t),
      messageTextStyle: text(messageTextStyle, other.messageTextStyle, t),
      actionTextStyle: text(actionTextStyle, other.actionTextStyle, t),
      actionColor: color(actionColor, other.actionColor, t),
      destructiveActionColor: color(
        destructiveActionColor,
        other.destructiveActionColor,
        t,
      ),
      defaultActionColor: color(
        defaultActionColor,
        other.defaultActionColor,
        t,
      ),
      actionFillColor: color(actionFillColor, other.actionFillColor, t),
      defaultActionFillColor: color(
        defaultActionFillColor,
        other.defaultActionFillColor,
        t,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassAlertStyle &&
      other.titleTextStyle == titleTextStyle &&
      other.messageTextStyle == messageTextStyle &&
      other.actionTextStyle == actionTextStyle &&
      other.actionColor == actionColor &&
      other.destructiveActionColor == destructiveActionColor &&
      other.defaultActionColor == defaultActionColor &&
      other.actionFillColor == actionFillColor &&
      other.defaultActionFillColor == defaultActionFillColor;

  @override
  int get hashCode => Object.hash(
    titleTextStyle,
    messageTextStyle,
    actionTextStyle,
    actionColor,
    destructiveActionColor,
    defaultActionColor,
    actionFillColor,
    defaultActionFillColor,
  );
}

/// One button of an alert or an action sheet.
///
/// UIKit: `UIAlertAction`. SwiftUI: a `Button` in `alert` or
/// `confirmationDialog`. Flutter: `CupertinoDialogAction`.
@immutable
class GlassAlertAction {
  /// Creates an action showing [child].
  const GlassAlertAction({
    required this.child,
    this.onPressed,
    this.isDefaultAction = false,
    this.enabled = true,
  }) : _role = _Role.normal;

  /// Creates the action that cancels: it goes first in a row of two buttons
  /// and last in a column, and Escape, Back and a screen reader's dismiss
  /// choose it.
  const GlassAlertAction.cancel({
    required this.child,
    this.onPressed,
    this.isDefaultAction = false,
    this.enabled = true,
  }) : _role = _Role.cancel;

  /// Creates an action that destroys data: its label is red.
  const GlassAlertAction.destructive({
    required this.child,
    this.onPressed,
    this.isDefaultAction = false,
    this.enabled = true,
  }) : _role = _Role.destructive;

  /// The button's label.
  final Widget child;

  /// Called once the alert has gone after the user chose this action, as
  /// UIKit calls an action's handler after the dismissal.
  final VoidCallback? onPressed;

  /// Whether this is the preferred action: its button is filled with the
  /// accent color, its label semibold, and it takes the focus when the
  /// alert opens, so Return chooses it.
  final bool isDefaultAction;

  /// Whether the button takes taps; a disabled one keeps its fill and draws
  /// its label in tertiary label color, and a disabled default one loses
  /// its accent fill (iPhone 16 Pro, iOS 27.0.1).
  final bool enabled;

  final _Role _role;

  /// Whether this action cancels.
  bool get isCancel => _role == _Role.cancel;

  /// Whether this action destroys data.
  bool get isDestructive => _role == _Role.destructive;
}

/// Shows an iOS 27 alert and completes with the action chosen, or null
/// when it was closed without one.
///
/// UIKit: `UIAlertController` with the alert style. SwiftUI: `alert`.
/// Flutter: `showCupertinoDialog` with a `CupertinoAlertDialog`.
///
/// Pass a [title], an optional [message] and the [actions]: a
/// [GlassAlertAction] for each button, [GlassAlertAction.cancel] for the
/// one that cancels and [GlassAlertAction.destructive] for one that
/// destroys data. Each action's `onPressed` runs once the alert has gone.
/// [style] changes its colors. The [context] needs a [Navigator] above it,
/// as any `WidgetsApp` gives; with [level] at its default the alert covers
/// the whole app, bars and tabs included.
///
/// ```dart
/// Future<void> confirmDelete(BuildContext context) async {
///   await showGlassAlert(
///     context,
///     title: const Text('Delete the note?'),
///     message: const Text('This cannot be undone.'),
///     actions: [
///       const GlassAlertAction.cancel(child: Text('Cancel')),
///       GlassAlertAction.destructive(
///         child: const Text('Delete'),
///         onPressed: () => debugPrint('deleted'),
///       ),
///     ],
///   );
/// }
/// ```
///
/// The platter is a `GlassSurface`: liquid glass on the liquid renderer,
/// blurred and lit glass on the fake renderer, and a translucent fill with
/// a hairline rim and a soft shadow on the flat renderer. The alert sits
/// on the outermost navigator, so it draws with the renderer of a
/// `GlassScope` above that navigator, such as one in `WidgetsApp.builder`,
/// and flat with none.
///
/// A platter 320 points wide with corners of 34 holds the [title], the
/// [message] and the [actions], two side by side when their labels fit
/// and a column otherwise, over a black dimming at 20 percent. It presents
/// by fading in with the dimming while it shrinks from 1.199 times its
/// size, and leaves by fading, on one critically damped spring of response
/// 0.275 s; under Reduce Motion it presents at its size. A finger slides
/// between the buttons and chooses the one it lifts from, lifting the
/// whole platter as a glass button lifts. Each button is a focus stop:
/// the default action has the focus when the alert opens, Tab and the
/// arrows move between the buttons, and Return and Space choose the
/// focused one.
/// Escape, Back (Android's predictive back fading the alert with the
/// gesture) and a screen reader's dismiss choose the cancel action;
/// without one they do nothing, and neither does a tap outside. Screen
/// readers hear an alert dialog named by the title, or the message
/// without one, or [GlassLocalizations.alertLabel].
///
/// Fidelity. The presenting spring is read from UIKit's
/// `CASpringAnimation` and checked on an iPhone 16 Pro.
Future<GlassAlertAction?> showGlassAlert(
  BuildContext context, {
  Widget? title,
  Widget? message,
  List<GlassAlertAction> actions = const [],
  GlassAlertStyle? style,
  PresentationLevel level = PresentationLevel.window,
}) => showPresentation(
  context,
  PresentationRoute(
    presentation: _alert(
      title: title,
      message: message,
      actions: actions,
      style: style,
      actionSheet: false,
      strings: GlassLocalizations.of(context),
    ),
  ),
  level: level,
);

/// Shows an iOS 27 action sheet and completes with the action chosen, or
/// null when it was closed without one.
///
/// UIKit: `UIAlertController` with the action sheet style. SwiftUI:
/// `confirmationDialog`. Flutter: `showCupertinoModalPopup` with a
/// `CupertinoActionSheet`.
///
/// With a source, [anchor] (a context inside the control that summoned
/// it, laid out) or [anchorRect] (in global coordinates), the action sheet
/// is a glass popover 240 points wide next to the source, as iOS 27
/// presents one on an iPhone: it grows out of its arrow's tip and shrinks
/// back into it (see [showGlassPopover]), does not lift under a finger and
/// leaves the cancel action out, which a tap outside chooses. Without a
/// source an action sheet is an alert whose actions stand in a column with
/// the cancel action last; a tap outside chooses the cancel action, or
/// closes it without one, and screen readers find the dimming as
/// [GlassLocalizations.actionSheetDismissLabel]. The keys and screen
/// readers reach its buttons as an alert's.
Future<GlassAlertAction?> showGlassActionSheet(
  BuildContext context, {
  Widget? title,
  Widget? message,
  List<GlassAlertAction> actions = const [],
  BuildContext? anchor,
  Rect? anchorRect,
  GlassAlertStyle? style,
  PresentationLevel level = PresentationLevel.window,
}) => showPresentation(
  context,
  PresentationRoute(
    presentation: _alert(
      title: title,
      message: message,
      actions: actions,
      style: style,
      actionSheet: true,
      strings: GlassLocalizations.of(context),
      anchorRect: anchor == null && anchorRect == null
          ? null
          : popoverSource(
              anchor: anchor,
              anchorRect: anchorRect,
              caller: 'showGlassActionSheet',
            ),
    ),
  ),
  level: level,
);

Presentation<GlassAlertAction, PresentedProgress> _alert({
  required Widget? title,
  required Widget? message,
  required List<GlassAlertAction> actions,
  required GlassAlertStyle? style,
  required bool actionSheet,
  required GlassLocalizations strings,
  Rect? anchorRect,
}) {
  final cancel = _cancelOf(actions);
  // An alert without an enabled cancel action waits for one of its
  // buttons; an action sheet always closes on Escape, Back and a screen
  // reader's dismiss, with its cancel action or none.
  final closable = actionSheet || cancel != null;
  return Presentation(
    motion: (_) => anchorRect == null ? AlertMotion() : PopoverMotion(),
    builder: (context, motion) => _AlertView(
      motion: motion,
      title: title,
      message: message,
      actions: actions,
      style: style,
      actionSheet: actionSheet,
      anchorRect: anchorRect,
    ),
    dismiss: DismissPolicy({
      if (actionSheet) DismissTrigger.outsideTap,
      if (closable) ...{
        DismissTrigger.escape,
        DismissTrigger.back,
        DismissTrigger.accessibility,
      },
      DismissTrigger.interaction,
    }),
    dim: anchorRect == null
        ? (motion) =>
              _AlertLook.dimmingOpacity * (motion as AlertMotion).dimming
        : null,
    result: (result) => result ?? cancel,
    onDismissed: (action) => action?.onPressed?.call(),
    semanticsLabel:
        glassLabelTextOf(title) ??
        glassLabelTextOf(message) ??
        strings.alertLabel,
    // As Flutter's CupertinoActionSheet: a sheet of choices is a dialog,
    // only an alert interrupts.
    semanticsRole: actionSheet
        ? SemanticsRole.dialog
        : SemanticsRole.alertDialog,
    barrierLabel: actionSheet ? strings.actionSheetDismissLabel : null,
  );
}

// A disabled cancel action answers nothing, as its button does nothing.
GlassAlertAction? _cancelOf(List<GlassAlertAction> actions) {
  for (final action in actions) {
    if (action.isCancel) return action.enabled ? action : null;
  }
  return null;
}

List<GlassAlertAction> _ordered(
  List<GlassAlertAction> actions, {
  required bool row,
  required bool popover,
}) {
  final cancel = [
    for (final a in actions)
      if (a.isCancel) a,
  ];
  final rest = [
    for (final a in actions)
      if (!a.isCancel) a,
  ];
  if (popover) return rest;
  return row ? [...cancel, ...rest] : [...rest, ...cancel];
}

extension on TextStyle {
  TextStyle resolvedColor(BuildContext context) => switch (color) {
    final color? => copyWith(color: GlassDynamicColor.resolve(color, context)),
    null => this,
  };
}

// The message color of an alert, light and dark (UIKit's rendering on an
// iPhone 16 Pro).
const _messageColor = GlassDynamicColor.withBrightness(
  color: Color(0x993C3C43),
  darkColor: Color(0x99EBEBF5),
);

class _AlertView extends StatefulWidget {
  const _AlertView({
    required this.motion,
    required this.title,
    required this.message,
    required this.actions,
    required this.style,
    required this.actionSheet,
    required this.anchorRect,
  });

  // An AlertMotion, or a PopoverMotion for an action sheet with a source.
  final PresentedProgress motion;
  final Widget? title;
  final Widget? message;
  final List<GlassAlertAction> actions;
  final GlassAlertStyle? style;
  final bool actionSheet;
  final Rect? anchorRect;

  @override
  State<_AlertView> createState() => _AlertViewState();
}

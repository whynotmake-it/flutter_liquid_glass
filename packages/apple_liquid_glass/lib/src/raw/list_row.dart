import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/widgets.dart';

/// Builds a part of a glass list row from [details]; it runs when the part
/// builds, such as when its states change, never on a frame of the
/// highlight.
typedef GlassListRowBuilder = Widget Function(
  BuildContext context,
  GlassListRowDetails details,
);

/// What a [GlassListRowBuilder] builds a part of a list row from.
@immutable
final class GlassListRowDetails {
  /// Describes a part of a list row.
  const GlassListRowDetails({
    required this.states,
    required this.highlight,
    required this.statesListenable,
  });

  /// The states the part is in.
  final Set<WidgetState> states;

  /// The part's states as they change: a builder hands it to the highlight
  /// of the part, which then draws the focus ring and the hover response.
  final ValueListenable<Set<WidgetState>> statesListenable;

  /// How strongly the row shows highlighted, 0 to 1, with the measured
  /// timing of `ListRowHighlight`: a builder hands it to what paints the
  /// row's fill, which follows it without a build.
  final ValueListenable<double> highlight;
}

/// A row of a list with the behavior of an iOS 27 table cell and no look of
/// its own: [builder] decides how the row looks and [infoBuilder] how its
/// info button looks.
///
/// UIKit: `UITableViewCell` with its accessory button. SwiftUI: a row of a
/// `List`. Flutter: `CupertinoListTile`.
///
/// With [onPressed] the row is a button: its highlight shows while a finger
/// is down on it, with UIKit's timing (`ListRowHighlight`: inside a scroll
/// view after its 0.15 s touch delay, gone at once when a scroll takes the
/// touch, faded out over 0.5 s after a tap), and Space and Enter press it.
/// Without [onPressed] the row takes no input and no focus, and a screen
/// reader reads it as text. A row that is not [enabled] ignores presses;
/// either way its highlight clears and [builder] sees
/// [WidgetState.disabled].
///
/// With [infoBuilder] the row has an info button (UIKit's detail button),
/// centered [infoCenterInset] from the row's end edge and as tall as the
/// row. It is a target of its own beside the row, not inside it: a touch on
/// it does not press the row, it is a Tab stop of its own, takes a finger
/// in at least 44 by 44 points, and a screen reader reads it as a button
/// labeled [infoSemanticLabel]. It takes presses while the row is
/// [enabled] and [onInfoPressed] is set.
class RawGlassListRow extends StatefulWidget {
  /// Creates a row whose look [builder] builds.
  const RawGlassListRow({
    required this.builder,
    this.onPressed,
    this.enabled = true,
    this.selected = false,
    this.infoBuilder,
    this.onInfoPressed,
    this.infoCenterInset = 0,
    this.infoSemanticLabel,
    this.statesController,
    this.focusNode,
    this.autofocus = false,
    super.key,
  });

  /// Builds the row's look.
  final GlassListRowBuilder builder;

  /// Called when the row is pressed; null makes the row inert.
  final VoidCallback? onPressed;

  /// Whether the row and its info button take presses.
  final bool enabled;

  /// Whether a screen reader reads the row as selected, as a row with a
  /// checkmark is.
  final bool selected;

  /// Builds the info button's look inside its target, or null for a row
  /// without one.
  final GlassListRowBuilder? infoBuilder;

  /// Called when the info button is pressed (UIKit
  /// `accessoryButtonTappedForRowWith`); null leaves it inert.
  final VoidCallback? onInfoPressed;

  /// How far the center of the info button lies from the row's end edge.
  final double infoCenterInset;

  /// What accessibility reads for the info button; the localized
  /// [GlassLocalizations.moreInfoLabel] when null.
  final String? infoSemanticLabel;

  /// Where the row publishes its states, or null for its own. The row is
  /// its only writer: what else writes to it is written over.
  final WidgetStatesController? statesController;

  /// The row's focus node, or null for its own.
  final FocusNode? focusNode;

  /// Whether the row takes focus when it first appears.
  final bool autofocus;

  @override
  State<RawGlassListRow> createState() => _RawGlassListRowState();
}

class _RawGlassListRowState extends State<RawGlassListRow>
    with ControlStates<RawGlassListRow> {
  final _highlight = ListRowHighlight();
  late final _strength = _highlight.select((h) => h.opacity);
  late final List<Interaction> _interactions = [
    PressInteraction(
      role: InteractionRole.content,
      onTap: (t) => widget.onPressed?.call(),
    ).simultaneously(
      FollowInteraction(_highlight, role: InteractionRole.content),
    ),
  ];

  @override
  WidgetStatesController? get givenStates => widget.statesController;

  @override
  void didUpdateWidget(RawGlassListRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!enabled) _highlight.clear(_highlight.clock.now);
  }

  @override
  bool get enabled => widget.onPressed != null && widget.enabled;

  @override
  Widget build(BuildContext context) {
    final look = widget.builder(
      context,
      GlassListRowDetails(
        states: {...widgetStates.value},
        statesListenable: widgetStates,
        highlight: _strength,
      ),
    );
    final selected = widget.selected ? true : null;
    final row = Semantics(
      container: true,
      child: widget.onPressed == null
          ? Semantics(button: false, selected: selected, child: look)
          : InputRegion(
              interactions: _interactions,
              enabled: enabled,
              statesController: widgetStates,
              focusNode: widget.focusNode,
              autofocus: widget.autofocus,
              semantics: SemanticsProperties(button: true, selected: selected),
              child: look,
            ),
    );
    final infoBuilder = widget.infoBuilder;
    if (infoBuilder == null) return row;
    const target = glassMinimumTarget;
    // The info button is a target beside the row's, not inside it: a
    // region inside another one would hand its keys to the outer one.
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: Stack(
        children: [
          row,
          PositionedDirectional(
            top: 0,
            bottom: 0,
            end: widget.infoCenterInset - target.width / 2,
            width: target.width,
            child: Center(
              child: _InfoButton(
                builder: infoBuilder,
                highlight: _strength,
                enabled: widget.enabled && widget.onInfoPressed != null,
                onPressed: widget.onInfoPressed,
                label:
                    widget.infoSemanticLabel ??
                    GlassLocalizations.of(context).moreInfoLabel,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The info button of a row: its own region, states and semantics.
class _InfoButton extends StatefulWidget {
  const _InfoButton({
    required this.builder,
    required this.highlight,
    required this.enabled,
    required this.onPressed,
    required this.label,
  });

  final GlassListRowBuilder builder;
  final ValueListenable<double> highlight;
  final bool enabled;
  final VoidCallback? onPressed;
  final String label;

  @override
  State<_InfoButton> createState() => _InfoButtonState();
}

class _InfoButtonState extends State<_InfoButton>
    with ControlStates<_InfoButton> {
  late final List<Interaction> _interactions = [
    PressInteraction(onTap: (t) => widget.onPressed?.call()),
  ];

  @override
  WidgetStatesController? get givenStates => null;

  @override
  bool get enabled => widget.enabled;

  @override
  Widget build(BuildContext context) => InputRegion(
    interactions: _interactions,
    enabled: enabled,
    statesController: widgetStates,
    semantics: SemanticsProperties(label: widget.label, button: true),
    reach: glassTargetReach,
    child: widget.builder(
      context,
      GlassListRowDetails(
        states: {...widgetStates.value},
        statesListenable: widgetStates,
        highlight: widget.highlight,
      ),
    ),
  );
}

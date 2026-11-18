import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/src/widgets/input_zones.dart';

/// Where an [InputZone] lies in one frame, as its control reads it from the
/// motion it paints with.
///
/// [InputZones.frameOf] answers one per zone whenever input or
/// accessibility asks: at hit testing, at the pointer events of a touch,
/// for the focus rectangle and the semantics rectangle. The host keeps an
/// answer only until `InputZones.frames` notifies, so a zone is hit where it
/// is painted in the frame the finger lands in.
@immutable
final class InputZoneFrame {
  /// Places a zone at [rect] with [radius] corners, painted at [opacity],
  /// taking input while [takesInput] holds.
  const InputZoneFrame(
    this.rect, {
    this.opacity = 1,
    this.takesInput = true,
    this.radius = BorderRadius.zero,
  });

  /// UIKit's hit-testing rule: a view painted with an alpha below 0.01
  /// takes no touch (`UIView.hitTest(_:with:)`).
  ///
  /// It is the one opacity threshold of input: a zone fading in starts to
  /// take input at this opacity, a zone fading out stops. A control that
  /// wants a zone to stop earlier, such as an item that is leaving while
  /// its replacement fades in over it, says so with [takesInput].
  static const double minimumOpacity = 0.01;

  /// The zone's box as painted, in the coordinates of the [InputZones]
  /// host, which are those of its child.
  final Rect rect;

  /// How opaque the zone is painted, from 0 to 1.
  final double opacity;

  /// Whether the control lets the zone take input in this frame: false
  /// for a zone that is leaving, covered or not yet shown.
  final bool takesInput;

  /// The corners of the zone as painted: the shape a presentation that
  /// grows out of the zone starts from.
  final BorderRadius radius;

  /// Whether the zone is there for input and accessibility in this frame:
  /// it [takesInput], is painted at [minimumOpacity] or more, and has an
  /// area.
  bool get live => takesInput && opacity >= minimumOpacity && !rect.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is InputZoneFrame &&
      other.rect == rect &&
      other.opacity == opacity &&
      other.takesInput == takesInput &&
      other.radius == radius;

  @override
  int get hashCode => Object.hash(rect, opacity, takesInput, radius);
}

/// One interactive part of a control that paints many parts in one render
/// object: a bar item, an alert action, a segment, a menu row, a day.
///
/// A zone is what a lone `InputRegion` is, without a widget of its own: its
/// [interactions] hear the touches that land on it, in its own
/// coordinates (its rect's top left is the origin), and the keyboard and
/// accessibility commands sent to it; it has a focus node, a mouse cursor,
/// hover, a state set and a semantics node. Its geometry comes from
/// [InputZones.frameOf].
@immutable
class InputZone<T extends Object> {
  /// Describes the zone [id].
  const InputZone({
    required this.id,
    this.interactions = const [],
    this.enabled = true,
    this.states = const {},
    this.mouseCursor,
    this.reach = PressReach.box,
    this.autofocus = false,
    this.focusable = true,
    this.semantics,
    this.adjustRange,
  });

  /// What the zone stands for; unique among the host's zones. The host
  /// keeps the zone's focus node, session and states across rebuilds by
  /// this id.
  final T id;

  /// The zone's interactions; when two recognize on one input, the first
  /// wins. Their owner makes them once, one set per zone.
  ///
  /// A press with [InteractionRole.content] lets a gesture around the host
  /// (a row that slides, a selector's drag) take the touch once it moves.
  final List<Interaction> interactions;

  /// Whether the zone takes input. A disabled zone is still hit, so it
  /// keeps a touch from what lies below it, shows its cursor and is read
  /// by accessibility as disabled; disabling it ends its touch.
  final bool enabled;

  /// What the zone's control says of it, such as selected: never disabled,
  /// which is [enabled], nor a state input keeps. The zone publishes them
  /// with its other states (`InputZonesController.states`).
  final Set<WidgetState> states;

  /// The cursor over the zone, or null for the default.
  ///
  /// A `WidgetStateMouseCursor` resolves against the zone's states. The
  /// default is `WidgetStateMouseCursor.adaptiveClickable` when an
  /// interaction [Interaction.activates] or [Interaction.adjusts],
  /// `MouseCursor.defer` otherwise, as for `InputRegion.mouseCursor`.
  final MouseCursor? mouseCursor;

  /// Where the zone takes pointers and where a press on it holds the
  /// finger, as `InputRegion.reach`. A zone whose own rect holds the
  /// pointer wins over one whose extension does. The semantics rectangle
  /// grows the same way.
  final PressReach reach;

  /// Whether the zone takes focus when it first appears.
  final bool autofocus;

  /// Whether the zone is a focus target of its own.
  ///
  /// A zone that is not takes touch, mouse and accessibility as any other
  /// (its semantics node, its tap, its hit area) but no focus and no key:
  /// the halves of a stepper, whose control is one value control with one
  /// stop and its value commands, and whose halves are just targets with a
  /// 44 point area and a semantic button each. The focus and the keys then
  /// belong to a region around the host.
  final bool focusable;

  /// What accessibility reads for the zone, or null for a node with only
  /// what the zone does: Flutter's description of a rectangle that has no
  /// widget, as `CustomPainterSemantics.properties` and `Semantics`.
  ///
  /// ```dart
  /// InputZone(
  ///   id: day,
  ///   interactions: [press],
  ///   semantics: SemanticsProperties(
  ///     label: 'Thursday, 1 October',
  ///     button: true,
  ///     selected: picked == day,
  ///   ),
  /// )
  /// ```
  ///
  /// Every property means what it means on a `Semantics` widget. What the
  /// zone does is its own and is written over what this says: whether it is
  /// enabled and focused, the tap of a zone whose interaction
  /// [Interaction.activates], increase and decrease of one that
  /// [Interaction.adjusts]. A zone that adjusts and has a value also says
  /// its increased and decreased values, as Flutter requires.
  final SemanticsProperties? semantics;

  /// Which ways the value of a zone that adjusts can move now, or null when
  /// it always can; as `InputRegion.adjustRange`, followed without a
  /// rebuild.
  final ValueListenable<AdjustRange>? adjustRange;
}

/// Where Tab stops among the zones of an [InputZones] host.
///
/// WAI-ARIA: the tab sequence of a composite widget, every item or one
/// roving stop. Flutter: a `FocusTraversalGroup` whose items are all in
/// traversal, or a `RadioGroup`, whose radios Tab treats as one.
enum InputZoneStops {
  /// Every zone that takes a key is a stop of its own: the buttons of a
  /// dialog, the items of a toolbar.
  each,

  /// The host is one stop: Tab enters at [InputZones.current] (the
  /// selected item), else at the zone focused last, else at the first, and
  /// the next Tab leaves the group; the arrows, Home and End move among
  /// the zones. A segmented control, a tab bar, a radio-like group.
  one,
}

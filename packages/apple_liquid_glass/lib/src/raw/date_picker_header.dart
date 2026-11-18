import 'package:apple_liquid_glass/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/widgets.dart';

/// One part of a date picker's header, the month title or an arrow: a
/// button of its own for input, focus and accessibility, with a target of
/// 44 points.
class DatePickerHeaderPart extends StatelessWidget {
  /// Creates a header part whose [interactions] answer input on [child].
  const DatePickerHeaderPart({
    required this.states,
    required this.interactions,
    required this.enabled,
    required this.label,
    required this.child,
    this.value,
    this.liveRegion = false,
    super.key,
  });

  /// Where the part's region writes its states.
  final WidgetStatesController states;

  /// The part's interactions.
  final List<Interaction> interactions;

  /// Whether the part takes input.
  final bool enabled;

  /// What accessibility reads for the part.
  final String label;

  /// The part's look; accessibility reads [label] in its place.
  final Widget child;

  /// What accessibility reads as the part's value, or null.
  final String? value;

  /// Whether accessibility announces a change of [value].
  final bool liveRegion;

  @override
  Widget build(BuildContext context) => InputRegion(
    interactions: interactions,
    enabled: enabled,
    statesController: states,
    semantics: SemanticsProperties(
      label: label,
      button: true,
      value: value,
      liveRegion: liveRegion,
    ),
    reach: glassTargetReach,
    child: ExcludeSemantics(child: child),
  );
}

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:apple_liquid_glass/src/raw/source.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/widgets.dart';
import 'package:liquid_glass_renderer/painting.dart';

/// Builds a glass button from [details]; it runs when the button builds,
/// such as when its states change, never on a frame of its motion.
typedef GlassButtonBuilder = Widget Function(
  BuildContext context,
  GlassButtonDetails details,
);

/// What a [GlassButtonBuilder] builds a button from.
@immutable
final class GlassButtonDetails {
  /// Describes a button.
  const GlassButtonDetails({
    required this.body,
    required this.states,
    required this.label,
    this.statesListenable,
  });

  /// The frames of the button's body: the measured lift, lean and touch
  /// glow, in the button's own box. A builder hands it to a
  /// `GlassSurface.live` that fills the button.
  final MotionSelection<GlassFrame> body;

  /// The states the button is in.
  final Set<WidgetState> states;

  /// The button's states as they change, or null for a body that shows
  /// neither focus nor hover: a builder hands it to the `GlassSurface`
  /// of its body, whose renderer then draws the focus ring and the hover
  /// response.
  final ValueListenable<Set<WidgetState>>? statesListenable;

  /// The button's label.
  final Widget label;
}

/// Anything pressable with the measured press of an iOS 27 glass button and
/// no look of its own: [builder] decides how it looks.
///
/// UIKit: `UIButton` with a glass configuration. SwiftUI: `Button` with
/// `.buttonStyle(.glass)`. Flutter: `RawMaterialButton`.
///
/// A touch lifts the body, a finger that drags leans and stretches it
/// toward itself, and a glow follows the finger; a release within 70
/// points of the button presses it. All of that reaches the look through
/// [GlassButtonDetails.body], so the builder never runs while the button
/// moves. The app's `ActivateIntent` (Space and Enter under a `WidgetsApp`)
/// and the accessibility tap press it too. A finger takes it within a 44
/// by 44 point area around a smaller body, where the button's parent
/// leaves that room; the body does not grow. Under Reduce Motion (kinesis's
/// motion traits) the body glows but never lifts or leans (an
/// approximation, not measured).
///
/// Inside a `GlassMenuAnchor` (under a [GlassSourceScope]) the button keeps
/// its touches, keys, focus, states and semantics, and its body stays at
/// rest: the anchor presses the whole button by the menu's measured press
/// as it watches the same touch.
class RawGlassButton extends StatefulWidget {
  /// Creates a button labeled [child] whose look [builder] builds.
  const RawGlassButton({
    required this.onPressed,
    required this.builder,
    required this.child,
    this.shape = LiquidRoundedSuperellipse.capsule,
    this.statesController,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    super.key,
  });

  /// Called when the button is pressed; null disables it.
  final VoidCallback? onPressed;

  /// Builds the button's look.
  final GlassButtonBuilder builder;

  /// The button's label.
  final Widget child;

  /// The outline of the button's body.
  final LiquidShape shape;

  /// Where the button publishes its states, or null for its own. The button is
  /// its only writer: what else writes to it is written over.
  final WidgetStatesController? statesController;

  /// The button's focus node, or null for its own.
  final FocusNode? focusNode;

  /// Whether the button takes focus when it first appears.
  final bool autofocus;

  /// What accessibility reads for the button; null lets its label speak.
  final String? semanticLabel;

  @override
  State<RawGlassButton> createState() => _RawGlassButtonState();
}

class _RawGlassButtonState extends State<RawGlassButton>
    with ControlStates<RawGlassButton> {
  final GlassPress _press = GlassPress();
  late final _tap = PressInteraction(
    onTap: (t) => widget.onPressed?.call(),
  );
  late final List<Interaction> _interactions = [
    _tap.simultaneously(FollowInteraction(_press)),
  ];
  late final List<Interaction> _sourceInteractions = [_tap];
  late MotionSelection<GlassFrame> _body = _bodyOf(widget.shape);

  MotionSelection<GlassFrame> _bodyOf(LiquidShape shape) => _press.select(
    (press) => press.isAtRest
        ? GlassFrame(shape: shape)
        : GlassFrame(
            shape: shape,
            rect: (Offset.zero & press.size).shift(press.lean),
            scaleX: press.scaleX,
            scaleY: press.scaleY,
            glow: press.touchGlow,
          ),
  );

  late MotionSelection<GlassFrame> _resting = _restingOf(widget.shape);

  static MotionSelection<GlassFrame> _restingOf(LiquidShape shape) =>
      MotionSelection(() => GlassFrame(shape: shape));

  @override
  WidgetStatesController? get givenStates => widget.statesController;

  @override
  void didUpdateWidget(RawGlassButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shape != oldWidget.shape) {
      _body = _bodyOf(widget.shape);
      _resting = _restingOf(widget.shape);
    }
  }

  @override
  bool get enabled => widget.onPressed != null;

  @override
  Widget build(BuildContext context) {
    final source = GlassSource.isSourceAt(context);
    return MotionScope(
      motion: _press,
      child: InputRegion(
        interactions: source ? _sourceInteractions : _interactions,
        enabled: enabled,
        statesController: widgetStates,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        semantics: SemanticsProperties(
          label: widget.semanticLabel,
          button: true,
        ),
        reach: glassButtonReach,
        child: ExcludeSemantics(
          excluding: widget.semanticLabel != null,
          child: _described(
            source,
            widget.builder(
              context,
              GlassButtonDetails(
                body: source ? _resting : _body,
                states: {...widgetStates.value},
                statesListenable: widgetStates,
                label: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _described(bool source, Widget body) => source
      ? GlassSource(
          description: GlassSourceDescription(
            shape: widget.shape,
            semanticLabel: widget.semanticLabel,
          ),
          child: body,
        )
      : body;
}

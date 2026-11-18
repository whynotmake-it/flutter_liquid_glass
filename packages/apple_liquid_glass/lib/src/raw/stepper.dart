import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/src/raw/still.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/widgets.dart';

/// A half of a stepper.
enum GlassStepperHalf {
  /// The minus half, on the left in either direction.
  decrement,

  /// The plus half, on the right in either direction.
  increment,
}

/// Builds a glass stepper from [details]; it runs again when the held half
/// or the states change.
typedef GlassStepperBuilder = Widget Function(
  BuildContext context,
  GlassStepperDetails details,
);

/// What a [GlassStepperBuilder] builds a stepper from.
@immutable
final class GlassStepperDetails {
  /// Describes a stepper.
  const GlassStepperDetails({
    required this.pressed,
    required this.canDecrement,
    required this.canIncrement,
    required this.states,
    this.statesListenable,
  });

  /// The half a finger holds, or null.
  final GlassStepperHalf? pressed;

  /// Whether the value is above the minimum.
  final bool canDecrement;

  /// Whether the value is below the maximum.
  final bool canIncrement;

  /// The states the stepper is in.
  final Set<WidgetState> states;

  /// The stepper's states as they change, or null for a look that shows
  /// neither focus nor hover: a builder hands it to the `GlassSurface` of
  /// the halves, whose renderer then draws the focus ring and the hover
  /// response.
  final ValueListenable<Set<WidgetState>>? statesListenable;
}

/// A stepper with the behavior of iOS 27's `UIStepper` and no look of its own:
/// [builder] decides how it looks.
///
/// UIKit: `UIStepper`. SwiftUI: `Stepper`. Flutter: none.
///
/// There is no motion: a held half highlights at once and clears on release. A
/// tap commits on release; a held half repeats every half second, first
/// after that long, without acceleration (stepper passport, device: 0.520,
/// 1.021, 1.522 s after the touch). Sliding to the other half moves the
/// highlight and the repeat with it without a step, and leaving the control's
/// 44 point tall target, which reaches above and below its 32 point box where
/// its parent leaves that room, cancels the touch. Minus stays on the left in a
/// right-to-left context, as UIKit's does (stepper passport, device), and so do
/// the arrow keys: left and down decrement, right and up increment, in either
/// direction. Home and End take the value to [min] and [max]; the stepper has
/// no larger step, so Page Up and Page Down do nothing, and neither do Space
/// and Enter, as on Flutter's `Slider`. The stepper is one Tab stop; its halves
/// are zones that are not focus targets. Screen readers see two buttons with 44
/// point targets that announce the value and run the same commands as the keys,
/// inside one adjustable node with the value and the accessibility increase and
/// decrease. A disabled stepper ignores input; [builder] sees
/// [WidgetState.disabled].
class RawGlassStepper extends StatefulWidget {
  /// Creates a stepper showing [value] between [min] and [max].
  const RawGlassStepper({
    required this.value,
    required this.onChanged,
    required this.builder,
    this.min = 0,
    this.max = 100,
    this.step = 1,
    this.decrementLabel,
    this.incrementLabel,
    this.semanticFormatterCallback,
    this.semanticLabel,
    this.statesController,
    this.focusNode,
    this.autofocus = false,
    super.key,
  });

  /// The value.
  final double value;

  /// Called with the new value when the user steps; null disables the
  /// stepper.
  final ValueChanged<double>? onChanged;

  /// Builds the stepper's look.
  final GlassStepperBuilder builder;

  /// The lowest value.
  final double min;

  /// The highest value.
  final double max;

  /// How much one step changes the value.
  final double step;

  /// What screen readers announce for the minus half; null reads
  /// [GlassLocalizations.decrementLabel].
  final String? decrementLabel;

  /// What screen readers announce for the plus half; null reads
  /// [GlassLocalizations.incrementLabel].
  final String? incrementLabel;

  /// Formats the value each half announces; null uses up to twelve
  /// significant digits without binary floating-point tails.
  final String Function(double value)? semanticFormatterCallback;

  /// What accessibility reads for the stepper.
  final String? semanticLabel;

  /// Where the stepper publishes its states, or null for its own. The
  /// stepper is its only writer: what else writes to it is written over.
  final WidgetStatesController? statesController;

  /// The stepper's focus node, or null for its own.
  final FocusNode? focusNode;

  /// Whether the stepper takes focus when it first appears.
  final bool autofocus;

  /// The size of the stepper (stepper passport, device).
  static const Size size = Size(94, 32);

  static const Duration _repeatInterval = Duration(milliseconds: 500);

  @override
  State<RawGlassStepper> createState() => _RawGlassStepperState();
}

class _RawGlassStepperState extends State<RawGlassStepper>
    with ControlStates<RawGlassStepper> {
  late final _StepperInput _input = _StepperInput(
    onPressed: (half) => setState(() => _pressed = half),
    onStep: _stepBy,
    onCommand: _command,
  );
  late final List<Interaction> _interactions = [_input];
  late final Map<GlassStepperHalf, _HalfButton> _halfInputs = {
    for (final half in GlassStepperHalf.values)
      half: _HalfButton(() => _halfActivated(half)),
  };
  final GlobalKey _halves = GlobalKey();
  GlassStepperHalf? _pressed;

  @override
  WidgetStatesController? get givenStates => widget.statesController;

  @override
  bool get enabled => widget.onChanged != null;

  double get _minimum => widget.min.isFinite ? widget.min : 0;

  double get _maximum =>
      widget.max.isFinite && widget.max >= _minimum ? widget.max : _minimum;

  double get _value =>
      widget.value.isFinite ? widget.value.clamp(_minimum, _maximum) : _minimum;

  bool _canStep(GlassStepperHalf half) => switch (half) {
    GlassStepperHalf.decrement => _value > _minimum,
    GlassStepperHalf.increment => _value < _maximum,
  };

  double _after(GlassStepperHalf half) {
    final step = widget.step;
    if (!step.isFinite || step <= 0 || !_canStep(half)) return _value;
    final delta = half == GlassStepperHalf.increment ? step : -step;
    return (_value + delta).clamp(_minimum, _maximum);
  }

  void _stepBy(GlassStepperHalf half) {
    final next = _after(half);
    if (next != _value) widget.onChanged?.call(next);
  }

  void _command(ValueCommand command) {
    switch (command) {
      case ValueCommand.increase:
        _stepBy(GlassStepperHalf.increment);
      case ValueCommand.decrease:
        _stepBy(GlassStepperHalf.decrement);
      case ValueCommand.toMinimum:
        if (_canStep(GlassStepperHalf.decrement)) {
          widget.onChanged?.call(_minimum);
        }
      case ValueCommand.toMaximum:
        if (_canStep(GlassStepperHalf.increment)) {
          widget.onChanged?.call(_maximum);
        }
      case ValueCommand.increaseLarge || ValueCommand.decreaseLarge:
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = GlassLocalizations.of(context);
    String format(double value) =>
        widget.semanticFormatterCallback?.call(value) ?? _format(value);
    final value = format(_value);
    InputZone<GlassStepperHalf> half(GlassStepperHalf half, String label) =>
        InputZone(
          id: half,
          interactions: [_halfInputs[half]!],
          enabled: enabled && _canStep(half),
          focusable: false,
          reach: glassTargetReach,
          semantics: SemanticsProperties(
            label: label,
            value: value,
            button: true,
          ),
        );
    final direction = Directionality.of(context);
    // The region lays its arrow keys out left to right, as the halves are.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: InputRegion(
        interactions: _interactions,
        enabled: enabled,
        statesController: widgetStates,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        semantics: SemanticsProperties(
          label: widget.semanticLabel,
          value: value,
          increasedValue: format(_after(GlassStepperHalf.increment)),
          decreasedValue: format(_after(GlassStepperHalf.decrement)),
        ),
        reach: glassTargetReach,
        child: SizedBox.fromSize(
          size: RawGlassStepper.size,
          child: InputZones<GlassStepperHalf>(
            key: _halves,
            zones: [
              half(
                GlassStepperHalf.decrement,
                widget.decrementLabel ?? strings.decrementLabel,
              ),
              half(
                GlassStepperHalf.increment,
                widget.incrementLabel ?? strings.incrementLabel,
              ),
            ],
            frameOf: _frameOf,
            frames: still,
            child: Directionality(
              textDirection: direction,
              child: Builder(
                builder: (context) => widget.builder(
                  context,
                  GlassStepperDetails(
                    pressed: _pressed,
                    canDecrement: _canStep(GlassStepperHalf.decrement),
                    canIncrement: _canStep(GlassStepperHalf.increment),
                    states: {...widgetStates.value},
                    statesListenable: widgetStates,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static InputZoneFrame _frameOf(GlassStepperHalf half) {
    final halfSize = Size(
      RawGlassStepper.size.width / 2,
      RawGlassStepper.size.height,
    );
    return InputZoneFrame(
      switch (half) {
            GlassStepperHalf.decrement => Offset.zero,
            GlassStepperHalf.increment => Offset(halfSize.width, 0),
          } &
          halfSize,
    );
  }

  // A half's button runs the stepper's own command through the actions
  // above the halves, so an app that overrides AdjustValueIntent hears it.
  void _halfActivated(GlassStepperHalf half) {
    final context = _halves.currentContext;
    if (context == null) return;
    Actions.maybeInvoke(
      context,
      AdjustValueIntent(switch (half) {
        GlassStepperHalf.decrement => ValueCommand.decrease,
        GlassStepperHalf.increment => ValueCommand.increase,
      }),
    );
  }

  static String _format(double value) {
    final digits = value.toStringAsPrecision(12);
    final number = double.parse(digits);
    return number == number.truncateToDouble()
        ? number.toInt().toString()
        : number.toString();
  }
}

/// A half's button for the keyboard-free activation assistive technology
/// sends; touch stays with the stepper's own input around the halves.
final class _HalfButton extends Interaction {
  _HalfButton(this.onActivate) : super(role: InteractionRole.control);

  final VoidCallback onActivate;

  @override
  bool get activates => true;

  @override
  bool accepts(PointerDownInput down) => false;

  @override
  InteractionUpdate handle(InteractionInput input) {
    if (input is ActivateInput) onActivate();
    return InteractionUpdate.none;
  }
}

/// A stepper's touch, its repeat and its value commands.
final class _StepperInput extends Interaction {
  _StepperInput({
    required this.onPressed,
    required this.onStep,
    required this.onCommand,
  }) : super(role: InteractionRole.control);

  final ValueChanged<GlassStepperHalf?> onPressed;
  final ValueChanged<GlassStepperHalf> onStep;
  final ValueChanged<ValueCommand> onCommand;
  static final double _interval =
      RawGlassStepper._repeatInterval.inMicroseconds / 1e6;

  int? _pointer;
  PressReach _reach = PressReach.box;
  GlassStepperHalf? _half;
  double? _due;
  bool _repeated = false;

  @override
  bool get pressed => _half != null;

  @override
  bool get adjusts => true;

  @override
  double? get nextDue => _due;

  GlassStepperHalf? _halfAt(Offset position, Rect box) {
    if (!_reach.holds(box, position)) return null;
    return position.dx < box.center.dx
        ? GlassStepperHalf.decrement
        : GlassStepperHalf.increment;
  }

  void _hold(GlassStepperHalf? half) {
    if (half == _half) return;
    _half = half;
    onPressed(half);
  }

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case AdjustInput(:final command):
        onCommand(command);
      case PointerDownInput() when _pointer == null && accepts(input):
        _reach = input.reach;
        final half = _halfAt(input.position, Offset.zero & input.regionSize);
        if (half == null) return const InteractionUpdate(fails: true);
        _pointer = input.pointer;
        _repeated = false;
        _due = input.time + _interval;
        _hold(half);
        return const InteractionUpdate(claims: true);
      case PointerMoveInput() when input.pointer == _pointer:
        final half = _halfAt(input.position, input.regionBox);
        if (half == null) return _end(fails: true);
        _hold(half);
      case PointerUpInput() when input.pointer == _pointer:
        final half = _half;
        final repeated = _repeated;
        _end(fails: false);
        if (half != null && !repeated) onStep(half);
        return const InteractionUpdate(recognizes: true);
      case PointerCancelInput() when input.pointer == _pointer:
        return _end(fails: true);
      default:
    }
    return InteractionUpdate.none;
  }

  InteractionUpdate _end({required bool fails}) {
    _pointer = null;
    _due = null;
    _hold(null);
    return InteractionUpdate(fails: fails);
  }

  @override
  InteractionUpdate advance(double time) {
    final due = _due;
    final half = _half;
    if (due == null || half == null || time < due) {
      return InteractionUpdate.none;
    }
    _repeated = true;
    _due = due + _interval;
    onStep(half);
    return InteractionUpdate.none;
  }
}

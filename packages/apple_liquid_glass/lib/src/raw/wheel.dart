import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/widgets.dart';

/// Builds one row of a [RawGlassWheel], from 0 to its count less one; it
/// runs when the wheel's rows are built, never on a frame of its turn.
typedef GlassWheelRowBuilder = Widget Function(BuildContext context, int row);

/// Builds what a [RawGlassWheel] draws over its selected row, such as the
/// focus ring and the hover wash, from the wheel's states.
typedef GlassWheelSelectionBuilder = Widget Function(
  BuildContext context,
  ValueListenable<Set<WidgetState>> states,
);

/// One of iOS 27's picker wheels with no look of its own: a column of
/// rows on a cylinder that a finger turns and that comes to rest on a row.
///
/// UIKit: one component of `UIPickerView`, as `UIDatePicker` with `.wheels`
/// shows it. SwiftUI: `Picker` with `.wheel`. Flutter:
/// `ListWheelScrollView`.
///
/// A finger turns the wheel with a fling that snaps to a row. Each row the
/// wheel comes to on its way plays a selection haptic and calls
/// [onChanged], with [onWrapped] first when a looping wheel passed its
/// last row; a wheel whose [value] does not follow returns to it once the
/// finger and the glide stop. A new [value] from the app turns the wheel
/// to it (in a short step with [animatesValue]) without calling anything.
///
/// It is a value control: one Tab stop whose arrows step a row, Page Up and
/// Page Down a quarter of the rows, Home and End go to the first and last
/// row, and whose accessibility increase and decrease step a row; a key
/// turns the wheel in a short step. Screen readers read [semanticLabel]
/// and [rowLabel] of the value, with the rows on either side as the
/// increased and decreased values. A wheel that does not loop stops at its
/// ends.
class RawGlassWheel extends StatefulWidget {
  /// Creates a wheel of [count] rows showing [value].
  const RawGlassWheel({
    required this.count,
    required this.value,
    required this.onChanged,
    required this.rowBuilder,
    required this.itemExtent,
    this.looping = true,
    this.onWrapped,
    this.diameterRatio = RenderListWheelViewport.defaultDiameterRatio,
    this.perspective = RenderListWheelViewport.defaultPerspective,
    this.squeeze = 1,
    this.magnification = 1,
    this.overAndUnderCenterOpacity = 1,
    this.rowsKey,
    this.animatesValue = false,
    this.selectionBuilder,
    this.semanticLabel,
    this.rowLabel,
    this.statesController,
    this.focusNode,
    this.autofocus = false,
    super.key,
  }) : assert(count > 0, 'A wheel has a row.');

  /// How many rows the wheel has.
  final int count;

  /// The selected row, from 0 to [count] less one.
  final int value;

  /// Called with the row the wheel comes to as the user turns it; null
  /// disables the wheel.
  final ValueChanged<int>? onChanged;

  /// Called before [onChanged] with how many times a looping wheel passed
  /// from its last row to its first (positive) or back (negative) on its
  /// way to the new row.
  final ValueChanged<int>? onWrapped;

  /// Builds each row.
  final GlassWheelRowBuilder rowBuilder;

  /// Whether the rows repeat past the last one, as an hour wheel's do.
  final bool looping;

  /// The distance between two rows along the cylinder.
  final double itemExtent;

  /// The cylinder's diameter over the wheel's height.
  final double diameterRatio;

  /// How strongly the cylinder recedes from the viewer.
  final double perspective;

  /// The squeeze that turns [itemExtent] into the angle between two rows on
  /// the cylinder.
  final double squeeze;

  /// How much larger the selected row draws than the others.
  final double magnification;

  /// The opacity of the rows outside the selected one.
  final double overAndUnderCenterOpacity;

  /// What the rows show, or null to build them each time the wheel builds:
  /// while it stays equal, along with [count], [looping] and the cylinder,
  /// a new [value] or a rebuild of the wheel builds no row.
  final Object? rowsKey;

  /// Whether a new [value] turns the wheel in a short step instead of
  /// jumping to it.
  final bool animatesValue;

  /// Builds what the wheel draws over its selected row, or null for
  /// nothing.
  final GlassWheelSelectionBuilder? selectionBuilder;

  /// What accessibility reads for the wheel.
  final String? semanticLabel;

  /// What accessibility reads for a row, or null for no value.
  final String Function(int row)? rowLabel;

  /// Where the wheel publishes its states, or null for its own. The wheel is
  /// its only writer: what else writes to it is written over.
  final WidgetStatesController? statesController;

  /// The wheel's focus node, or null for its own.
  final FocusNode? focusNode;

  /// Whether the wheel takes focus when it first appears.
  final bool autofocus;

  @override
  State<RawGlassWheel> createState() => _RawGlassWheelState();
}

class _RawGlassWheelState extends State<RawGlassWheel>
    with ControlStates<RawGlassWheel>, ControlledValue<RawGlassWheel> {
  // A looping wheel lays out this many laps of its rows and starts in the
  // middle one, so a finger never reaches an end.
  static const int _laps = 100;

  // A key's step, not measured on a device.
  static const Duration _step = Duration(milliseconds: 200);
  static const Curve _stepCurve = Cubic(0.25, 0.1, 0.25, 1);

  late final FixedExtentScrollController _controller =
      FixedExtentScrollController(initialItem: _centered(widget.value));
  late final ValueNotifier<AdjustRange> _range = ValueNotifier(_rangeNow());
  late final List<Interaction> _interactions = [_WheelInput(_command)];
  late int _item = _controller.initialItem;
  late int _shown = widget.value;
  bool _dragging = false;
  Widget? _cylinder;
  Object? _cylinderKey;

  int get _count => widget.count;

  int _centered(int row) => widget.looping ? _count * (_laps ~/ 2) + row : row;

  AdjustRange _rangeNow() => AdjustRange(
    canIncrease: widget.looping || widget.value + 1 < _count,
    canDecrease: widget.looping || widget.value > 0,
  );

  @override
  WidgetStatesController? get givenStates => widget.statesController;

  @override
  bool get enabled => widget.onChanged != null;

  @override
  MotionClock get valueClock => MotionClockScope.of(context);

  @override
  bool get userLeads => _dragging;

  @override
  void didUpdateWidget(RawGlassWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _range.value = _rangeNow();
    if (widget.count != oldWidget.count ||
        widget.looping != oldWidget.looping) {
      _shown = widget.value;
      if (_controller.hasClients) _controller.jumpToItem(_centered(_shown));
      return;
    }
    followWidget();
  }

  @override
  void dispose() {
    _controller.dispose();
    _range.dispose();
    super.dispose();
  }

  @override
  void followWidget() {
    final value = widget.value;
    if (!_controller.hasClients) {
      _shown = value;
      return;
    }
    final item = _controller.selectedItem;
    if (item % _count == value && _shown == value) return;
    _shown = value;
    final to = _nearest(item, value);
    if (to == item) return;
    if (widget.animatesValue) {
      _controller.animateToItem(to, duration: _step, curve: _stepCurve);
    } else {
      _controller.jumpToItem(to);
    }
  }

  // The item showing [row] closest to [item], in the lap of [item] or the
  // one beside it.
  int _nearest(int item, int row) {
    if (!widget.looping) return row;
    final base = item - item % _count + row;
    final candidates = [base - _count, base, base + _count];
    final last = _count * _laps - 1;
    var best = base.clamp(0, last);
    for (final c in candidates) {
      if (c < 0 || c > last) continue;
      if ((c - item).abs() < (best - item).abs()) best = c;
    }
    return best;
  }

  void _selected(int item) {
    final laps = item ~/ _count - _item ~/ _count;
    _item = item;
    final row = item % _count;
    if (row == _shown) return;
    _shown = row;
    // A row's detent is no event of the region's interactions: the wheel's
    // own scrolling turns it, so it plays as the row arrives.
    MotionHaptic.selection.play(context);
    tellApp(() {
      if (laps != 0) widget.onWrapped?.call(laps);
      widget.onChanged?.call(row);
    });
  }

  bool _scrolled(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    switch (notification) {
      case ScrollStartNotification(:final dragDetails):
        _dragging = dragDetails != null;
      case ScrollEndNotification() when _dragging:
        _dragging = false;
        returnUnlessFollowed();
      default:
    }
    return false;
  }

  void _command(ValueCommand command) {
    if (!_controller.hasClients) return;
    final item = _controller.selectedItem;
    final first = widget.looping ? item - item % _count : 0;
    final large = math.max(2, _count ~/ 4);
    final target = switch (command) {
      ValueCommand.increase => item + 1,
      ValueCommand.decrease => item - 1,
      ValueCommand.increaseLarge => item + large,
      ValueCommand.decreaseLarge => item - large,
      ValueCommand.toMinimum => first,
      ValueCommand.toMaximum => first + _count - 1,
    };
    final last = widget.looping ? _count * _laps - 1 : _count - 1;
    final to = target.clamp(0, last);
    if (to == item) return;
    _controller.animateToItem(to, duration: _step, curve: _stepCurve);
  }

  Widget _cylinderOf() {
    final rowsKey = widget.rowsKey;
    final key = (
      rowsKey,
      _count,
      widget.looping,
      widget.itemExtent,
      widget.diameterRatio,
      widget.perspective,
      widget.squeeze,
      widget.magnification,
      widget.overAndUnderCenterOpacity,
    );
    final kept = _cylinder;
    if (rowsKey != null && kept != null && key == _cylinderKey) return kept;
    _cylinderKey = key;
    final rowBuilder = widget.rowBuilder;
    return _cylinder = ListWheelScrollView.useDelegate(
      controller: _controller,
      itemExtent: widget.itemExtent,
      diameterRatio: widget.diameterRatio,
      perspective: widget.perspective,
      squeeze: widget.squeeze,
      useMagnifier: widget.magnification != 1,
      magnification: widget.magnification,
      overAndUnderCenterOpacity: widget.overAndUnderCenterOpacity,
      physics: const FixedExtentScrollPhysics(
        parent: BouncingScrollPhysics(
          decelerationRate: ScrollDecelerationRate.fast,
        ),
      ),
      onSelectedItemChanged: _selected,
      childDelegate: ListWheelChildBuilderDelegate(
        childCount: widget.looping ? _count * _laps : _count,
        builder: (context, i) => rowBuilder(context, i % _count),
      ),
    );
  }

  @override
  Widget buildControl(BuildContext context) {
    final value = widget.value;
    final rowLabel = widget.rowLabel;
    final range = _range.value;
    final selection = widget.selectionBuilder;
    return InputRegion(
      interactions: _interactions,
      statesController: widgetStates,
      enabled: enabled,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      adjustRange: _range,
      semantics: SemanticsProperties(
        label: widget.semanticLabel,
        value: rowLabel?.call(value),
        increasedValue: range.canIncrease
            ? rowLabel?.call((value + 1) % _count)
            : null,
        decreasedValue: range.canDecrease
            ? rowLabel?.call((value - 1) % _count)
            : null,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: _scrolled,
            child: ExcludeSemantics(child: _cylinderOf()),
          ),
          if (selection != null)
            Center(
              child: SizedBox(
                height: widget.itemExtent,
                child: IgnorePointer(child: selection(context, widgetStates)),
              ),
            ),
        ],
      ),
    );
  }
}

/// A wheel's value commands, for the keyboard and accessibility; touches
/// are the wheel's own scrolling.
final class _WheelInput extends Interaction {
  _WheelInput(this.onCommand) : super(role: InteractionRole.control);

  final ValueChanged<ValueCommand> onCommand;

  @override
  bool get adjusts => true;

  @override
  bool accepts(PointerDownInput down) => false;

  @override
  InteractionUpdate handle(InteractionInput input) {
    if (input is AdjustInput) onCommand(input.command);
    return InteractionUpdate.none;
  }
}

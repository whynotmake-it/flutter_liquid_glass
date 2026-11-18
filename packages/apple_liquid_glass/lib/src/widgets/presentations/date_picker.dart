import 'dart:async';
import 'dart:math' as math;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:apple_liquid_glass/raw.dart';
import 'package:apple_liquid_glass/src/widgets/controls/date_picker.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/presentation.dart';
import 'package:kinesis/widgets.dart';
import 'package:liquid_glass_renderer/painting.dart';

part 'package:apple_liquid_glass/src/widgets/presentations/date_picker_label.dart';
part 'package:apple_liquid_glass/src/widgets/presentations/date_picker_look.dart';
part 'package:apple_liquid_glass/src/widgets/presentations/date_picker_overlay.dart';

/// What a [GlassCompactDatePicker] picks.
enum GlassDatePickerMode {
  /// A day: one label that opens a month calendar.
  date,

  /// A time of day: one label that opens the hour and minute wheels.
  time,

  /// A day and a time: a date label and a time label side by side.
  dateAndTime,
}

/// [value] floored to [interval] as [GlassCompactDatePicker.minuteInterval]
/// describes; unchanged for an interval of 1.
DateTime _floorToMinuteInterval(DateTime value, int interval) {
  if (interval < 2) return value;
  return value.copyWith(
    minute: value.minute - value.minute % interval,
    second: 0,
    millisecond: 0,
    microsecond: 0,
  );
}

/// The iOS 27 compact date picker: a label that opens its picker in an
/// overlay.
///
/// UIKit: `UIDatePicker` with `.compact`. SwiftUI: `DatePicker` with
/// `.compact`. Flutter: `showDatePicker` and `showTimePicker`.
///
/// The label is a tinted capsule showing [value]; a touch dims its text,
/// and a tap opens the overlay out of it: a [GlassDatePicker] for a date,
/// the hour and minute wheels for a time. The overlay grows out of the
/// label's center on a spring while it fades in and reveals its content
/// from the label's side, hangs below the label (above it when there is no
/// room), and extends toward the leading side, on springs fitted to
/// UIKit's frames (replayed on an iPhone 16 Pro).
/// While it is open the label's text takes the accent color. Choosing a day
/// or turning a time wheel calls [onChanged] at once and the overlay stays
/// open; a tap outside or Escape closes it, turning an overlay that still
/// opens around. A tap on the label while the overlay closes opens a new
/// one after a shorter delay than a first open, as UIKit does, while the
/// old one finishes its close. With both labels, a tap on the other label
/// turns the open overlay into its picker.
///
/// In 12-hour time the wheels are the hour (1 to 12), the minute and AM/PM,
/// as UIKit lays them out; the hour wheel turning past 11 and 12 switches
/// AM and PM.
///
/// The texts come from [GlassLocalizations]. The label is a button and a
/// Tab stop; Space and Enter open it, and screen readers hear it expand. The
/// overlay is a dialog to screen readers, with a barrier that dismisses it;
/// it takes the focus at the picked day, and the focus returns to the label
/// when it closes. Focused from the keyboard, the label draws Flutter's
/// Cupertino focus ring, and a mouse over it washes it as a glass body's
/// hover does (an approximation, not measured). A disabled picker draws
/// its labels as text without their capsules and does not open.
///
/// The content fades inside the overlay's clip: NEAR (the clip's
/// anti-aliased edge row differs by up to 23 of 255 in the first frames
/// of the opening). The day grid (the time wheels) mounts on the frame
/// after the overlay's, while the overlay is still transparent, so the
/// open's layout spreads over two frames (IDENTICAL). A label dims under
/// the finger through the alpha of its text color instead of an opacity
/// layer: NEAR (one rounding instead of two, at most 1 of 255 per
/// channel, except where the anti-aliased edges of two glyphs share a
/// pixel, which a layer would cover once and the color covers twice).
class GlassCompactDatePicker extends StatefulWidget {
  /// Creates a picker.
  const GlassCompactDatePicker({
    required this.value,
    required this.onChanged,
    this.mode = GlassDatePickerMode.date,
    this.style,
    this.minuteInterval = 1,
    this.minimumDate,
    this.maximumDate,
    this.use24HourFormat,
    this.firstDayOfWeek = DateTime.sunday,
    this.today,
    this.semanticLabel,
    super.key,
  }) : assert(
         minuteInterval >= 1 &&
             minuteInterval <= 30 &&
             60 % minuteInterval == 0,
         'minuteInterval must divide 60 and lie in 1 to 30.',
       );

  /// The colors, over the theme's and the picker's defaults.
  final GlassDatePickerStyle? style;

  /// The step of the minute wheel in minutes, a divisor of 60 from 1 to
  /// 30 (UIKit `minuteInterval`). As UIKit's `roundsToMinuteInterval`
  /// does, a time between two multiples is rounded DOWN to the earlier one
  /// with its seconds dropped, in the label and on the wheel alike, and the
  /// picker reports only such times (read from UIKit, notes private).
  final int minuteInterval;

  /// The picked moment.
  final DateTime value;

  /// Called with the new moment when the user picks one; null disables
  /// the picker.
  final ValueChanged<DateTime>? onChanged;

  /// What the picker picks.
  final GlassDatePickerMode mode;

  /// The earliest moment that can be picked; null for no limit. The
  /// calendar disables earlier days and the time wheels honor the time
  /// on the boundary day. Later than [maximumDate], both are ignored, as
  /// UIKit ignores them.
  final DateTime? minimumDate;

  /// The latest moment that can be picked; null for no limit. The time
  /// wheels honor its time on the boundary day.
  final DateTime? maximumDate;

  /// Whether times use 24 hours; null follows the platform's
  /// [MediaQueryData.alwaysUse24HourFormat] (the device's 24-Hour Time
  /// setting on iOS), as UIKit follows the locale's.
  final bool? use24HourFormat;

  /// The first column of the calendar, as a [DateTime] weekday.
  final int firstDayOfWeek;

  /// The day to tint as today; null for the current day.
  final DateTime? today;

  /// The label screen readers announce before the value.
  final String? semanticLabel;

  @override
  State<GlassCompactDatePicker> createState() => _GlassCompactDatePickerState();
}

enum _Part { date, time }

// What the open overlay shows of its picker; null once the picker is gone.
typedef _PickerConfig = ({GlassCompactDatePicker picker, bool twentyFour});

class _GlassCompactDatePickerState extends State<GlassCompactDatePicker> {
  _Part? _open;
  DatePickerMotion? _overlay;
  final _config = ValueNotifier<_PickerConfig?>(null);
  final Map<_Part, GlobalKey> _labels = {
    _Part.date: GlobalKey(debugLabel: 'date'),
    _Part.time: GlobalKey(debugLabel: 'time'),
  };

  Rect? _labelRect(_Part part) {
    final box = _labels[part]!.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _switched(_Part part) {
    if (mounted) setState(() => _open = part);
  }

  bool get _enabled => widget.onChanged != null;

  bool get _twentyFour => use24HourFormatAt(context, widget.use24HourFormat);

  void _configure() =>
      _config.value = (picker: widget, twentyFour: _twentyFour);

  Future<void> _show(_Part part, BuildContext anchor) async {
    if (!_enabled || _open != null) return;
    final box = anchor.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final rect = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    setState(() => _open = part);
    final reopening = _overlay?.presence == PresenceStatus.leaving;
    final days = FocusNode(debugLabel: 'GlassCompactDatePicker days');
    final loc = GlassLocalizations.of(context);
    await showPresentation<void>(
      context,
      PresentationRoute(
        presentation: Presentation<void, DatePickerMotion>(
          motion: (_) => _overlay = DatePickerMotion(reopening: reopening),
          semanticsRole: SemanticsRole.dialog,
          barrierLabel: loc.datePickerDismissLabel,
          initialFocus: part == _Part.date ? days : null,
          builder: (context, motion) => _OverlayView(
            config: _config,
            labelRect: _labelRect,
            onSwitched: _switched,
            onChanged: _changed,
            motion: motion,
            part: part,
            label: rect,
            days: days,
          ),
        ),
      ),
    );
    days.dispose();
    if (mounted) setState(() => _open = null);
  }

  void _changed(DateTime value) => widget.onChanged?.call(value);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configure();
  }

  @override
  void didUpdateWidget(GlassCompactDatePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    _configure();
  }

  @override
  void dispose() {
    _config.value = null;
    _config.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = GlassLocalizations.of(context);
    final value = _floorToMinuteInterval(widget.value, widget.minuteInterval);
    final date = loc.compactDate(value);
    final time = loc.compactTime(value, use24HourFormat: _twentyFour);
    final parts = switch (widget.mode) {
      GlassDatePickerMode.date => [(_Part.date, date)],
      GlassDatePickerMode.time => [(_Part.time, time)],
      GlassDatePickerMode.dateAndTime => [
        (_Part.date, date),
        (_Part.time, time),
      ],
    };
    final look = GlassDatePickerStyle.resolve(context, widget.style);
    // The labels keep their measured sizes; a box narrower than they are
    // scales them down instead of overflowing.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < parts.length; i++) ...[
            if (i > 0) const SizedBox(width: _DatePickerLook.labelGap),
            _CompactLabel(
              key: _labels[parts[i].$1],
              text: parts[i].$2,
              height: parts[i].$1 == _Part.date
                  ? _DatePickerLook.dateLabelHeight
                  : _DatePickerLook.timeLabelHeight,
              open: _open == parts[i].$1,
              enabled: _enabled,
              look: look,
              semanticLabel: widget.semanticLabel,
              onOpen: (BuildContext anchor) => _show(parts[i].$1, anchor),
            ),
          ],
        ],
      ),
    );
  }
}

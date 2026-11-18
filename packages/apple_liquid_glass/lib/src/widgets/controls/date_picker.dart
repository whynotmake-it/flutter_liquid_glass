import 'dart:math' as math;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:apple_liquid_glass/raw.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/widgets.dart';
import 'package:liquid_glass_renderer/painting.dart';

part 'package:apple_liquid_glass/src/widgets/controls/date_picker_calendar.dart';
part 'package:apple_liquid_glass/src/widgets/controls/date_picker_style.dart';
part 'package:apple_liquid_glass/src/widgets/controls/date_picker_time_wheels.dart';
part 'package:apple_liquid_glass/src/widgets/controls/date_picker_wheels.dart';

// The opacity of the wheels' rows outside the band, drawn in the label
// color at the smaller size (21 points against the band's 23.5), before
// they darken toward the cylinder's edges. UIKit's labels report 0.447; 0.4
// matches the screen (the rows next to the band read 0.36 of black on an
// iPhone 16 Pro).
const double _wheelFadedOpacity = 0.4;

// The opacity of a day outside the picker's range (not measured on a
// device).
const double _unavailableDayOpacity = 0.35;

/// Whether a picker shows 24-hour time at [context]: [given], else the
/// platform's setting.
@internal
bool use24HourFormatAt(BuildContext context, bool? given) =>
    given ?? MediaQuery.maybeAlwaysUse24HourFormatOf(context) ?? false;

/// A part of a date picker that shows the keyboard focus and the pointer
/// over it in [highlights]: the ring inside its [shape], the hover's wash
/// over it.
@internal
Widget glassDatePickerHighlight(
  GlassHighlightLook highlights, {
  required ValueListenable<Set<WidgetState>> states,
  required Widget child,
  LiquidShape shape = LiquidRoundedSuperellipse.capsule,
}) => GlassHighlightPaint(
  look: highlights,
  states: states,
  shape: shape,
  inside: true,
  wash: true,
  child: child,
);

/// The iOS 27 calendar date picker: a month calendar in place.
///
/// UIKit: `UIDatePicker` with `.inline` and `.date`. SwiftUI: `DatePicker`
/// with `.graphical`. Flutter: `CalendarDatePicker`.
///
/// Its behaviour, keys and accessibility are [RawGlassDatePicker]'s: the
/// arrows turn the month with a slide, a tap on the month title turns the
/// day grid into month and year wheels (the title takes the accent color
/// at once and its chevron turns to point down over 0.25 s, as UIKit
/// does), and a tap on a day picks it. The picked day sits on a disc in
/// the label color, or in the accent when it is today, and today's number
/// takes the accent on a tinted disc; days outside [minimumDate] and
/// [maximumDate] fade. Texts come from [GlassLocalizations]. The calendar
/// follows the text scale up to [maxTextScale], except the day numbers,
/// which keep their size. It works with any renderer.
///
/// Focused from the keyboard, the title, an arrow or a day draws Flutter's
/// Cupertino focus ring inside it, and a mouse over one washes it as a
/// glass body's hover does (the rule of the glass controls; an
/// approximation, not measured). Each month grid is a layer of its own, so
/// a page turn moves recorded grids instead of painting every day again
/// (IDENTICAL).
class GlassDatePicker extends StatelessWidget {
  /// Creates a calendar with [value] picked.
  const GlassDatePicker({
    required this.value,
    required this.onChanged,
    this.minimumDate,
    this.maximumDate,
    this.firstDayOfWeek = DateTime.sunday,
    this.today,
    this.style,
    this.focusNode,
    this.autofocus = false,
    @internal this.defersDays = false,
    super.key,
  });

  /// The picked day; its time of day is kept when another day is picked.
  final DateTime value;

  /// Called with the day the user picks; null disables the picker.
  final ValueChanged<DateTime>? onChanged;

  /// The earliest moment that can be picked; null for no limit. Later
  /// than [maximumDate], both are ignored, as UIKit ignores them.
  final DateTime? minimumDate;

  /// The latest moment that can be picked; null for no limit.
  final DateTime? maximumDate;

  /// The first column of the calendar, as a [DateTime] weekday.
  final int firstDayOfWeek;

  /// The day to tint as today; null for the current day.
  final DateTime? today;

  /// The colors, over the theme's and the picker's defaults.
  final GlassDatePickerStyle? style;

  /// The focus node of the days, or null for the picker's own: focusing it
  /// focuses the picked day.
  final FocusNode? focusNode;

  /// Whether the days take focus when they first appear.
  final bool autofocus;

  /// Whether the days mount a frame after the rest.
  @internal
  final bool defersDays;

  /// The largest text scale the fixed-size calendar follows.
  static const double maxTextScale = 1.2;

  @override
  Widget build(BuildContext context) {
    final look = GlassDatePickerStyle.resolve(context, style);
    final text = GlassTextScale.of(context, max: maxTextScale);
    final days = GlassTextScale.fixed(context);
    final title = text.resolve(look.titleTextStyle!);
    final weekday = text.resolve(look.weekdayTextStyle!);
    final day = days.resolve(look.dayTextStyle!);
    final selectedDay = days.resolve(look.selectedDayTextStyle!);
    final highlights = look.highlightsAt(context);
    return text.apply(
      DefaultTextStyle(
        style: text.resolve(TextStyle(fontSize: 17, color: look.labelColor)),
        child: RawGlassDatePicker(
          value: value,
          onChanged: onChanged,
          minimumDate: minimumDate,
          maximumDate: maximumDate,
          firstDayOfWeek: firstDayOfWeek,
          today: today,
          focusNode: focusNode,
          autofocus: autofocus,
          defersDays: defersDays,
          dayBuilder: (context, details) => _day(
            details,
            look: look,
            highlights: highlights,
            scale: days,
            style: details.selected ? selectedDay : day,
          ),
          titleBuilder: (context, details) => glassDatePickerHighlight(
            highlights,
            states: details.states,
            child: _Title(details: details, look: look, style: title),
          ),
          arrowBuilder: (context, details) => glassDatePickerHighlight(
            highlights,
            states: details.states,
            shape: const LiquidOval(),
            child: _Arrow(details: details, look: look),
          ),
          weekdayBuilder: (context, label) =>
              Text(label, textAlign: TextAlign.center, style: weekday),
          monthYearBuilder: (context, details) =>
              _MonthYearWheels(details: details, look: look),
        ),
      ),
    );
  }
}

/// The iOS 27 time picker: the hour and minute wheels, with an AM/PM wheel
/// in 12-hour time.
///
/// UIKit: `UIDatePicker` with `.wheels` and `.time`. SwiftUI: `DatePicker`
/// with `.wheel` and `.hourAndMinute`. Flutter: `CupertinoTimerPicker` or
/// `CupertinoDatePicker` in time mode.
///
/// A wheel coming to a new row calls [onChanged] with [value]'s day at
/// the new time, bounded by [minimumDate] and [maximumDate]; a new [value]
/// turns the wheels to it. In 12-hour time the hour wheel turning past 11
/// and 12 switches AM and PM, as UIKit's does. A time between two multiples
/// of [minuteInterval] is shown, and reported, rounded down to the earlier
/// one. It is 232 by 204 points and works with any renderer.
///
/// ```dart
/// GlassTimePicker(
///   value: time,
///   minuteInterval: 5,
///   onChanged: (picked) => setState(() => time = picked),
/// )
/// ```
class GlassTimePicker extends StatefulWidget {
  /// Creates wheels showing [value]'s time.
  const GlassTimePicker({
    required this.value,
    required this.onChanged,
    this.minuteInterval = 1,
    this.use24HourFormat,
    this.minimumDate,
    this.maximumDate,
    this.style,
    super.key,
  }) : assert(
         minuteInterval >= 1 &&
             minuteInterval <= 30 &&
             60 % minuteInterval == 0,
         'minuteInterval must divide 60 and lie in 1 to 30.',
       );

  /// The time shown; its day is kept when a wheel turns.
  final DateTime value;

  /// Called with the new time when a wheel comes to a new row; null
  /// disables the wheels.
  final ValueChanged<DateTime>? onChanged;

  /// The step of the minute wheel in minutes, a divisor of 60 from 1 to 30
  /// (UIKit `minuteInterval`).
  final int minuteInterval;

  /// Whether times use 24 hours; null follows the platform's
  /// [MediaQueryData.alwaysUse24HourFormat] (the device's 24-Hour Time
  /// setting on iOS), as UIKit follows the locale's.
  final bool? use24HourFormat;

  /// The earliest moment that can be picked; null for no limit. The wheels
  /// honor its time on its day.
  final DateTime? minimumDate;

  /// The latest moment that can be picked; null for no limit. The wheels
  /// honor its time on its day.
  final DateTime? maximumDate;

  /// The look, over the theme's and the picker's defaults.
  final GlassDatePickerStyle? style;

  @override
  State<GlassTimePicker> createState() => _TimeWheelsState();
}

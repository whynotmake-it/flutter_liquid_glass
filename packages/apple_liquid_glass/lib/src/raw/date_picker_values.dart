import 'package:apple_liquid_glass/src/raw/date_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';

/// The moments a date picker offers: from [first] to [last], either open.
/// Bounds whose last lies before their first offer every moment, as
/// `UIDatePicker` ignores a maximum before its minimum.
@immutable
final class GlassDateBounds {
  /// The bounds from [minimum] to [maximum].
  factory GlassDateBounds(DateTime? minimum, DateTime? maximum) =>
      minimum != null && maximum != null && maximum.isBefore(minimum)
      ? const GlassDateBounds._(null, null)
      : GlassDateBounds._(minimum, maximum);

  const GlassDateBounds._(this.first, this.last);

  /// The first moment offered, or null for none before it.
  final DateTime? first;

  /// The last moment offered, or null for none after it.
  final DateTime? last;

  /// [value] moved to the nearest moment offered.
  DateTime clamp(DateTime value) {
    if (first case final first? when value.isBefore(first)) return first;
    if (last case final last? when value.isAfter(last)) return last;
    return value;
  }

  /// Whether any moment of [day] is offered.
  bool offersDay(DateTime day) {
    final date = dateOnly(day);
    return !(first != null && date.isBefore(dateOnly(first!))) &&
        !(last != null && date.isAfter(dateOnly(last!)));
  }

  /// [value] moved to the nearest day offered, at its own time of day.
  DateTime clampDay(DateTime value) {
    DateTime at(DateTime day) =>
        DateTime(day.year, day.month, day.day, value.hour, value.minute);
    final date = dateOnly(value);
    if (first case final first? when date.isBefore(dateOnly(first))) {
      return at(first);
    }
    if (last case final last? when date.isAfter(dateOnly(last))) {
      return at(last);
    }
    return value;
  }

  /// Whether any day of [month]'s month is offered.
  bool offersMonth(DateTime month) {
    DateTime monthOf(DateTime moment) => DateTime(moment.year, moment.month);
    final shown = monthOf(month);
    return !(first != null && shown.isBefore(monthOf(first!))) &&
        !(last != null && shown.isAfter(monthOf(last!)));
  }

  @override
  bool operator ==(Object other) =>
      other is GlassDateBounds && other.first == first && other.last == last;

  @override
  int get hashCode => Object.hash(first, last);
}

/// Midnight of [moment]'s day.
DateTime dateOnly(DateTime moment) =>
    DateTime(moment.year, moment.month, moment.day);

/// What a [GlassDatePickerDayBuilder] builds one day of the month from.
@immutable
final class GlassDatePickerDay {
  /// Describes a day.
  const GlassDatePickerDay({
    required this.date,
    required this.size,
    required this.selected,
    required this.today,
    required this.enabled,
    required this.states,
  });

  /// The day, at midnight.
  final DateTime date;

  /// The day's cell: as wide as a seventh of the grid, as tall as its
  /// week's row.
  final Size size;

  /// Whether the day is the picked one.
  final bool selected;

  /// Whether the day is today.
  final bool today;

  /// Whether the day lies between the picker's first and last dates and
  /// the picker is enabled.
  final bool enabled;

  /// The day's states as they change: pressed, hovered and focused (only
  /// while focus should show), selected and disabled.
  final ValueListenable<Set<WidgetState>> states;
}

/// Builds one day of a [RawGlassDatePicker]; it runs when the picker builds
/// a month, never on a frame of its motion.
typedef GlassDatePickerDayBuilder = Widget Function(
  BuildContext context,
  GlassDatePickerDay day,
);

/// What a [GlassDatePickerTitleBuilder] builds the month title from.
@immutable
final class GlassDatePickerTitle {
  /// Describes the title.
  const GlassDatePickerTitle({
    required this.text,
    required this.showsYearPicker,
    required this.chevronAngle,
    required this.states,
  });

  /// The shown month and its year, such as "October 2026".
  final String text;

  /// Whether the picker shows, or turns to, its month and year wheels.
  final bool showsYearPicker;

  /// The angle in radians the title's chevron turns by from pointing
  /// toward the trailing side: a quarter turn, toward pointing down, as
  /// the wheels show, mirrored in right-to-left.
  final MotionSelection<double> chevronAngle;

  /// The title's states as they change: pressed, hovered, focused and
  /// disabled.
  final ValueListenable<Set<WidgetState>> states;
}

/// Builds the month title of a [RawGlassDatePicker], a button that shows
/// and hides the month and year wheels.
typedef GlassDatePickerTitleBuilder = Widget Function(
  BuildContext context,
  GlassDatePickerTitle title,
);

/// What a [GlassDatePickerArrowBuilder] builds a month arrow from.
@immutable
final class GlassDatePickerArrow {
  /// Describes an arrow.
  const GlassDatePickerArrow({
    required this.next,
    required this.pointsRight,
    required this.enabled,
    required this.states,
  });

  /// Whether the arrow turns to the next month, or else the previous one.
  final bool next;

  /// Whether the arrow points to the right: the next month's arrow in a
  /// left-to-right context, the previous month's in a right-to-left one.
  final bool pointsRight;

  /// Whether the month it turns to may be shown.
  final bool enabled;

  /// The arrow's states as they change: pressed, hovered, focused and
  /// disabled.
  final ValueListenable<Set<WidgetState>> states;
}

/// Builds a month arrow of a [RawGlassDatePicker].
typedef GlassDatePickerArrowBuilder = Widget Function(
  BuildContext context,
  GlassDatePickerArrow arrow,
);

/// What a [GlassDatePickerMonthYearBuilder] builds the month and year
/// wheels from.
@immutable
final class GlassDatePickerMonthYear {
  /// Describes the wheels.
  const GlassDatePickerMonthYear({
    required this.month,
    required this.firstDate,
    required this.lastDate,
    required this.onChanged,
  });

  /// The shown month, its first day at midnight.
  final DateTime month;

  /// The earliest day that may be picked, or null for no limit.
  final DateTime? firstDate;

  /// The latest day that may be picked, or null for no limit.
  final DateTime? lastDate;

  /// Called with the month and year a wheel comes to rest on: the picker
  /// shows that month and moves the picked day there.
  final void Function(int year, int month) onChanged;
}

/// Builds the month and year wheels a [RawGlassDatePicker] shows in place
/// of its day grid while its title is turned.
typedef GlassDatePickerMonthYearBuilder = Widget Function(
  BuildContext context,
  GlassDatePickerMonthYear details,
);

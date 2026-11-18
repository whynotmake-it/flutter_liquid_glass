import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// The words the package's widgets say to assistive technology, such as the
/// label of a sheet's grabber or of the dimming behind a popover.
///
/// UIKit: the system's own localized accessibility strings. Flutter:
/// `CupertinoLocalizations`, `WidgetsLocalizations`.
///
/// Found with [GlassLocalizations.of] through Flutter's [Localizations]. An
/// app that registers no delegate gets the English
/// [DefaultGlassLocalizations]; an app that translates registers its own
/// `LocalizationsDelegate<GlassLocalizations>` in its
/// `localizationsDelegates`, usually a subclass of
/// [DefaultGlassLocalizations] that overrides what it translates.
abstract class GlassLocalizations {
  /// Creates the strings; for a subclass.
  const GlassLocalizations();

  /// The strings of the closest [Localizations] that loaded a
  /// [GlassLocalizations], or the English [DefaultGlassLocalizations] when
  /// none did.
  static GlassLocalizations of(BuildContext context) =>
      Localizations.of<GlassLocalizations>(context, GlassLocalizations) ??
      const DefaultGlassLocalizations();

  /// The name of an alert whose title and message are not plain text, as
  /// `CupertinoLocalizations.alertDialogLabel` names one.
  String get alertLabel;

  /// The label of the dimming behind an action sheet, whose tap dismisses
  /// it.
  String get actionSheetDismissLabel;

  /// The label of the dimming behind a sheet, whose tap dismisses it.
  String get sheetDismissLabel;

  /// The label of the dimming behind a popover, whose tap dismisses it.
  String get popoverDismissLabel;

  /// The label of what lies around a menu, whose tap dismisses it, as
  /// `CupertinoLocalizations.menuDismissLabel`.
  String get menuDismissLabel;

  /// The name of a menu whose source gives it none, as
  /// `MaterialLocalizations.popupMenuLabel` names one.
  String get menuLabel;

  /// The label of a sheet's grabber, which steps the sheet between its
  /// detents.
  String get sheetGrabberLabel;

  /// The value a sheet's grabber reads at the large detent, the full
  /// height.
  String get sheetLargeDetentValue;

  /// The value a sheet's grabber reads at the medium detent, half the
  /// height.
  String get sheetMediumDetentValue;

  /// The value a sheet's grabber reads at a detent of its own height: the
  /// [position]th smallest of [count], counting from 1.
  String sheetDetentValue(int position, int count);

  /// The label of the button that goes back a page.
  String get backButtonLabel;

  /// The label of a button that closes what it sits in.
  String get closeButtonLabel;

  /// The label of a search field and of the button that opens one.
  String get searchLabel;

  /// The title of the row a menu shows while a deferred group loads.
  String get loadingLabel;

  /// The label of the button that clears a text field.
  String get clearTextLabel;

  /// The label of a row's button that shows more about it.
  String get moreInfoLabel;

  /// The value of a page control: [page] of [count], counting from 1.
  String pageValue(int page, int count);

  /// The label of the half of a stepper that raises its value.
  String get incrementLabel;

  /// The label of the half of a stepper that lowers its value.
  String get decrementLabel;

  /// The value of a slider at [fraction] of its range, 0 to 1.
  String percentValue(double fraction);

  /// The name of [month], 1 for January to 12 for December.
  String monthName(int month);

  /// The initial a calendar heads the column of [weekday] with, as a
  /// [DateTime] weekday: 1 for Monday to 7 for Sunday.
  String weekdayAbbreviation(int weekday);

  /// The title of a calendar showing the month of [month] and its year.
  String monthYear(DateTime month);

  /// What a calendar's day [date] reads: its number first, then the full
  /// date, then that it is [today], as `CalendarDatePicker` reads a day.
  String dayLabel(DateTime date, {required bool today});

  /// The date a compact date picker's label shows, such as "Oct 3, 2026".
  String compactDate(DateTime date);

  /// The time of day a compact date picker's label shows, in 24 hours or
  /// in 12 with the half of the day.
  String compactTime(DateTime time, {required bool use24HourFormat});

  /// What a compact date picker's label reads: the app's [label] for the
  /// picker, then the [value] it shows.
  String compactDatePickerLabel(String label, String value);

  /// The label of a calendar's button that shows the previous month.
  String get previousMonthLabel;

  /// The label of a calendar's button that shows the next month.
  String get nextMonthLabel;

  /// The label of a calendar's month title while it shows the days: a tap
  /// shows the month and year wheels.
  String get showYearPickerLabel;

  /// The label of a calendar's month title while it shows the month and
  /// year wheels: a tap shows the days again.
  String get hideYearPickerLabel;

  /// The label of the wheel of months.
  String get monthLabel;

  /// The label of the wheel of years.
  String get yearLabel;

  /// The label of the wheel of hours.
  String get hourLabel;

  /// The label of the wheel of minutes.
  String get minuteLabel;

  /// The label of the wheel of the half of the day.
  String get dayPeriodLabel;

  /// The first half of the day on a wheel of 12 hours.
  String get anteMeridiemAbbreviation;

  /// The second half of the day on a wheel of 12 hours.
  String get postMeridiemAbbreviation;

  /// What a compact date picker's label says it does when activated.
  String get compactDatePickerHint;

  /// The label of what lies around a compact date picker's calendar or
  /// wheels, whose tap dismisses them.
  String get datePickerDismissLabel;
}

/// The English [GlassLocalizations], used where an app loaded none.
class DefaultGlassLocalizations extends GlassLocalizations {
  /// Creates the English strings.
  const DefaultGlassLocalizations();

  /// A delegate that loads the English strings for every locale, for an
  /// app that lists its delegates and wants the package's English ones.
  static const LocalizationsDelegate<GlassLocalizations> delegate =
      _DefaultGlassLocalizationsDelegate();

  @override
  String get alertLabel => 'Alert';

  @override
  String get actionSheetDismissLabel => 'Dismiss action sheet';

  @override
  String get sheetDismissLabel => 'Dismiss sheet';

  @override
  String get popoverDismissLabel => 'Dismiss popover';

  @override
  String get menuDismissLabel => 'Dismiss menu';

  @override
  String get menuLabel => 'Menu';

  @override
  String get sheetGrabberLabel => 'Sheet grabber';

  @override
  String get sheetLargeDetentValue => 'Large';

  @override
  String get sheetMediumDetentValue => 'Medium';

  @override
  String sheetDetentValue(int position, int count) =>
      'Detent $position of $count';

  @override
  String get backButtonLabel => 'Back';

  @override
  String get closeButtonLabel => 'Close';

  @override
  String get searchLabel => 'Search';

  @override
  String get loadingLabel => 'Loading...';

  @override
  String get clearTextLabel => 'Clear text';

  @override
  String get moreInfoLabel => 'More info';

  @override
  String pageValue(int page, int count) => 'page $page of $count';

  @override
  String get incrementLabel => 'Increment';

  @override
  String get decrementLabel => 'Decrement';

  @override
  String percentValue(double fraction) => '${(fraction * 100).round()}%';

  static const List<String> _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static const List<String> _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  String monthName(int month) => _months[month - 1];

  @override
  String weekdayAbbreviation(int weekday) =>
      _weekdays[weekday - 1].substring(0, 3).toUpperCase();

  @override
  String monthYear(DateTime month) => '${monthName(month.month)} ${month.year}';

  @override
  String dayLabel(DateTime date, {required bool today}) =>
      '${date.day}, ${_weekdays[date.weekday - 1]}, '
      '${monthName(date.month)} ${date.day}, ${date.year}'
      '${today ? ', Today' : ''}';

  @override
  String compactDate(DateTime date) =>
      '${monthName(date.month).substring(0, 3)} ${date.day}, ${date.year}';

  @override
  String compactTime(DateTime time, {required bool use24HourFormat}) {
    String two(int v) => v.toString().padLeft(2, '0');
    if (use24HourFormat) return '${two(time.hour)}:${two(time.minute)}';
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final period = time.hour < 12
        ? anteMeridiemAbbreviation
        : postMeridiemAbbreviation;
    return '$hour:${two(time.minute)} $period';
  }

  @override
  String compactDatePickerLabel(String label, String value) => '$label, $value';

  @override
  String get previousMonthLabel => 'Previous month';

  @override
  String get nextMonthLabel => 'Next month';

  @override
  String get showYearPickerLabel => 'Show year picker';

  @override
  String get hideYearPickerLabel => 'Hide year picker';

  @override
  String get monthLabel => 'Month';

  @override
  String get yearLabel => 'Year';

  @override
  String get hourLabel => 'Hour';

  @override
  String get minuteLabel => 'Minute';

  @override
  String get dayPeriodLabel => 'AM/PM';

  @override
  String get anteMeridiemAbbreviation => 'AM';

  @override
  String get postMeridiemAbbreviation => 'PM';

  @override
  String get compactDatePickerHint => 'Shows the picker';

  @override
  String get datePickerDismissLabel => 'Dismiss picker';
}

class _DefaultGlassLocalizationsDelegate
    extends LocalizationsDelegate<GlassLocalizations> {
  const _DefaultGlassLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<GlassLocalizations> load(Locale locale) =>
      SynchronousFuture<GlassLocalizations>(const DefaultGlassLocalizations());

  @override
  bool shouldReload(_DefaultGlassLocalizationsDelegate old) => false;
}

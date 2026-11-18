part of 'date_picker.dart';

extension on RawGlassDatePicker {
  GlassDateBounds get _bounds => GlassDateBounds(minimumDate, maximumDate);
}

int _daysIn(DateTime month) => DateTime(month.year, month.month + 1, 0).day;

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// The layout of the calendar, read from UIKit's views at 320 points wide.
abstract final class _Metrics {
  static const double top = 16;
  static const double headerHeight = 37.67;
  static const double titleInset = 20.33;
  static const double titleButtonStart = 16;
  static const double titleButtonEnd = 4;
  static const double weekdayTop = 16;
  static const double weekdayHeight = 15.67;
  static const double gridInset = 10.33;
  static const double cell = 42.67;
  static const double row = 45.67;
  static const double gridTop = 1;
  static const double chevronButton = 43.33;
  static const double chevronEnd = 2;
  static const double grid = 7 * cell;

  /// How far a day's 44-point target reaches past its cell on each side.
  static const double reach = (44 - cell) / 2;

  /// Where the month and year wheels sit in the calendar
  /// (`_UICalendarMonthYearSelector`, iPhone 16 Pro, fixture
  /// ios27-device/date_picker/month-year.json): 288 x 216 at 16 x 76.84.
  static const double wheelsStart = 16;
  static const double wheelsTop = 76.84;
  static const double wheelsWidth = 288;
  static const double wheelsHeight = 216;
}

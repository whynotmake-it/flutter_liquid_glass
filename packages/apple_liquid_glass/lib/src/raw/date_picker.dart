import 'dart:math' as math;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:apple_liquid_glass/src/raw/date_picker_header.dart';
import 'package:apple_liquid_glass/src/raw/date_picker_values.dart';
import 'package:apple_liquid_glass/src/raw/still.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/widgets.dart';

part 'package:apple_liquid_glass/src/raw/date_picker_support.dart';
part 'package:apple_liquid_glass/src/raw/date_picker_views.dart';

/// A month calendar with the measured motion and layout of iOS 27's
/// inline `UIDatePicker` and no look of its own: its builders decide how
/// each part looks.
///
/// UIKit: `UIDatePicker` with `.inline` (its calendar). SwiftUI:
/// `DatePicker` with `.graphical`. Flutter: `CalendarDatePicker`.
///
/// It lays out UIKit's calendar, 320 by 332 points: the month title with
/// its chevron, the two month arrows, the weekday initials and the days of
/// the shown month in weeks starting at [firstDayOfWeek]; a month of six
/// weeks packs its rows into the five rows' height. An arrow turns the
/// month with a slide (0.3 s on a sine ease); a tap on the
/// title fades the grid out and [monthYearBuilder]'s wheels in, and a
/// wheel at rest moves the picked day to its month and year, keeping its
/// day of the month where the month has it (the 31st turned to November is
/// the 30th). A tap on a day picks it; the time of [value] is kept.
///
/// Keys and accessibility follow Flutter's `CalendarDatePicker`. The title
/// and each arrow are buttons and Tab stops of their own, with targets of
/// 44 points; Space and Enter press them. The days are one Tab stop,
/// entered at the picked day ([focusNode] stands for them): an arrow key
/// moves the focus a day back or forward, or a week up or down, mirrored
/// in a right-to-left context, and turns the month when it leaves it;
/// Space and Enter pick the focused day. Screen readers read each day as
/// its number and its full date, "Today" after today's, as a button, with
/// the picked day selected and the days outside [minimumDate] and
/// [maximumDate] disabled. A frame of motion rebuilds no builder.
class RawGlassDatePicker extends StatefulWidget {
  /// Creates a calendar showing [value]'s month with [value] picked.
  const RawGlassDatePicker({
    required this.value,
    required this.onChanged,
    required this.dayBuilder,
    required this.titleBuilder,
    required this.arrowBuilder,
    required this.weekdayBuilder,
    required this.monthYearBuilder,
    this.minimumDate,
    this.maximumDate,
    this.firstDayOfWeek = DateTime.sunday,
    this.today,
    this.statesController,
    this.focusNode,
    this.autofocus = false,
    @internal this.defersDays = false,
    super.key,
  });

  /// The picked day; its time of day is kept when another day is picked.
  final DateTime value;

  /// Called with the day the user picks, at [value]'s time of day; null
  /// disables the picker.
  final ValueChanged<DateTime>? onChanged;

  /// Builds each day.
  final GlassDatePickerDayBuilder dayBuilder;

  /// Builds the month title.
  final GlassDatePickerTitleBuilder titleBuilder;

  /// Builds each month arrow.
  final GlassDatePickerArrowBuilder arrowBuilder;

  /// Builds the initial of a weekday, given its text.
  final Widget Function(BuildContext context, String label) weekdayBuilder;

  /// Builds the month and year wheels.
  final GlassDatePickerMonthYearBuilder monthYearBuilder;

  /// The earliest moment that can be picked; null for no limit. Later
  /// than [maximumDate], both are ignored, as UIKit ignores them.
  final DateTime? minimumDate;

  /// The latest moment that can be picked; null for no limit.
  final DateTime? maximumDate;

  /// The first column of the calendar, as a [DateTime] weekday.
  final int firstDayOfWeek;

  /// The day to show as today; null for the current day.
  final DateTime? today;

  /// Where the picker publishes the states of the picker as a whole, or
  /// null for its own: [WidgetState.disabled] while [onChanged] is null.
  /// The picker is its only writer: what else writes to it is written
  /// over.
  final WidgetStatesController? statesController;

  /// The focus node of the days, or null for the picker's own: focusing
  /// it focuses the picked day.
  final FocusNode? focusNode;

  /// Whether the days take focus when they first appear.
  final bool autofocus;

  /// Whether the days mount a frame after the rest, as an overlay that
  /// opens with them spreads its layout over two frames.
  @internal
  final bool defersDays;

  @override
  State<RawGlassDatePicker> createState() => _RawGlassDatePickerState();
}

class _RawGlassDatePickerState extends State<RawGlassDatePicker>
    with ControlStates<RawGlassDatePicker> {
  final DatePickerCalendarMotion _motion = DatePickerCalendarMotion();
  final InputZonesController<DateTime> _zones =
      InputZonesController<DateTime>();
  final _HeaderStates _header = _HeaderStates();
  final Map<DateTime, List<Interaction>> _presses = {};
  late final List<Interaction> _titlePress = [
    PressInteraction(role: InteractionRole.content, onTap: _toggleYearPicker),
  ];
  late final List<Interaction> _previousPress = [
    PressInteraction(
      role: InteractionRole.content,
      onTap: (t) => _motion.turnPage(t, -1),
    ),
  ];
  late final List<Interaction> _nextPress = [
    PressInteraction(
      role: InteractionRole.content,
      onTap: (t) => _motion.turnPage(t, 1),
    ),
  ];
  late final MotionSelection<bool> _pageTurning = _motion.select(
    (m) => m.page < 1,
  );
  late final MotionSelection<bool> _yearsVisible = _motion.select(
    (m) => m.yearPicker.clamp(0.0, 1.0) > 0,
  );
  late final MotionSelection<double> _gridOpacity = _motion.select(
    (m) => 1 - m.yearPicker.clamp(0.0, 1.0),
  );
  late final MotionSelection<double> _wheelsOpacity = _motion.select(
    (m) => m.yearPicker.clamp(0.0, 1.0),
  );
  late MotionSelection<double> _chevronAngle = _angle(rtl: false);
  bool _rtl = false;
  bool _showsYears = false;
  late DateTime _month = DateTime(_shown.year, _shown.month);
  DateTime? _previousMonth;
  DateTime? _focusAfterTurn;
  late bool _daysReady = !widget.defersDays;
  VoidCallback? _cancelDays;
  VoidCallback? _cancelFocus;

  DateTime get _shown => _bounded(widget.value);

  @override
  WidgetStatesController? get givenStates => widget.statesController;

  @override
  bool get enabled => widget.onChanged != null;

  @override
  void initState() {
    super.initState();
    _motion.onTurn = _turned;
    if (!_daysReady) {
      _cancelDays = _motion.clock.schedulePublish(() {
        _cancelDays = null;
        // The deferred days mount once, a frame after the rest.
        if (mounted) setState(() => _daysReady = true);
      });
    }
  }

  @override
  void didUpdateWidget(RawGlassDatePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    final value = _shown;
    if (!_sameDay(_bounded(oldWidget.value), value) &&
        !(value.year == _month.year && value.month == _month.month)) {
      _month = DateTime(value.year, value.month);
      _previousMonth = null;
    }
  }

  @override
  void dispose() {
    _cancelDays?.call();
    _cancelFocus?.call();
    _motion.onTurn = null;
    _zones.dispose();
    _header.dispose();
    super.dispose();
  }

  MotionSelection<double> _angle({required bool rtl}) => _motion.select(
    (m) => (rtl ? -1 : 1) * m.yearPickerTurn * math.pi / 2,
  );

  DateTime _bounded(DateTime value) => widget._bounds.clamp(value);

  bool _canTurn(int direction) => widget._bounds.offersMonth(
    DateTime(_month.year, _month.month + direction),
  );

  bool _turned(int direction) {
    if (!mounted || !_canTurn(direction)) return false;
    // Once per turn, as it starts: the new month's days are built.
    setState(() {
      _previousMonth = _month;
      _month = DateTime(_month.year, _month.month + direction);
    });
    return true;
  }

  void _toggleYearPicker(double t) {
    // The title's label, its chevron's state and which half takes input
    // and semantics follow the tap at once.
    setState(() => _showsYears = !_showsYears);
    _motion.showYearPicker(t, show: _showsYears);
  }

  void _pick(DateTime day) {
    final onChanged = widget.onChanged;
    if (onChanged == null || !widget._bounds.offersDay(day)) return;
    final v = widget.value;
    onChanged(DateTime(day.year, day.month, day.day, v.hour, v.minute));
  }

  void _pickMonth(int year, int month) {
    final v = _shown;
    var next = DateTime(
      year,
      month,
      math.min(v.day, _daysIn(DateTime(year, month))),
      v.hour,
      v.minute,
    );
    next = widget._bounds.clampDay(next);
    // A wheel at rest shows its month without a turn.
    setState(() {
      _previousMonth = null;
      _month = DateTime(next.year, next.month);
    });
    if (next != v) widget.onChanged?.call(next);
  }

  // An arrow key that finds no day in its direction on screen moves a day
  // or a week from the focused one, as Flutter's CalendarDatePicker does,
  // and turns the month when that day lies in another.
  bool _edge(DateTime from, TraversalDirection direction) {
    final step = switch (direction) {
      TraversalDirection.up => -DateTime.daysPerWeek,
      TraversalDirection.down => DateTime.daysPerWeek,
      TraversalDirection.left => _rtl ? 1 : -1,
      TraversalDirection.right => _rtl ? -1 : 1,
    };
    final next = DateTime(from.year, from.month, from.day + step);
    if (!widget._bounds.offersDay(next)) return true;
    if (next.year == _month.year && next.month == _month.month) {
      _zones.requestFocus(next);
      return true;
    }
    final turn = next.isBefore(_month) ? -1 : 1;
    if (!_canTurn(turn)) return true;
    _focusAfterTurn = next;
    _motion.turnPage(_motion.clock.now, turn);
    return true;
  }

  void _focusPicked(bool focused) {
    if (!focused || !(widget.focusNode?.hasPrimaryFocus ?? false)) return;
    _zones.requestFocus(_entry());
  }

  // The day Tab enters the grid at: the picked day when it is shown, else
  // today, else the first day of the month.
  DateTime _entry() {
    final value = dateOnly(_shown);
    if (value.year == _month.year && value.month == _month.month) {
      return value;
    }
    final today = _today;
    if (today.year == _month.year && today.month == _month.month) {
      return today;
    }
    return _month;
  }

  DateTime get _today => dateOnly(widget.today ?? DateTime.now());

  List<Interaction> _pressOf(DateTime day) => _presses.putIfAbsent(
    day,
    () => [
      PressInteraction(
        role: InteractionRole.content,
        onTap: (_) => _pick(day),
      ),
    ],
  );

  void _forgetOtherMonths() => _presses.removeWhere(
    (day, _) => day.year != _month.year || day.month != _month.month,
  );

  int _leadOf(DateTime month) =>
      (DateTime(month.year, month.month).weekday - widget.firstDayOfWeek) % 7;

  int _weeksOf(DateTime month) =>
      ((_leadOf(month) + _daysIn(month)) / 7).ceil();

  double _rowOf(DateTime month) => _weeksOf(month) > 5
      ? DatePickerCalendarMotion.sixWeekRowHeight
      : _Metrics.row;

  InputZoneFrame? _dayFrame(DateTime day) {
    if (day.year != _month.year || day.month != _month.month) return null;
    final index = _leadOf(day) + day.day - 1;
    final column = index % 7;
    final row = _rowOf(day);
    final left = _rtl
        ? _Metrics.grid - (column + 1) * _Metrics.cell
        : column * _Metrics.cell;
    return InputZoneFrame(
      Rect.fromLTWH(left, (index ~/ 7) * row, _Metrics.cell, row),
    );
  }

  Widget _monthGrid(
    BuildContext context,
    DateTime month, {
    required bool live,
  }) {
    final lead = _leadOf(month);
    final days = _daysIn(month);
    final weeks = _weeksOf(month);
    final row = _rowOf(month);
    final value = _shown;
    final today = _today;
    DateTime at(int day) => DateTime(month.year, month.month, day);
    // Its own layer: a page turn moves the recorded grid instead of
    // painting every day again on each frame.
    return RepaintBoundary(
      child: Column(
        children: [
          for (var w = 0; w < weeks; w++)
            SizedBox(
              height: row,
              child: Row(
                children: [
                  for (var d = 0; d < 7; d++)
                    if (w * 7 + d - lead + 1 case final day
                        when day >= 1 && day <= days)
                      widget.dayBuilder(
                        context,
                        GlassDatePickerDay(
                          date: at(day),
                          size: Size(_Metrics.cell, row),
                          selected: _sameDay(at(day), value),
                          today: _sameDay(at(day), today),
                          enabled: enabled && widget._bounds.offersDay(at(day)),
                          states: live ? _zones.states(at(day)) : still,
                        ),
                      )
                    else
                      const SizedBox(width: _Metrics.cell),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _days(BuildContext context, DateTime month) {
    _forgetOtherMonths();
    final value = dateOnly(_shown);
    final today = _today;
    final focus = _focusAfterTurn;
    if (focus != null &&
        focus.year == month.year &&
        focus.month == month.month) {
      _focusAfterTurn = null;
      // The focus scope hands the focus back to its last holder when the
      // old month's days leave, so autofocus on the new day would not
      // apply; the new day takes it once its zone is mounted.
      _cancelFocus?.call();
      _cancelFocus = _motion.clock.schedulePublish(() {
        _cancelFocus = null;
        if (mounted) _zones.requestFocus(focus);
      });
    }
    final days = [
      for (var d = 1; d <= _daysIn(month); d++)
        DateTime(month.year, month.month, d),
    ];
    final loc = GlassLocalizations.of(context);
    Widget grid = InputZones<DateTime>(
      zones: [
        for (final day in days)
          InputZone<DateTime>(
            id: day,
            interactions: _pressOf(day),
            enabled: enabled && widget._bounds.offersDay(day),
            states: {if (_sameDay(day, value)) WidgetState.selected},
            reach: glassTargetReach,
            semantics: SemanticsProperties(
              label: loc.dayLabel(day, today: _sameDay(day, today)),
              button: true,
              selected: _sameDay(day, value),
            ),
          ),
      ],
      frameOf: _dayFrame,
      frames: still,
      controller: _zones,
      axis: null,
      stops: InputZoneStops.one,
      current: _entry(),
      onEdge: _edge,
      child: _monthGrid(context, month, live: true),
    );
    if (widget.focusNode case final node?) {
      grid = Focus(
        focusNode: node,
        skipTraversal: true,
        includeSemantics: false,
        onFocusChange: _focusPicked,
        child: grid,
      );
    }
    return grid;
  }

  Widget _faded(MotionSelection<double> opacity, Widget child) =>
      MotionTransition(opacity: opacity, child: child);

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    if (rtl != _rtl) {
      _rtl = rtl;
      _chevronAngle = _angle(rtl: rtl);
    }
    final loc = GlassLocalizations.of(context);
    final years = _showsYears;
    final month = _month;
    final titleText = loc.monthYear(month);
    final canPrevious = enabled && _canTurn(-1);
    final canNext = enabled && _canTurn(1);
    Widget arrow({required bool next}) {
      final enabled = next ? canNext : canPrevious;
      final states = next ? _header.next : _header.previous;
      return DatePickerHeaderPart(
        states: states,
        interactions: next ? _nextPress : _previousPress,
        enabled: enabled,
        label: next ? loc.nextMonthLabel : loc.previousMonthLabel,
        child: SizedBox(
          width: _Metrics.chevronButton,
          height: _Metrics.headerHeight,
          child: widget.arrowBuilder(
            context,
            GlassDatePickerArrow(
              next: next,
              pointsRight: next != rtl,
              enabled: enabled,
              states: states,
            ),
          ),
        ),
      );
    }

    final previous = _previousMonth;
    final previousGrid = previous == null
        ? null
        : ExcludeSemantics(
            child: IgnorePointer(
              child: _monthGrid(context, previous, live: false),
            ),
          );
    final monthGrid = _days(context, month);
    final calendar = Padding(
      padding: const EdgeInsets.only(top: _Metrics.top),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: _Metrics.headerHeight,
            child: Row(
              children: [
                const SizedBox(width: _Metrics.titleButtonStart),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: DatePickerHeaderPart(
                          states: _header.title,
                          interactions: _titlePress,
                          enabled: enabled,
                          label: years
                              ? loc.hideYearPickerLabel
                              : loc.showYearPickerLabel,
                          value: titleText,
                          liveRegion: true,
                          child: Padding(
                            padding: const EdgeInsetsDirectional.only(
                              start:
                                  _Metrics.titleInset -
                                  _Metrics.titleButtonStart,
                              end: _Metrics.titleButtonEnd,
                            ),
                            child: SizedBox(
                              height: _Metrics.headerHeight,
                              child: widget.titleBuilder(
                                context,
                                GlassDatePickerTitle(
                                  text: titleText,
                                  showsYearPicker: years,
                                  chevronAngle: _chevronAngle,
                                  states: _header.title,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _faded(
                  _gridOpacity,
                  IgnorePointer(
                    ignoring: years,
                    child: ExcludeSemantics(
                      excluding: years,
                      child: ExcludeFocus(
                        excluding: years,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [arrow(next: false), arrow(next: true)],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: _Metrics.chevronEnd),
              ],
            ),
          ),
          Expanded(
            child: _faded(
              _gridOpacity,
              IgnorePointer(
                ignoring: years,
                child: ExcludeSemantics(
                  excluding: years,
                  child: ExcludeFocus(
                    excluding: years,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: _Metrics.weekdayTop),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: _Metrics.gridInset,
                          ),
                          child: SizedBox(
                            height: _Metrics.weekdayHeight,
                            child: ExcludeSemantics(
                              child: Row(
                                children: [
                                  for (var i = 0; i < 7; i++)
                                    SizedBox(
                                      width: _Metrics.cell,
                                      child: widget.weekdayBuilder(
                                        context,
                                        loc.weekdayAbbreviation(
                                          (widget.firstDayOfWeek + i - 1) % 7 +
                                              1,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                              _Metrics.gridInset - _Metrics.reach,
                              _Metrics.gridTop,
                              _Metrics.gridInset - _Metrics.reach,
                              0,
                            ),
                            child: _PageClip(
                              inset: _Metrics.reach,
                              // A page turn repaints the moving grids'
                              // offsets only, not the weekday row above;
                              // mounting or swapping a grid lays out only
                              // this area.
                              child: _ScopedRepaintBoundary(
                                builder: (context, _) => ListenableBuilder(
                                  listenable: _pageTurning,
                                  builder: (context, _) => _daysReady
                                      ? _turning(
                                          rtl: rtl,
                                          previous: previous,
                                          previousGrid: previousGrid,
                                          month: month,
                                          monthGrid: monthGrid,
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    final wheels = widget.monthYearBuilder(
      context,
      GlassDatePickerMonthYear(
        month: month,
        firstDate: widget._bounds.first,
        lastDate: widget._bounds.last,
        onChanged: _pickMonth,
      ),
    );
    return MotionScope(
      motion: _motion,
      child: SizedBox.fromSize(
        size: DatePickerCalendarMotion.calendarSize,
        child: Stack(
          children: [
            Positioned.fill(child: calendar),
            PositionedDirectional(
              start: _Metrics.wheelsStart,
              top: _Metrics.wheelsTop,
              width: _Metrics.wheelsWidth,
              height: _Metrics.wheelsHeight,
              child: ListenableBuilder(
                listenable: _yearsVisible,
                builder: (context, child) {
                  if (!years && !_yearsVisible.value) {
                    return const SizedBox.shrink();
                  }
                  return IgnorePointer(
                    ignoring: !years,
                    child: ExcludeSemantics(
                      excluding: !years,
                      child: _faded(_wheelsOpacity, child!),
                    ),
                  );
                },
                child: wheels,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _turning({
    required bool rtl,
    required DateTime? previous,
    required Widget? previousGrid,
    required DateTime month,
    required Widget monthGrid,
  }) {
    final turning = _pageTurning.value;
    double dir(DatePickerCalendarMotion m) =>
        m.pageDirection * (rtl ? -1.0 : 1.0);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (previousGrid != null && previous != null && turning)
          Positioned(
            key: ValueKey<DateTime>(previous),
            left: _Metrics.reach,
            top: 0,
            width: _Metrics.grid,
            child: MotionTransition(
              offset: _motion.select(
                (m) => Offset(-dir(m) * _Metrics.grid * m.page, 0),
              ),
              child: previousGrid,
            ),
          ),
        Positioned(
          key: ValueKey<DateTime>(month),
          left: 0,
          top: 0,
          width: _Metrics.grid + 2 * _Metrics.reach,
          child: MotionTransition(
            offset: _motion.select((m) {
              final q = m.page;
              return Offset(
                previousGrid != null && q < 1
                    ? dir(m) * _Metrics.grid * (1 - q)
                    : 0,
                0,
              );
            }),
            // The outer days' targets reach past the grid.
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: _Metrics.reach),
              child: monthGrid,
            ),
          ),
        ),
      ],
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:kinesis/motion.dart';
import 'package:meta/meta.dart';

/// The measured tuning and geometry of the iOS 27 compact date picker
/// (UIDatePicker with the compact style) and the overlay it opens.
@internal
abstract final class DatePickerTuning {
  /// The spring the overlay opens on, fitted to the simulator's frames of
  /// `_UIDatePickerOverlayPlatterView` (0.27 percent rms of the travel; no
  /// tuning value was found to read).
  static const openSpring = Spring.response(0.32, dampingRatio: 0.8);

  /// The spring the overlay closes on, fitted the same way (0.18 percent
  /// rms).
  static const closeSpring = Spring.response(0.348, dampingRatio: 0.86);

  /// The spring an open overlay changes picker on when the other label
  /// of a date-and-time picker is tapped: the platter's frame moves from
  /// the calendar's placement to the wheels' (or back) while the two
  /// contents cross-fade, both pinned to the anchored corner. Fitted to
  /// the platter's frames on an iPhone 16 Pro (critically damped, response
  /// 0.25 s: 0.04 percent rms of the travel; a screen recording of the same
  /// switch reads 0.245), starting [switchDelay] after the lift of the tap.
  /// The outgoing content's opacity is one minus the progress, the
  /// incoming one's the progress.
  static const switchSpring = Spring.response(0.25);

  /// The time from the lift of the tap that opens the overlay to the
  /// start of its spring (an iPhone 16 Pro: 0.143 and 0.125 s from the
  /// platter's frames; the simulator 0.14 - 0.15 s).
  static const double openDelay = 0.14;

  /// The time from the lift of the tap outside to the start of the
  /// closing spring (an iPhone 16 Pro: 0.052 and 0.062 s).
  static const double closeDelay = 0.055;

  /// The time from the lift of the tap outside to the start of the
  /// closing spring while the overlay is still opening: the close turns
  /// the opening around from its value and velocity (an iPhone 16 Pro,
  /// taps 0.05 - 0.3 s after the opening tap: 0.030, 0.042 and 0.038 s,
  /// 0.003 rms of the scale with the springs unchanged).
  static const double closeDelayWhileOpening = 0.037;

  /// The time from the lift of a tap on the label to the start of the
  /// open while the previous overlay is still closing: UIKit opens a new
  /// overlay from its hidden state and lets the old one finish its close
  /// (an iPhone 16 Pro, taps 0.05 - 0.3 s into the close: 0.072 s).
  static const double reopenDelay = 0.072;

  /// The time from the lift of the tap on the other label to the start of
  /// the [switchSpring] (an iPhone 16 Pro: 0.088 s).
  static const double switchDelay = 0.088;

  /// The scale of the hidden overlay about its anchor.
  static const double hiddenScale = 0.2;

  /// The seconds the overlay fades in or out for under Reduce Motion, at
  /// its full size, on [reducedMotionCurve]. Read from UIKit, notes
  /// private: UIDatePicker's overlay presentation replaces its spring by
  /// this fade under Reduce Motion (and switches pickers with it too;
  /// here a switch keeps [switchSpring] under Reduce Motion).
  static const double reducedMotionDuration = 0.3;

  /// The easing of the Reduce Motion fade: UIView's default curve.
  static const Curve reducedMotionCurve = Curves.easeInOut;

  /// The height of the hidden overlay's box before the scale: the overlay
  /// grows its box from this height to its own while it scales, so its
  /// content is revealed from the anchored edge.
  static const double hiddenHeight = 50;

  /// The distance from the label's center to the overlay's facing edge,
  /// across and along: the overlay's top sits this far below the label's
  /// center (or its bottom this far above), and its trailing edge this far
  /// before the center before it is moved inside the margins.
  static const double anchorOffset = 6;

  /// The space the overlay keeps from the screen's sides on a wide phone
  /// (the iOS 27 simulator's 440 point iPhone 18 Pro Max): UIKit's layout
  /// margin there.
  static const double margin = 20;

  /// The space the overlay keeps from the screen's sides on a phone
  /// narrower than [wideScreenWidth] (an iPhone 16 Pro, 402 points: the
  /// calendar's left edge at 16 in a screen recording).
  static const double compactMargin = 16;

  /// The screen width from which the overlay keeps [margin] rather than
  /// [compactMargin] from the sides: UIKit's system layout margins grow
  /// from 16 to 20 points on the 414 point and wider phones.
  static const double wideScreenWidth = 414;

  /// The space the overlay keeps from the sides of a screen [width]
  /// points wide.
  static double marginFor(double width) =>
      width >= wideScreenWidth ? margin : compactMargin;

  /// The duration of the change between the calendar's day grid and its
  /// month and year wheels, in seconds: a tap on the month title fades the
  /// grid, the weekday initials and the month chevrons out and the wheels
  /// in, and turns the title's chevron a quarter turn to point down, all on
  /// CABasicAnimations of this duration with [yearPickerCurve] (an iPhone
  /// 16 Pro: the layers' opacity and the chevron's frame follow it to
  /// 0.0001 with the start fitted).
  static const double yearPickerDuration = 0.25;

  /// The timing curve of the change between the day grid and the month and
  /// year wheels: UIKit's ease in and out.
  static const yearPickerCurve = Curves.easeInOut;

  /// The time from the lift of the tap on the month title to the start of
  /// the wheels fading in (an iPhone 16 Pro, eight taps: 0.061 - 0.077 s,
  /// mean 0.069; UIKit builds the wheels first).
  static const double yearPickerShowDelay = 0.069;

  /// The time from the lift of the tap on the month title to the start of
  /// the day grid fading back in (an iPhone 16 Pro, six taps: 0.018 -
  /// 0.022 s, mean 0.019).
  static const double yearPickerHideDelay = 0.019;

  /// The time from the lift of a second tap on the month title to the
  /// start of the day grid fading back in while the wheels still fade in
  /// (an iPhone 16 Pro, four taps 0.03 and 0.12 s after the first: 0.013
  /// s, 0.006 - 0.016 rms of the opacity against 0.019 - 0.038 with
  /// [yearPickerHideDelay]).
  static const double yearPickerHideDelayWhileShowing = 0.013;

  /// The duration of the label's highlight fading in and out, in seconds:
  /// a CABasicAnimation of its opacity with the timing curve
  /// [highlightCurve].
  static const double highlightDuration = 0.47;

  /// The timing curve of the label's highlight.
  static const highlightCurve = Curves.ease;

  /// The opacity the label's text fades toward under a touch (inferred
  /// from the start of the animation; about one half).
  static const double highlightOpacity = 0.5;

  /// The duration of a month page turn, in seconds: the grid slides one
  /// page on a sine ease in and out, fitted within 2 px rms; UIScrollView's
  /// own curve differs (approximation, date-picker passport).
  static const double pageDuration = 0.3;
}

/// Where the overlay of a compact date picker sits.
@immutable
class DatePickerPlacement {
  /// Creates a placement.
  const DatePickerPlacement({required this.rect, required this.anchor});

  /// The overlay's box.
  final Rect rect;

  /// The point the overlay grows out of and shrinks into: the label's
  /// center across (kept on the overlay's edge when the label's center is
  /// past it), the overlay's facing edge along.
  final Offset anchor;

  /// Whether the overlay sits below its label.
  bool get below => anchor.dy <= rect.top + 0.5;

  @override
  bool operator ==(Object other) =>
      other is DatePickerPlacement &&
      other.rect == rect &&
      other.anchor == anchor;

  @override
  int get hashCode => Object.hash(rect, anchor);
}

/// Places the overlay of a compact date picker of [size] for a [label] in
/// [screen], as UIKit does on iOS 27.
///
/// The overlay hangs below the label, its top
/// [DatePickerTuning.anchorOffset] below the label's center, or above
/// it when there is no room below inside [padding]. Across, it extends
/// toward the leading side: its trailing edge sits the offset before the
/// label's center, then it moves as little as it must to stay
/// [DatePickerTuning.marginFor] the screen's width from its sides.
/// Checked against six placements on the iOS 27 simulator and one on an
/// iPhone 16 Pro.
DatePickerPlacement placeDatePicker({
  required Size size,
  required Rect label,
  required Size screen,
  EdgeInsets padding = EdgeInsets.zero,
  TextDirection textDirection = TextDirection.ltr,
}) {
  const offset = DatePickerTuning.anchorOffset;
  final margin = DatePickerTuning.marginFor(screen.width);
  final c = label.center;
  final belowTop = c.dy + offset;
  final roomBelow = screen.height - padding.bottom - belowTop;
  final below = roomBelow >= size.height || c.dy > screen.height;
  final top = below
      ? belowTop
      : math.max(padding.top, c.dy - offset - size.height);
  final ideal = textDirection == TextDirection.ltr
      ? c.dx - offset - size.width
      : c.dx + offset;
  final low = margin + padding.left;
  final high = math.max(
    low,
    screen.width - margin - padding.right - size.width,
  );
  final left = ideal.clamp(low, high);
  final rect = Rect.fromLTWH(left, top, size.width, size.height);
  return DatePickerPlacement(
    rect: rect,
    anchor: Offset(
      c.dx.clamp(rect.left, rect.right),
      below ? rect.top : rect.bottom,
    ),
  );
}

/// The press highlight of a compact date picker's label: the text dims
/// under a finger over [DatePickerTuning.highlightDuration] on
/// [DatePickerTuning.highlightCurve] and comes back on release. Under
/// Reduce Motion (the motion's [Motion.traits]) the text does not dim
/// (approximation, not recorded on the device).
///
/// Times are seconds on the motion's timeline.
final class DatePickerLabelMotion extends Motion {
  late final _highlight = own(TimedValue(1));

  /// The label's text dims under a finger at time [t].
  void press(double t) => _to(t, DatePickerTuning.highlightOpacity);

  /// The finger left the label at time [t].
  void release(double t) => _to(t, 1);

  void _to(double t, double opacity) {
    advance(t);
    _highlight.animate(
      t,
      traits.reduceMotion ? 1 : opacity,
      duration: DatePickerTuning.highlightDuration,
      curve: DatePickerTuning.highlightCurve,
    );
  }

  /// The opacity of the label's text.
  double get highlight => _highlight.valueAt(now);
}

/// The motion of a compact date picker's overlay: opening out of its label
/// and closing back, and a switch between the date and the time picker.
///
/// One progress drives the overlay: it scales about its anchor from
/// [DatePickerTuning.hiddenScale], fades in, and grows its box from
/// [DatePickerTuning.hiddenHeight] to its own height, on
/// [DatePickerTuning.openSpring]; closing reverses it on
/// [DatePickerTuning.closeSpring], velocity included. The progress and a
/// switch rest within [overlayRest]. Under Reduce Motion (the motion's
/// [Motion.traits]) the overlay fades in and out at its full size over
/// [DatePickerTuning.reducedMotionDuration] instead (read from UIKit,
/// notes private).
///
/// Times are seconds on the motion's timeline.
final class DatePickerMotion extends Motion with Presented {
  /// Creates the motion of a closed overlay; a [reopening] one opens while
  /// an earlier overlay of the same picker still closes.
  DatePickerMotion({this.reopening = false});

  /// Whether the overlay opens while an earlier one still closes: it opens
  /// [DatePickerTuning.reopenDelay] after the tap instead of
  /// [DatePickerTuning.openDelay].
  final bool reopening;

  /// The size of the time overlay: the hour and minute wheels.
  static const Size timeSize = Size(232, 204);

  /// The swing of the overlay's progress, and of a switch between the
  /// pickers, at which they rest. NEAR: the calendar's edge lands by up to
  /// 0.27 pt, looser than [MotionRest.length]; resting at 0.1 pt costs 20
  /// more frames in the date-picker perf scene (172 to 192).
  static const double overlayRest = 1e-3;

  /// The swing at which a closing overlay counts as gone, and an opening
  /// one as open enough that a close waits the full delay. NEAR: 0.53 pt
  /// on the calendar's edge, behind an overlay that has faded out.
  static const double _closedRest = 2e-3;

  static double _rest() => overlayRest;

  late final _progress = own(
    MotionValue<double>(0, spring: DatePickerTuning.openSpring),
    rest: _rest,
  );
  late final _fade = own(TimedValue(0));
  late final _swap = own(
    MotionValue<double>(1, spring: DatePickerTuning.switchSpring),
    rest: _rest,
  );

  bool _open = false;
  double? _pendingAt;
  MotionCancel _cancelPending = _keep;
  int _pending = 0;
  bool _switching = false;

  static void _keep() {}

  bool get _reduced => traits.reduceMotion;

  /// Whether the overlay is open or opening.
  bool get isOpen => _open;

  /// Whether the overlay has closed and nothing of it moves.
  bool get isClosed =>
      !_open &&
      _pendingAt == null &&
      (_reduced ? _fade.restsAt(now) : _progress.restsAt(now, _closedRest));

  bool get _overlayRests {
    if (_pendingAt != null) return false;
    if (_reduced) return _fade.restsAt(now);
    final rest = _progress.restTime(overlayRest);
    return rest != null && rest <= now;
  }

  @override
  PresenceStatus get presence {
    if (_open) {
      return _overlayRests ? PresenceStatus.shown : PresenceStatus.opening;
    }
    return isClosed ? PresenceStatus.hidden : PresenceStatus.leaving;
  }

  /// Opens the overlay at time [t]: the spring starts [delay] seconds
  /// later ([DatePickerTuning.openDelay] by default, UIKit's latency from
  /// the lift of the tap, or [DatePickerTuning.reopenDelay] when
  /// [reopening]); until then whatever motion runs goes on.
  @override
  void open(double t, {double? delay}) {
    advance(t);
    _open = true;
    _schedule(
      t +
          (delay ??
              (reopening
                  ? DatePickerTuning.reopenDelay
                  : DatePickerTuning.openDelay)),
      1,
      DatePickerTuning.openSpring,
    );
  }

  @override
  bool leave(double t, DismissTrigger trigger) {
    advance(t);
    if (!_open && isClosed) return false;
    close(t);
    return true;
  }

  /// Closes the overlay at time [t], the spring starting [delay] seconds
  /// later: by default [DatePickerTuning.closeDelay] from rest and
  /// [DatePickerTuning.closeDelayWhileOpening] while the overlay
  /// still opens.
  void close(double t, {double? delay}) {
    advance(t);
    final opening =
        _pendingAt != null ||
        (_reduced ? !_fade.restsAt(t) : !_progress.restsAt(t, _closedRest));
    _open = false;
    _schedule(
      t +
          (delay ??
              (opening
                  ? DatePickerTuning.closeDelayWhileOpening
                  : DatePickerTuning.closeDelay)),
      0,
      DatePickerTuning.closeSpring,
    );
  }

  // A later command waits for an earlier one still due before it, which
  // runs at its own time; one due after it is dropped.
  void _schedule(double due, double target, Spring spring) {
    final pending = _pendingAt;
    if (pending != null && due < pending) _cancelPending();
    final id = ++_pending;
    _pendingAt = due;
    _cancelPending = at(due, (s) {
      if (id == _pending) _pendingAt = null;
      if (_reduced) {
        _fade.animate(
          s,
          target,
          duration: DatePickerTuning.reducedMotionDuration,
          curve: DatePickerTuning.reducedMotionCurve,
        );
        _progress.snap(s, target);
        return;
      }
      _progress.retarget(s, target, spring: spring);
    });
  }

  /// The overlay's progress: 0 hidden, 1 open.
  double get progress => _reduced ? _fade.valueAt(now) : _progress.valueAt(now);

  /// The overlay's scale about its anchor.
  double get scale => _reduced
      ? 1
      : DatePickerTuning.hiddenScale +
            (1 - DatePickerTuning.hiddenScale) * progress;

  /// The overlay's opacity.
  double get opacity => progress.clamp(0.0, 1.0);

  /// The height of the overlay's box before the scale, for an overlay
  /// [full] points tall.
  double height(double full) => _reduced
      ? full
      : DatePickerTuning.hiddenHeight +
            (full - DatePickerTuning.hiddenHeight) * progress;

  @override
  void didAdvance(double t) {
    if (_switching) {
      final rest = _swap.restTime(overlayRest);
      if (rest != null && rest <= t) _switching = false;
    }
  }

  /// Switches the overlay to the other picker at time [t], the lift of the
  /// tap on its label: [DatePickerTuning.switchDelay] later the platter
  /// moves to the new picker's placement on [DatePickerTuning.switchSpring]
  /// while the two contents cross-fade ([swap]). Switching [back] to the
  /// picker a running switch leaves turns that switch around from where it
  /// stands, velocity included.
  void switchPicker(double t, {required bool back}) {
    advance(t);
    final q = _swap.valueAt(t);
    final v = _swap.velocityAt(t);
    final start = t + DatePickerTuning.switchDelay;
    if (back && q < 1) {
      _swap.setPresentation(start, 1 - q, velocity: -v);
    } else {
      _swap.setPresentation(start, 0);
    }
    _swap.retarget(start, 1);
    _switching = true;
  }

  /// How far a switch between the pickers has gone: 0 the old picker's
  /// placement and content, 1 the new one's.
  double get swap => _swap.valueAt(now);

  /// Whether a switch between the pickers runs or waits to start.
  bool get switching => _switching;
}

/// The motion of a date picker's calendar: its month page turns and its
/// change between the day grid and the month and year wheels.
///
/// Page turns keep their timing under Reduce Motion (approximation, not
/// recorded on the device).
///
/// Times are seconds on the motion's timeline.
final class DatePickerCalendarMotion extends Motion {
  /// The size of the date overlay: a month calendar, five weeks or six
  /// (see [sixWeekRowHeight]), or the month and year wheels in its place.
  static const Size calendarSize = Size(320, 332);

  /// The height of a calendar row in a month of six weeks: UIKit keeps the
  /// calendar [calendarSize] and packs the six rows into the five rows'
  /// space (an iPhone 16 Pro, August 2026: cells 42.67 x 38, the chosen
  /// day's disc 38 across).
  static const double sixWeekRowHeight = 38;

  late final _page = own(TimedValue(1));
  late final _years = own(TimedValue(0));
  late final _turns = own(TimedValue(0, additive: true));

  int _pageDirection = 0;
  int _queued = 0;

  static const _queue = #queue;

  /// Takes a page turn in the given direction as it starts, or refuses it
  /// with false: the calendar turns the month it shows.
  bool Function(int direction)? onTurn;

  /// Turns the calendar one month forward ([direction] 1) or back (-1) at
  /// time [t], after [onTurn] takes the turn. A running turn completes
  /// before another can start: one asked for meanwhile waits for it, and
  /// turns asked for together add up and run one by one.
  void turnPage(double t, int direction) {
    advance(t);
    _queued += direction;
    _nextTurn(t);
  }

  void _nextTurn(double t) {
    while (_queued != 0 && _page.valueAt(t) >= 1) {
      final direction = _queued.sign;
      _queued -= direction;
      _turnPage(t, direction);
    }
    if (_queued != 0) at(_page.restTime()!, _nextTurn, slot: _queue);
  }

  void _turnPage(double t, int direction) {
    if (!(onTurn?.call(direction) ?? true)) return;
    _pageDirection = direction;
    _page.snap(t, 0);
    _page.animate(
      t,
      1,
      duration: DatePickerTuning.pageDuration,
      curve: const _SineInOut(),
    );
  }

  /// How far the current page turn has gone, from 0 (the old
  /// month in place) to 1 (the new one); 1 when no turn runs.
  double get page => _page.valueAt(now);

  /// The direction of the latest page turn: 1 forward, -1 back, 0 none.
  int get pageDirection => _pageDirection;

  /// Whether the calendar shows, or turns to, its month and year wheels.
  bool get showsYearPicker => _years.target == 1;

  /// Turns the calendar to its month and year wheels ([show] true) or back
  /// to its day grid at time [t], the tap's lift.
  ///
  /// The change starts [DatePickerTuning.yearPickerShowDelay] or
  /// [DatePickerTuning.yearPickerHideDelay] later
  /// ([DatePickerTuning.yearPickerHideDelayWhileShowing] when the
  /// wheels still fade in) and runs
  /// [DatePickerTuning.yearPickerDuration] seconds on
  /// [DatePickerTuning.yearPickerCurve] from wherever the previous
  /// change stands then, as UIKit restarts its animations from the
  /// presentation value; until then the previous change goes on.
  ///
  /// The month title's chevron ([yearPickerTurn]) adds each change on top
  /// of the ones still running instead of restarting from the current
  /// angle (an iPhone 16 Pro: a second tap 0.12 s into the change carries
  /// the chevron on to 0.82 of the turn before it comes back, while the
  /// fades turn around at once).
  void showYearPicker(double t, {required bool show}) {
    advance(t);
    final target = show ? 1.0 : 0.0;
    final moving = t < (_years.restTime() ?? double.infinity);
    final delay = show
        ? DatePickerTuning.yearPickerShowDelay
        : moving
        ? DatePickerTuning.yearPickerHideDelayWhileShowing
        : DatePickerTuning.yearPickerHideDelay;
    _years.animate(
      t,
      target,
      duration: DatePickerTuning.yearPickerDuration,
      curve: DatePickerTuning.yearPickerCurve,
      delay: delay,
    );
    if (target != _turns.target) {
      _turns.animate(
        t,
        target,
        duration: DatePickerTuning.yearPickerDuration,
        curve: DatePickerTuning.yearPickerCurve,
        delay: delay,
      );
    }
  }

  /// How far the month title's chevron has turned toward pointing down: 0
  /// pointing forward, 1 down.
  double get yearPickerTurn => _turns.valueAt(now);

  /// How far the calendar has turned to its month and year wheels: 0 the
  /// day grid, 1 the wheels.
  double get yearPicker => _years.valueAt(now);
}

/// A sine ease in and out, `(1 - cos(pi k)) / 2`: a page turn's curve.
final class _SineInOut extends Curve {
  const _SineInOut();

  @override
  double transformInternal(double t) => (1 - math.cos(math.pi * t)) / 2;
}

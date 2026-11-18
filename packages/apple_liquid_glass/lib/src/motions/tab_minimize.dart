import 'package:kinesis/motion.dart';
import 'package:meta/meta.dart';

/// When a tab bar minimizes to its selected tab while the content under it
/// scrolls.
///
/// UIKit: `UITabBarController.MinimizeBehavior`. SwiftUI:
/// `TabBarMinimizeBehavior`.
enum GlassTabBarMinimizeBehavior {
  /// The platform's default for the context. On an iPhone tab bar that
  /// does not opt in, UIKit's default does not minimize, so this resolves
  /// to [never] (an approximation: the resolution is not read from UIKit).
  automatic,

  /// The bar never minimizes.
  never,

  /// The bar minimizes when the content scrolls down. It expands at the
  /// content's top end, on a tap and when the content is pushed past its
  /// far end; a scroll back up in the middle of the content leaves it
  /// minimized, as iOS 27 does.
  onScrollDown,

  /// The bar minimizes when the content scrolls up, mirroring
  /// [onScrollDown]; for content aligned to the bottom (a chat).
  onScrollUp;

  /// Whether a bar with this behavior minimizes at all.
  bool get minimizes => this == onScrollDown || this == onScrollUp;
}

/// The measured tuning of a minimizing tab bar and its bottom accessory.
///
/// The thresholds, springs and the hint scale are read from UIKit on iOS
/// 27 (the scroll-away interaction of the floating tab bar, its animation
/// settings and its phone layout record; notes private), the circle
/// matched to the measured search tab circle (48 pt, 28 from the side and
/// the bottom). The bar turns into the circle in one liquid morph of its
/// shape and content ([morphSpring]); the four collapse and expand springs
/// move only the bottom accessory, one axis after the other (iPhone 16 Pro,
/// layer rows, within 0.09 points). What the content does during the morph
/// is taken from films of the same phone, by eye.
@internal
abstract final class TabBarMinimizeTuning {
  /// The scroll in the minimizing direction, in points, before the bar
  /// starts to respond: UIKit's activation threshold, 0.
  static const double activationDistance = 0;

  /// The scroll, in points, past [activationDistance] that takes the bar
  /// from expanded to minimized: UIKit's active distance, 64.
  static const double activeDistance = 64;

  /// The scrollable range a content needs, as a multiple of
  /// [activationDistance] + [activeDistance], before the bar minimizes
  /// over it: 1.5 (96 pt), read from UIKit.
  static const double minimumRangeFactor = 1.5;

  /// The least progress of a scroll that has started to minimize the
  /// bar, so a scroll that turns back mid-way does not read as one that
  /// expanded it: UIKit clamps between 0.01 and 1.
  static const double minimumProgress = 0.01;

  /// How much smaller the bar draws at the end of a scroll's progress,
  /// before it minimizes: the bar's glass group scales by 1 - 0.05 x
  /// progress about its center, read from UIKit.
  static const double hintScale = 0.05;

  /// The spring of the hint while a finger drags the content (UIKit
  /// `scrollAwayTrackingProgressSpring`: damping 0.8, response 0.1).
  static const hintTrackingSpring = Spring.response(0.1, dampingRatio: 0.8);

  /// The spring of the hint while the content decelerates on its own
  /// (UIKit `scrollAwayProgressSpring`: damping 0.8, response 0.5).
  static const hintSpring = Spring.response(0.5, dampingRatio: 0.8);

  /// The spring the hint returns to full size on when the bar minimizes,
  /// expands or the scroll ends short of it (UIKit
  /// `scrollAwayHintResetSpring`: damping 0.8, response 0.3).
  static const hintResetSpring = Spring.response(0.3, dampingRatio: 0.8);

  /// The spring of the liquid morph between the bar and the circle: every
  /// channel of the shapes (size, position, transform) and the morph of
  /// their content, both ways, without a delay (damping 0.8, response 0.3;
  /// read from UIKit).
  static const morphSpring = Spring.response(0.3, dampingRatio: 0.8);

  /// [morphSpring] under Reduce Motion: critically damped, response 0.15
  /// (read from UIKit).
  static const reducedMotionMorphSpring = Spring.response(0.15);

  /// The spring the bottom accessory's horizontal position and width move
  /// on as the bar minimizes (UIKit `collapseIntermediateSpring`: damping
  /// 0.72, response 0.36).
  static const accessoryCollapseSpring = Spring.response(
    0.36,
    dampingRatio: 0.72,
  );

  /// The spring its vertical position and height follow on,
  /// [accessoryFollowDelay] later (`collapseFinalSpring`: damping 0.76,
  /// response 0.42).
  static const accessoryCollapseFollowSpring = Spring.response(
    0.42,
    dampingRatio: 0.76,
  );

  /// The spring the bottom accessory's vertical position and height move
  /// on as the bar expands (`expandIntermediateSpring`: damping 0.72,
  /// response 0.3).
  static const accessoryExpandSpring = Spring.response(0.3, dampingRatio: 0.72);

  /// The spring its horizontal position and width follow on,
  /// [accessoryFollowDelay] later (`expandFinalSpring`: damping 0.72,
  /// response 0.36).
  static const accessoryExpandFollowSpring = Spring.response(
    0.36,
    dampingRatio: 0.72,
  );

  /// The delay of the accessory's second axis, both ways (0.05 s).
  static const double accessoryFollowDelay = 0.05;

  /// How far a finger on the minimized bar moves along the bar, in points,
  /// before the bar expands and the touch becomes the bar's selection drag:
  /// 4, read from UIKit. A finger that only rests does nothing more: a 1.6 s
  /// hold leaves the circle lifted until the lift (iPhone 16 Pro).
  static const double dragHysteresis = 4;

  /// The spring of that lift: damping 0.625, response 0.262, fitted to the
  /// device's rows within 0.01 points.
  static const pressSpring = Spring.response(0.262, dampingRatio: 0.625);

  /// The time from the touch to the start of that lift: 0.032 s.
  static const double pressLag = 0.032;
}

/// The scroll-away interaction of a minimizing tab bar: how far a user's
/// scroll has carried the bar toward minimizing, ported from UIKit's
/// floating tab bar (iOS 27.0.1; equations read from UIKit, notes
/// private).
///
/// Offsets are along the content's scroll axis, growing as the content
/// moves toward its end (Flutter's `pixels` on a downward list, UIKit's
/// `contentOffset.y`); `min` and `max` are the offsets of the content's
/// two ends. Only a user's scroll counts: a drag, and the deceleration
/// after it. A programmatic scroll is only recorded ([last]).
///
/// - A drag starts a fresh accumulation ([beginDrag]).
/// - Past an end, only motion further past it counts (a rubber band's
///   return does not).
/// - Motion in the minimizing direction starts the interaction once it
///   passes the activation distance (0 points), if the content's range is
///   at least 1.5 x (activation + active distance, 96 points); from then
///   on [progress] grows by the scroll over the active distance (64
///   points), clamped to 0.01 - 1; at 1 the bar minimizes and the
///   interaction rests until the next drag.
/// - The end of a drag that does not decelerate, and the end of a
///   deceleration, floor [progress]: a scroll that stopped short returns
///   to 0.
/// - Pushing further past the far end while the bar is minimized expands
///   it, as does reaching the near end while the interaction runs.
/// - A scroll to the top ([scrollToTop]) expands it.
/// - A drag in the expanding direction in the middle of the content does
///   not expand a minimized bar: UIKit's code has no such path, and on the
///   iOS 27 simulator a 150 point drag back left the bar minimized,
///   although the SDK header says the bar expands when the content
///   scrolls back.
class ScrollAway {
  /// Creates the interaction; [minimizesOnScrollUp] reverses the
  /// minimizing direction (UIKit `onScrollUp`).
  ScrollAway({this.minimizesOnScrollUp = false});

  /// Whether scrolling toward the content's start minimizes the bar.
  bool minimizesOnScrollUp;

  /// How far the bar has gone toward minimizing: 0 expanded, 1 minimized.
  double get progress => _progress;
  double _progress = 0;

  /// Called with the new [progress] and whether a finger drags the
  /// content, whenever [progress] changes.
  void Function(double progress, {required bool tracking})? onProgress;

  _State _state = _State.idle;
  double _accumulated = 0;
  double _startProgress = 0;

  /// The content's offset when it last moved; set it to record a scroll the
  /// user did not drive, without reacting to it.
  double? last;
  bool _tracking = false;

  /// Starts a fresh accumulation: a finger began to drag the content.
  void beginDrag() {
    _state = _State.accumulating;
    _accumulated = 0;
    _tracking = true;
  }

  /// Puts [progress] at [value] without reporting it: the bar was
  /// minimized or expanded by other means (a tap, the app).
  void reset(double value) {
    _state = _State.idle;
    _progress = value;
  }

  /// Reacts to the content scrolled to [offset] by a user (dragging when
  /// [tracking], else decelerating), its ends at [min] and [max].
  void scroll(
    double offset, {
    required double min,
    required double max,
    required bool tracking,
  }) {
    _tracking = tracking;
    final previous = last;
    last = offset;
    if (previous == null || _state == _State.idle) return;
    var delta = offset - previous;
    if (offset > max && delta < 0) delta = 0;
    if (offset < min && delta > 0) delta = 0;
    final signed = minimizesOnScrollUp ? -delta : delta;
    var excess = 0.0;
    if (_state == _State.accumulating) {
      final same = (signed < 0) == (_accumulated < 0);
      final acc = same ? _accumulated + signed : signed;
      _accumulated = acc;
      const threshold = TabBarMinimizeTuning.activationDistance;
      if (acc.abs() < threshold) return;
      final atFarEdge = minimizesOnScrollUp ? offset <= min : offset >= max;
      if (atFarEdge && signed > 0 && _progress != 0) {
        _state = _State.idle;
        _set(0);
        return;
      }
      const range =
          TabBarMinimizeTuning.minimumRangeFactor *
          (threshold + TabBarMinimizeTuning.activeDistance);
      if (acc < threshold || max - min < range) return;
      _state = _State.active;
      _startProgress = _progress;
      excess = acc - threshold > 0 ? acc - threshold : 0;
    } else {
      excess = signed;
    }
    final atNearEdge = minimizesOnScrollUp ? offset >= max : offset <= min;
    if (atNearEdge && excess < 0 && _startProgress != 0) {
      _state = _State.idle;
      _set(0);
      return;
    }
    if (_progress == 1) return;
    final next = (_progress + excess / TabBarMinimizeTuning.activeDistance)
        .clamp(TabBarMinimizeTuning.minimumProgress, 1.0);
    if (next == _progress) return;
    if (next == 1) _state = _State.idle;
    _set(next);
  }

  /// The finger lifted; [decelerates] when the content goes on moving.
  void endDrag({required bool decelerates}) {
    _tracking = false;
    if (decelerates) return;
    _end();
  }

  /// The content stopped after a deceleration.
  void endDeceleration() => _end();

  /// The content is scrolled to its top: the bar expands.
  void scrollToTop() {
    _state = _State.idle;
    _set(0);
  }

  void _end() {
    _state = _State.idle;
    _tracking = false;
    _set(_progress.floorToDouble());
  }

  void _set(double value) {
    if (value == _progress) return;
    _progress = value;
    onProgress?.call(value, tracking: _tracking);
  }
}

enum _State { accumulating, active, idle }

/// The motion of a minimizing tab bar: the scroll-away interaction
/// ([ScrollAway]), the hint scale it drives and the morph between the
/// expanded bar and its minimized circle.
///
/// While a scroll carries the bar toward minimizing, the whole bar group
/// draws smaller by [TabBarMinimizeTuning.hintScale] x progress on
/// the tracking spring (a finger down) or the progress spring
/// (decelerating), and returns to full size on the reset spring when it
/// minimizes, expands or the scroll stops short. Minimizing or expanding
/// runs the liquid morph of the bar ([morph]) on one spring, and moves the
/// bottom accessory along the bar ([accessoryX]) and up it ([accessoryY])
/// one after the other. A change in the middle of another turns it around
/// with its velocity.
///
/// Every spring rests within a visible scale step of a bar group [extent]
/// points wide ([MotionRest.scale]).
///
/// Times are seconds on the motion's timeline.
final class TabBarMinimizeMotion extends Motion {
  /// Creates the motion of a bar that minimizes as [behavior] says.
  TabBarMinimizeMotion({
    GlassTabBarMinimizeBehavior behavior =
        GlassTabBarMinimizeBehavior.onScrollDown,
  }) : _behavior = behavior {
    scrollAway.minimizesOnScrollUp =
        behavior == GlassTabBarMinimizeBehavior.onScrollUp;
    scrollAway.onProgress = _progressChanged;
  }

  /// The diameter of the minimized bar: UIKit's collapsed platter, 48,
  /// the size of the search tab's circle while searching.
  static const double collapsedSize = 48;

  /// How far a finger lifts the circle: from 48 to 64 points (iPhone 16 Pro).
  static const double pressGrowth = 8;

  /// The height of a tab's glyph center in the bar: 24 points, read from
  /// UIKit.
  static const double glyphCenter = 24;

  /// The morph's progress at which the lens has gone: it goes within two
  /// frames of the start (film), and comes back as late.
  static const double lensGoneAt = 0.1;

  /// The morph's progress at which the titles have gone: 0.07 s into it
  /// (film).
  static const double titlesGoneAt = 0.48;

  /// The morph's progress at which the other tabs have gone: 0.13 s into it
  /// (film).
  static const double othersGoneAt = 0.85;

  /// How much the tabs that dissolve draw together toward the circle over
  /// the whole morph, by eye.
  static const double othersDrift = 0.15;

  /// The blur the dissolving tabs reach, by eye: UIKit's radius is not read.
  static const double othersBlur = 3;

  /// The scroll-away interaction; feed it the content's scrolls after
  /// [advance] to their time.
  final ScrollAway scrollAway = ScrollAway();

  /// The width of the bar group, which sets how closely the springs rest.
  double extent = 400;

  double _rest() => MotionRest.scale(extent);

  late final _hint = own(
    MotionValue<double>(1, spring: TabBarMinimizeTuning.hintResetSpring),
    rest: _rest,
  );
  late final _morph = own(
    MotionValue<double>(0, spring: TabBarMinimizeTuning.morphSpring),
    rest: _rest,
  );
  late final _accessoryX = own(
    MotionValue<double>(
      0,
      spring: TabBarMinimizeTuning.accessoryCollapseSpring,
    ),
    rest: _rest,
  );
  late final _accessoryY = own(
    MotionValue<double>(0, spring: TabBarMinimizeTuning.accessoryExpandSpring),
    rest: _rest,
  );
  late final _press = own(
    MotionValue<double>(0, spring: TabBarMinimizeTuning.pressSpring),
    rest: _rest,
  );

  static const _follow = #follow;
  static const _lift = #lift;

  /// The behavior; a bar that no longer minimizes expands.
  GlassTabBarMinimizeBehavior get behavior => _behavior;
  GlassTabBarMinimizeBehavior _behavior;

  /// Changes the behavior at time [t].
  void setBehavior(double t, GlassTabBarMinimizeBehavior value) {
    advance(t);
    if (value == _behavior) return;
    _behavior = value;
    scrollAway.minimizesOnScrollUp =
        value == GlassTabBarMinimizeBehavior.onScrollUp;
    scrollAway.reset(0);
    _hint.retarget(t, 1, spring: TabBarMinimizeTuning.hintResetSpring);
    if (!value.minimizes) _setMinimized(t, minimized: false);
  }

  // Under Reduce Motion (the motion's traits) the morph runs on its own
  // spring and a finger lifts nothing.
  bool get _reduced => traits.reduceMotion;

  /// Whether the bar is minimized or heading there.
  bool get minimized => _minimized;
  bool _minimized = false;

  /// Minimizes or expands the bar at time [t].
  void setMinimized(double t, {required bool minimized}) {
    advance(t);
    _setMinimized(t, minimized: minimized);
  }

  void _setMinimized(double t, {required bool minimized}) {
    scrollAway.reset(minimized ? 1 : 0);
    if (_hint.target != 1) {
      _hint.retarget(t, 1, spring: TabBarMinimizeTuning.hintResetSpring);
    }
    _transition(t, minimized: minimized);
  }

  void _progressChanged(double progress, {required bool tracking}) {
    final t = now;
    if (progress > 0 && progress < 1) {
      _hint.retarget(
        t,
        1 - progress * TabBarMinimizeTuning.hintScale,
        spring: tracking
            ? TabBarMinimizeTuning.hintTrackingSpring
            : TabBarMinimizeTuning.hintSpring,
      );
    } else {
      _hint.retarget(t, 1, spring: TabBarMinimizeTuning.hintResetSpring);
    }
    if (progress == 0 && _minimized) _transition(t, minimized: false);
    if (progress == 1 && !_minimized && _behavior.minimizes) {
      _transition(t, minimized: true);
    }
  }

  void _transition(double t, {required bool minimized}) {
    if (minimized == _minimized) return;
    _minimized = minimized;
    final target = minimized ? 1.0 : 0.0;
    _morph.retarget(
      t,
      target,
      spring: _reduced
          ? TabBarMinimizeTuning.reducedMotionMorphSpring
          : TabBarMinimizeTuning.morphSpring,
    );
    // Collapsing, the accessory moves along first and up after; expanding,
    // up first and along after: an L, not a straight path.
    final first = minimized ? _accessoryX : _accessoryY;
    final second = minimized ? _accessoryY : _accessoryX;
    first.retarget(
      t,
      target,
      spring: minimized
          ? TabBarMinimizeTuning.accessoryCollapseSpring
          : TabBarMinimizeTuning.accessoryExpandSpring,
    );
    at(
      t + TabBarMinimizeTuning.accessoryFollowDelay,
      (s) => second.retarget(
        s,
        target,
        spring: minimized
            ? TabBarMinimizeTuning.accessoryCollapseFollowSpring
            : TabBarMinimizeTuning.accessoryExpandFollowSpring,
      ),
      slot: _follow,
    );
  }

  double? _pressX;

  /// Whether a finger that went down on the minimized bar is still on it.
  bool get pressed => _pressX != null;

  /// A finger went down at [x] along the minimized bar at time [t]; the
  /// circle lifts under it. Nothing happens on a bar that is not minimized.
  void pressDown(double t, double x) {
    advance(t);
    if (!_minimized) return;
    _pressX = x;
    if (_reduced) return;
    at(
      t + TabBarMinimizeTuning.pressLag,
      (s) => _press.retarget(s, 1, spring: TabBarMinimizeTuning.pressSpring),
      slot: _lift,
    );
  }

  /// The finger moved to [x] along the bar at time [t]; true on the move
  /// that makes it the bar's selection drag: the bar expands, for good.
  bool pressMove(double t, double x) {
    advance(t);
    final from = _pressX;
    if (from == null) return false;
    if ((x - from).abs() < TabBarMinimizeTuning.dragHysteresis) return false;
    _endPress(t);
    if (_minimized) _setMinimized(t, minimized: false);
    return true;
  }

  /// The finger lifted at time [t] without having moved along the bar: the
  /// bar expands and stays expanded, and selects nothing, however long the
  /// finger rested (iPhone 16 Pro).
  void pressUp(double t) {
    advance(t);
    if (_pressX == null) return;
    _endPress(t);
    _setMinimized(t, minimized: false);
  }

  /// The touch was taken away at time [t]: the circle settles back.
  void pressCancel(double t) {
    advance(t);
    if (_pressX == null) return;
    _endPress(t);
  }

  void _endPress(double t) {
    unschedule(_lift);
    _pressX = null;
    _press.retarget(t, 0, spring: TabBarMinimizeTuning.morphSpring);
  }

  /// How far a finger has lifted the circle, 0 to 1.
  double get press => _press.valueAt(now);

  /// The scale of the bar group: 1, or less while a scroll
  /// hints at minimizing.
  double get hint => _hint.valueAt(now);

  /// The morph's way from the expanded bar (0) to the minimized circle
  /// (1): of the glass's shape and of the content.
  double get morph => _morph.valueAt(now);

  /// The bottom accessory's way from above the bar (0) to beside the
  /// circle (1) along the bar: its horizontal position and width.
  double get accessoryX => _accessoryX.valueAt(now);

  /// The bottom accessory's way from above the bar (0) to beside the
  /// circle (1) up the screen: its vertical position and height.
  double get accessoryY => _accessoryY.valueAt(now);
}

import 'dart:math' as math;
import 'dart:ui';

import 'package:apple_liquid_glass/src/motions/sheet_event.dart';
import 'package:apple_liquid_glass/src/motions/sheet_layout.dart';
import 'package:apple_liquid_glass/src/motions/sheet_tuning.dart';
import 'package:apple_liquid_glass/src/motions/ui_frame_rate.dart';
import 'package:kinesis/motion.dart';

/// The motion of an iOS 27 sheet: its height between detents, its
/// translation while presenting and dismissing, how far it docks to the
/// screen edges and how much it dims what is behind it.
///
/// Heights are the sheet's unscaled heights in pixels, bottom safe area
/// included; the translation moves the sheet down from its resting place.
/// Presenting, dismissing and moving between detents ride
/// [SheetTuning.spring] (a flicked-away sheet
/// [SheetTuning.flickDismissSpring]) and carry velocity through every
/// retarget. A sheet resting below the large detent floats: it is the
/// full-width sheet scaled down so that it keeps
/// [SheetMotion.floatingInset] from the sides and the bottom. UIKit
/// docks it to the large detent as one transform interpolated by the
/// docking progress, the fraction of the height travelled between where
/// the transition started and the large detent (on the way back, between
/// the large detent and the floating one the sheet heads to); the scale,
/// the bottom corner radius ([bottomRadius]) and the opaque background
/// follow the same fraction. A move between two floating detents keeps the
/// sheet floating throughout.
///
/// The opaque fill that replaces the glass at the large detent follows
/// its own [SheetTuning.spring] toward the background of the detent
/// the sheet heads to: in a settle or a programmatic change it keeps pace
/// with the docking, while a drag switches it where the docking progress
/// crosses [SheetTuning.backgroundSwitch], so the glass gives way to
/// the fill at a point of the drag rather than along it.
///
/// A touch swells a floating sheet by [SheetTuning.pressScale] and
/// the swell holds through the drag the touch turns into. A drag moves
/// the sheet's top edge with the finger: between the smallest
/// and the largest detent the height follows it point for point, above
/// a floating largest detent it rubber-bands toward the maximum height
/// (at most [SheetTuning.stretchLimit]), a docked sheet does not
/// move up, and below the smallest the whole sheet slides down. A sheet
/// that floats when the drag begins stretches along
/// the drag with the finger's travel and its changes of speed
/// ([SheetTuning.stretchPerPoint]), keeping its area and its bottom
/// edge, and springs back on release.
/// Releasing above the smallest detent settles on the
/// detent nearest to the height projected by
/// [SheetTuning.projection]; releasing below it dismisses when the
/// projected slide passes half the sheet's visible height or the finger
/// moves faster than [SheetTuning.dismissVelocity], and returns
/// otherwise. The settle carries [SheetTuning.releaseVelocityGain]
/// times the finger's velocity. A tap on the grabber band cycles to the
/// next detent.
///
/// Height and offset rest within [MotionRest.length], the swell and the
/// stretch within [MotionRest.scale] of the sheet's longer side, the
/// sideways drift within [MotionRest.length] of the inset, the fill within
/// [MotionRest.opacity]: invisible, NEAR.
///
/// As a presentation's motion it is made before the sheet is laid out
/// ([SheetMotion.presented]) and learns its detents from [layout]: until
/// then it holds no heights, is opening once opened, and a leave ends the
/// presentation at once.
class SheetMotion extends Motion with Presented, PredictiveBack {
  /// Creates a motion with the given detent [heights] (ascending), resting
  /// hidden below the screen until [present].
  ///
  /// [fullHeight] is the height of a sheet at the maximum detent value,
  /// the room a drag up may stretch a floating sheet into; null takes the
  /// largest detent, which leaves no room.
  SheetMotion({
    required List<double> heights,
    required this.width,
    required int initial,
    double? fullHeight,
    this._dockedIndex,
    this._undimmedIndex,
    this.dismissible = true,
    this.inset = SheetMotion.floatingInset,
    this.displayRadius,
    super.clock,
  }) : _heights = List<double>.of(heights),
       _fullHeight = fullHeight ?? heights.last,
       _index = initial,
       _restingHeight = heights[initial],
       _restingFill = initial == _dockedIndex ? 1 : 0 {
    _restAt(0, initial);
  }

  /// Creates the motion of a presented sheet on [clock], hidden and holding
  /// no heights until its first [layout].
  SheetMotion.presented({
    this.dismissible = true,
    this.inset = SheetMotion.floatingInset,
    this.displayRadius,
    super.clock,
  }) : _heights = const [],
       width = 0,
       _fullHeight = 0,
       _index = 0,
       _restingHeight = 0,
       _restingFill = 0;

  /// The gap around a sheet resting below the large detent, in points:
  /// it floats 8 points from the sides and the bottom of the screen.
  static const double floatingInset = 8;

  /// How far, in points, a finger travels on the sheet before the sheet
  /// follows it: the device drags start 12 points from the touch (7 on
  /// the simulator); the drag replays use the device value.
  static const double dragSlop = 12;

  /// The band at the top of the sheet, in unscaled points, where a tap
  /// cycles the detents as a tap on the grabber does; a tap 25 points
  /// below the top edge cycled them, 40 is not measured.
  static const double grabberHitHeight = 40;

  @override
  double get minFrameRate => uikitMinFrameRate;

  List<double> _heights;
  double _fullHeight;

  /// The width of the container in pixels.
  double width;

  /// The corner radius of the display, or null where the platform reports
  /// none: the radius the bottom corners turn to as the sheet docks, less
  /// [inset] while it floats. The host updates it with every layout.
  double? displayRadius;

  /// The index of the detent that docks the sheet edge to edge, or null
  /// when no detent does.
  int? get dockedIndex => _dockedIndex;
  int? _dockedIndex;

  /// The index of the largest detent that does not dim, or null when
  /// every detent dims.
  int? get undimmedIndex => _undimmedIndex;
  int? _undimmedIndex;

  /// Whether a drag down may dismiss the sheet; otherwise the pull below
  /// the smallest detent rubber-bands. The host updates it before each
  /// drag (a PopScope may turn dismissal off).
  bool dismissible;

  /// The gap around the floating sheet in pixels.
  final double inset;

  final double _restingHeight;
  final double _restingFill;

  late final MotionValue<double> _height = own(
    MotionValue<double>(_restingHeight, spring: SheetTuning.spring),
    rest: () => MotionRest.length,
  );
  late final MotionValue<double> _offset = own(
    MotionValue<double>(0, spring: SheetTuning.spring),
    rest: () => MotionRest.length,
  );
  late final MotionValue<double> _fill = own(
    MotionValue<double>(_restingFill, spring: SheetTuning.spring),
    rest: () => MotionRest.opacity,
  );
  late final MotionValue<double> _press = own(
    MotionValue<double>(1, spring: SheetTuning.pressSpring),
    rest: () => _scaleRest,
  );
  late final MotionValue<double> _stretch = own(
    MotionValue<double>(0, spring: SheetTuning.stretchSpring),
    rest: () => _scaleRest,
  );
  late final MotionValue<double> _drift = own(
    MotionValue<double>(0, spring: SheetTuning.spring),
    rest: () => _driftRest,
  );
  // Not a part: it moves the sheet only while a drag stretches it, and the
  // drag holds the motion.
  final _lag = MotionValue<double>(
    0,
    spring: SheetTuning.stretchLagSpring,
  );
  static const Object _pressSlot = #press;
  bool _stretching = false;
  double _travel = 0;
  double _travelAt = 0;
  double _travelVelocity = 0;
  int _index;
  bool _dismissing = false;

  bool _toDocked = false;
  double _dockStart = 0;
  double _radiusStart = 0;
  bool _squareAtRest = false;
  double _heightStart = 0;
  double _floating = 0;

  double? _dragFrom;
  double _dragTop = 0;

  /// The detent heights, ascending.
  List<double> get heights => _heights;

  /// The detent the sheet rests at or heads to.
  int get index => _index;

  final List<SheetEvent> _events = [];

  /// The events raised since the last call, oldest first.
  List<SheetEvent> drainEvents() {
    if (_events.isEmpty) return const [];
    final drained = List<SheetEvent>.of(_events);
    _events.clear();
    return drained;
  }

  /// Whether events wait for [drainEvents].
  bool get hasEvents => _events.isNotEmpty;

  /// Whether the sheet is leaving or has left.
  bool get isDismissing => _dismissing;

  /// Whether a drag holds the sheet.
  bool get isDragging => _dragFrom != null && !_released;

  double get _floatingBelowDocked {
    final docked = dockedIndex;
    if (docked == null) return _heights.first;
    return docked > 0 ? _heights[docked - 1] : _heights[docked];
  }

  /// The translation that hides the sheet below the screen: its visible
  /// height and its gap to the bottom at the selected detent.
  double get hiddenOffset {
    final h = _heights[_index];
    final d = _index == dockedIndex ? 1.0 : 0.0;
    final s = _scaleFor(d);
    return h * s + h * (1 - s) / 2 - _shiftFor(h, d);
  }

  /// Whether the sheet is dismissed and still: its offset swings less
  /// than half a point about the hidden offset, where the sheet's top sits
  /// at the container's bottom edge.
  bool get isDismissed =>
      _dismissing && _offset.restsAt(now, 0.5) && _dragFrom == null;

  @override
  bool get holds => _dragFrom != null || _released || _stretching;

  double get _driftRest => inset <= 0 ? 1 : MotionRest.length / inset;

  double get _scaleRest => MotionRest.scale(
    _heights.isEmpty ? width : math.max(width, _heights[_index]),
  );

  /// The unscaled height.
  double get height => _height.valueAt(now);

  /// The translation down from the resting place.
  double get offset => _offset.valueAt(now);

  /// The docking progress: 0 floating, 1 edge to edge.
  double get dock => _dockAt(now);

  double _dockAt(double t) => _dockFor(_height.valueAt(t));

  /// The opacity of the opaque fill, 0 to 1: 0 shows the
  /// glass of a floating sheet, 1 the fill of a docked one, which hides
  /// the glass.
  ///
  /// A fill within its rest reads its target even while a drag holds the
  /// motion, so the glass gives way to the opaque fill as the drag docks.
  double get fill => _fill.restsAt(now, MotionRest.opacity)
      ? _fill.target
      : _fill.valueAt(now).clamp(0.0, 1.0);

  /// The display corner radius a card or sheet assumes where the platform
  /// reports none (62, the iPhone 16 Pro's).
  static const double fallbackDisplayRadius = SheetTuning.fallbackDisplayRadius;

  /// The radius of the bottom corners of a floating sheet, in unscaled
  /// pixels: the display's less [inset] (62 - 8 = 54 on an iPhone 16 Pro),
  /// [fallbackDisplayRadius] less it where the platform
  /// reports none.
  double get floatingRadius => (displayRadius ?? fallbackDisplayRadius) - inset;

  /// The radius the bottom corners turn to as the sheet docks: the
  /// display's, 0 where the platform reports none.
  double get dockedRadius => displayRadius ?? 0;

  /// The radius of the bottom corners now, in unscaled pixels; the top
  /// corners keep their own radius.
  ///
  /// Device clip layer, every frame (test/fixtures/ios27-device/sheet):
  /// a programmatic docking turns it from [floatingRadius] to
  /// [dockedRadius] in step with the docking progress `p`, linear in `p`
  /// (54 + 8 p), and once the sheet rests docked it is 0, square under the
  /// display's own corner, which hides it. Undocking from there runs from
  /// 0 to [floatingRadius] as `54 (1 - p)`. A transition that starts
  /// anywhere else runs from the radius it starts at, in step with the
  /// docking. A drag sets it from the docking progress as
  /// `docked - (docked - floating) (1 - p)^2`, concentric with the
  /// shrinking gap to the screen edge (simulator: 58.44 at `p` 0.333; UIKit
  /// rounds the gap up to a third of a point, this curve is smooth: NEAR). A
  /// sheet presented docked keeps [dockedRadius] (a large-only sheet reads
  /// 62 through its present and dismissal).
  double get bottomRadius => _bottomRadiusAt(now);

  double _bottomRadiusAt(double t) {
    final floating = floatingRadius;
    final docked = dockedRadius;
    final d = _dockAt(t);
    final double radius;
    if (_dragFrom != null) {
      radius = docked - (docked - floating) * (1 - d) * (1 - d);
    } else if (_toDocked) {
      if (_height.restsAt(t, MotionRest.length)) {
        radius = _squareAtRest ? 0 : docked;
      } else {
        final span = 1 - _dockStart;
        final p = span <= 1e-9
            ? 1.0
            : ((d - _dockStart) / span).clamp(0.0, 1.0);
        radius = _radiusStart + (docked - _radiusStart) * p;
      }
    } else if (_dockStart <= 1e-9) {
      radius = floating;
    } else {
      radius =
          floating +
          (_radiusStart - floating) * (d / _dockStart).clamp(0.0, 1.0);
    }
    return math.max(0, radius);
  }

  double get _rubberRoom =>
      (_fullHeight - _heights.last).clamp(0.0, SheetTuning.stretchLimit);

  double _dockFor(double h) {
    final docked = dockedIndex;
    if (docked == null) return 0;
    final top = _heights[docked];
    if (_dragFrom != null) {
      final ref = _floatingBelowDocked;
      if (top <= ref) return 1;
      final shortened = top - SheetTuning.dragDockShortfall;
      final end = shortened > ref ? shortened : top;
      return ((h - ref) / (end - ref)).clamp(0.0, 1.0);
    }
    if (_toDocked) {
      final span = top - _heightStart;
      if (span <= 1e-6) return 1;
      return (_dockStart + (1 - _dockStart) * (h - _heightStart) / span).clamp(
        0.0,
        1.0,
      );
    }
    final span = _heightStart - _heights[_index];
    if (span.abs() <= 1e-6) return 0;
    return (_dockStart * (h - _heights[_index]) / span).clamp(0.0, 1.0);
  }

  double _scaleFor(double dock) => 1 - 2 * inset / width * (1 - dock);

  double _shiftFor(double h, double dock) {
    final reference = dock > 0 ? _floating : h;
    return inset * (reference / width - 1) * (1 - dock);
  }

  /// The uniform scale of the sheet, the swell of a touch
  /// included.
  double get scale => _scaleAt(now);

  double _scaleAt(double t) => _scaleFor(_dockAt(t)) * _pressScaleAt(t);

  /// The ratio of the sheet's vertical to its horizontal scale: 1 at
  /// rest, above 1 while a drag stretches the sheet. The drawn
  /// height is the [scale]d height times its square root, the drawn width
  /// the [scale]d width over it, about the bottom edge. A drag that
  /// catches the sheet while a stretch still returns stretches it on top
  /// of that remainder, which keeps returning on
  /// [SheetTuning.stretchSpring].
  double get stretch => _stretchAt(now);

  double _stretchAt(double t) =>
      1 +
      _stretch.valueAt(t) +
      (_stretching
          ? SheetTuning.stretchPerPoint * _travel +
                SheetTuning.stretchLagGain * _lag.valueAt(t)
          : 0);

  void _holdStretch(double t) {
    if (!_stretching) return;
    _stretch.snap(t, _stretchAt(t) - 1);
    _stretching = false;
  }

  void _releaseStretch(double t) {
    _holdStretch(t);
    _stretch.retarget(t, 0);
  }

  double _driftAt(double t) => inset * (1 - _dockAt(t)) * _drift.valueAt(t);

  double _shiftAt(double t) => _shiftFor(_height.valueAt(t), _dockAt(t));

  /// How strongly the sheet dims what is behind it, 0 to 1;
  /// multiply by the opacity of the black dimming behind a dimmed detent
  /// (0.2).
  double get dimming {
    final t = now;
    final hidden = hiddenOffset;
    final shown = hidden <= 0
        ? 1.0
        : (1 - _offset.valueAt(t) / hidden).clamp(0.0, 1.0);
    final undimmed = undimmedIndex;
    if (undimmed == null) return shown;
    if (undimmed >= _heights.length - 1) return 0;
    final lo = _heights[undimmed];
    final hi = _heights[undimmed + 1];
    final f = hi <= lo
        ? 1.0
        : ((_height.valueAt(t) - lo) / (hi - lo)).clamp(0.0, 1.0);
    return shown * f;
  }

  SheetLayout? _layout;
  List<int> _order = const [];
  bool _opened = false;
  bool _left = false;
  // The velocity, down in pixels per second, of a back gesture that
  // committed: the leave that follows continues from it.
  double? _backVelocity;

  void _restAt(double t, int index) {
    _toDocked = index == dockedIndex;
    _dockStart = _toDocked ? 1 : 0;
    _radiusStart = _toDocked ? dockedRadius : floatingRadius;
    _heightStart = _heights[index];
    _floating = _toDocked ? _floatingBelowDocked : _heights[index];
    _offset.snap(t, hiddenOffset);
  }

  /// Whether a [layout] or the constructor gave the sheet its heights.
  bool get isLaidOut => _heights.isNotEmpty;

  /// Whether the presentation was told to leave.
  bool get hasLeft => _left;

  /// The latest [layout], null before the first.
  SheetLayout? get lastLayout => _layout;

  /// The position in the layout's detents of the detent at [index], the
  /// index of [heights] that [index] and [SheetDetentChanged] count in.
  int detentAt(int index) => _order[index];

  /// The index of [heights] of the layout's detent at position [detent],
  /// -1 before the first [layout].
  int indexOfDetent(int detent) => _order.indexOf(detent);

  /// Tells the sheet its [layout] at [t].
  ///
  /// The first rests the sheet hidden at the selected detent and presents
  /// it when it was opened and has not left. Each layout resolves the
  /// detents with the keyboard (UIKit's, simulator capture): every detent
  /// grows by the keyboard's height up to the maximum, and the sheet moves
  /// to its largest detent while the keyboard shows and back to the
  /// selected one when it hides, neither reported as a [SheetDetentChanged].
  /// Otherwise a later layout keeps the detent the sheet rests at or heads
  /// to; one that changes nothing but the selected detent does nothing.
  void layout(double t, SheetLayout layout) {
    final last = _layout;
    if (last != null && layout.copyWith(selected: last.selected) == last) {
      return;
    }
    _layout = layout;
    final raised = layout.keyboard > 0;
    final (:heights, :order, :docked, :undimmed) = layout.resolve();
    _order = order;
    final index = raised
        ? order.length - 1
        : order.indexOf(math.max(0, layout.detents.indexOf(layout.selected)));
    if (last == null) {
      _heights = heights;
      width = layout.size.width;
      _fullHeight = layout.fullHeight;
      _dockedIndex = docked;
      _undimmedIndex = undimmed;
      _index = index;
      _restAt(t, index);
      _height.snap(t, heights[index]);
      _fill.snap(t, _toDocked ? 1 : 0);
      if (_opened && !_left) present(t);
      return;
    }
    relayout(
      t,
      heights,
      layout.size.width,
      fullHeight: layout.fullHeight,
      index: raised == last.keyboard > 0 ? null : index,
    );
  }

  /// Replaces the detent [heights], the container [width] and the
  /// [fullHeight] after a layout change, keeping the selected detent, or
  /// moving to [index] without reporting it through `onDetentChanged`: the
  /// detent a keyboard raises the sheet to is not a selection.
  void relayout(
    double t,
    List<double> heights,
    double width, {
    double? fullHeight,
    int? index,
  }) {
    advance(t);
    this.width = width;
    _heights = List<double>.of(heights);
    _fullHeight = fullHeight ?? heights.last;
    _index = (index ?? _index).clamp(0, heights.length - 1);
    if (_dragFrom == null) _transition(t, _index);
  }

  @override
  PresenceStatus get presence {
    if (!isLaidOut) return _opened && !_left ? .opening : .hidden;
    if (_dismissing) return isDismissed ? .hidden : .leaving;
    return isSettled ? .shown : .opening;
  }

  @override
  void open(double t) {
    _opened = true;
    if (isLaidOut && !_left) present(t);
  }

  @override
  bool leave(double t, DismissTrigger trigger) {
    _left = true;
    if (!isLaidOut) return false;
    final back = _backVelocity;
    _backVelocity = null;
    if (back != null) {
      dismiss(t, velocity: back);
      return true;
    }
    if (isDragging) dragCancel(t);
    if (!_dismissing) dismiss(t);
    return true;
  }

  /// Slides the sheet in from below the screen to its detent.
  ///
  /// A floating sheet slides in with its frame at the container's leading
  /// edge and drifts sideways to its inset on the same spring, as UIKit's
  /// does.
  void present(double t) {
    advance(t);
    _dismissing = false;
    final hidden = hiddenOffset;
    if (hidden > 0) {
      _drift.snap(t, (_offset.valueAt(t) / hidden).clamp(0.0, 1.0));
      _drift.retarget(t, 0);
    }
    _offset.retarget(t, 0, spring: SheetTuning.spring);
  }

  /// Slides the sheet out below the screen, moving down at [velocity]
  /// pixels per second from where it is.
  void dismiss(double t, {double velocity = 0}) {
    advance(t);
    _dragFrom = null;
    _dismissing = true;
    _releaseStretch(t);
    if (velocity != 0) _offset.setVelocity(t, velocity);
    _offset.retarget(t, hiddenOffset, spring: SheetTuning.spring);
  }

  // How far down the back gesture's full progress takes the sheet: from
  // where it rests to below the screen.
  double _backRange = 0;

  /// Android's predictive back gesture starts at [t]: it drags the sheet
  /// down from where it rests, as a finger dragging it to its dismissal
  /// does, without the swell of a touch.
  @override
  void backStarted(double t) {
    if (!isLaidOut) return;
    advance(t);
    dismissible = true;
    _backRange = math.max(1, _top - _heights.first + hiddenOffset);
    dragStart(t, 0);
  }

  /// The back gesture stands at [progress], 0 where it started and 1 with
  /// the sheet below the screen.
  @override
  void backMoved(double t, double progress) {
    if (!isLaidOut) return;
    dragUpdate(t, progress.clamp(0.0, 1.0) * _backRange);
  }

  /// The back gesture ends: a commit's [velocity], its progress per
  /// second, carries the sheet down through the leave that follows; a
  /// cancel returns the sheet to its detent.
  @override
  void backEnded(double t, {required bool commits, required double velocity}) {
    if (!isLaidOut) return;
    if (commits) {
      _backVelocity = velocity * _backRange;
    } else {
      dragCancel(t);
    }
  }

  /// Animates to detent [index], as UIKit's animateChanges does.
  void animateTo(double t, int index) {
    advance(t);
    _transition(t, index.clamp(0, _heights.length - 1), byUser: false);
  }

  /// Moves to detent [index] the user picked without a drag, from the
  /// keyboard or a screen reader: reported as a tap on the grabber's is.
  void pick(double t, int index) {
    advance(t);
    if (_dismissing || _dragFrom != null) return;
    _transition(t, index.clamp(0, _heights.length - 1));
  }

  void _transition(
    double t,
    int index, {
    double? velocity,
    bool byUser = true,
  }) {
    final h = _height.valueAt(t);
    final d = _dockFor(h);
    final radius = _bottomRadiusAt(t);
    final dragged = _dragFrom != null;
    _dragFrom = null;
    _releaseStretch(t);
    final changed = index != _index;
    _index = index;
    _toDocked = index == dockedIndex;
    _dockStart = d;
    _radiusStart = radius;
    if (changed || dragged) _squareAtRest = true;
    _heightStart = h;
    _fillToward(t, _toDocked ? 1 : 0);
    if (!_toDocked) {
      _floating = _heights[index];
    } else if (d <= 0) {
      _floating = h;
    }
    if (velocity != null) _height.setPresentation(t, h, velocity: velocity);
    _height.retarget(t, _heights[index]);
    if (changed) _events.add(SheetDetentChanged(index, byUser: byUser));
  }

  double get _top => _height.valueAt(now) - _offset.valueAt(now);

  void _fillToward(double t, double target) {
    if (dockedIndex == null || _fill.target == target) return;
    _fill.retarget(t, target);
  }

  /// A finger touched the sheet: a sheet floating at the touch swells,
  /// and keeps its swell through a drag the touch turns into; a sheet
  /// docked at the touch does not swell for it, even once a drag undocks
  /// it.
  void press(double t) {
    advance(t);
    if (_dockAt(t) >= 1) return;
    at(
      t + SheetTuning.pressDelay,
      (s) => _press.retarget(s, SheetTuning.pressScale),
      slot: _pressSlot,
    );
  }

  /// The touch ended without a drag: the swell goes.
  void unpress(double t) {
    advance(t);
    _letGo(t);
  }

  void _letGo(double t) {
    unschedule(_pressSlot);
    _press.retarget(t, 1);
  }

  /// A tap on the grabber band: cycles to the next detent, back to the
  /// smallest after the largest.
  void tapGrabber(double t) {
    advance(t);
    if (_heights.length < 2 || _dismissing) return;
    at(t + SheetTuning.grabberTapDelay, (s) {
      if (_dragFrom == null && !_dismissing) {
        _transition(s, (_index + 1) % _heights.length);
      }
    });
  }

  double _pressScaleAt(double t) =>
      1 + (_press.valueAt(t) - 1) * math.sqrt(1 - _dockAt(t));

  /// A finger started dragging the sheet at screen position [y].
  void dragStart(double t, double y) {
    advance(t);
    _holdStretch(t);
    if (_dockAt(t) < 1) {
      _stretch.retarget(t, 0);
      _stretching = true;
      _travel = 0;
      _travelAt = t;
      _travelVelocity = 0;
      _lag.snap(t, 0);
    }
    _floating = _floatingBelowDocked;
    _dragFrom = y;
    final top = _top;
    final largest = _heights.last;
    final room = _rubberRoom;
    _dragTop = room > 0
        ? RubberBand(
            double.negativeInfinity,
            largest,
            dimension: room,
          ).unshow(top)
        : top;
    _height.snap(t, _height.valueAt(t));
    _offset.snap(t, _offset.valueAt(t));
  }

  /// The finger moved to screen position [y].
  void dragUpdate(double t, double y) {
    advance(t);
    final from = _dragFrom;
    if (from == null || _released) return;
    if (_stretching) _track(t, (y - from).abs());
    final raw = _dragTop - (y - from);
    final largest = _heights.last;
    final top = RubberBand(
      double.negativeInfinity,
      largest,
      dimension: _rubberRoom,
    ).show(raw);
    final lowest = _heights.first;
    if (top >= lowest) {
      _height.snap(t, top);
      _offset.snap(t, 0);
      _fillToward(
        t,
        _dockFor(top) >= SheetTuning.backgroundSwitch ? 1 : 0,
      );
    } else {
      final below = lowest - top;
      _height.snap(t, lowest);
      _offset.snap(
        t,
        dismissible
            ? below
            : -RubberBand(
                lowest,
                double.infinity,
                dimension: SheetTuning.refusedPullExtent,
              ).stretch(top),
      );
    }
  }

  void _track(double t, double travel) {
    if (t > _travelAt) {
      final v = (travel - _travel) / (t - _travelAt);
      _lag.setVelocity(t, _lag.velocityAt(t) + v - _travelVelocity);
      _travelVelocity = v;
      _travelAt = t;
    }
    _travel = travel;
  }

  /// The finger let go, moving at [velocity] pixels per second (positive
  /// down).
  void dragEnd(double t, double velocity) {
    advance(t);
    if (_dragFrom == null || _released) return;
    _holdStretch(t);
    _released = true;
    at(t + SheetTuning.releaseDelay, (s) {
      _letGo(s);
      _released = false;
      _settle(s, velocity);
    });
  }

  bool _released = false;

  void _settle(double t, double velocity) {
    if (_dragFrom == null) return;
    _releaseStretch(t);
    const gain = SheetTuning.releaseVelocityGain;
    const projection = Projection(rate: SheetTuning.projection);
    final below = _offset.valueAt(t);
    if (below > 0) {
      final hidden = hiddenOffset;
      final dismiss = ProjectionExit(
        threshold: hidden / 2,
        flickVelocity: SheetTuning.dismissVelocity,
      );
      if (dismissible &&
          dismiss.passes(projection.landing(below, velocity), velocity)) {
        _dragFrom = null;
        _dismissing = true;
        final flicked = velocity > 0;
        _offset.setVelocity(
          t,
          flicked ? velocity * SheetTuning.flickDismissVelocityGain : 0,
        );
        _offset.retarget(
          t,
          hidden,
          spring: flicked ? SheetTuning.flickDismissSpring : SheetTuning.spring,
        );
        _events.add(const SheetDismissed());
        return;
      }
      if (!dismissible &&
          below >
              SheetTuning.refusedPullExtent * SheetTuning.dismissAttemptShare) {
        _events.add(const SheetDismissRefused());
      }
      _offset.setVelocity(t, velocity * gain);
      _offset.retarget(t, 0, spring: SheetTuning.spring);
      _transition(t, 0, velocity: 0);
      return;
    }
    final ProjectionStop(:index) = projection.choose(
      _height.valueAt(t),
      -velocity,
      stops: _heights,
    ) as ProjectionStop;
    _offset.retarget(t, 0, spring: SheetTuning.spring);
    _transition(t, index, velocity: -velocity * gain);
  }

  /// The drag was cancelled; the sheet returns to its detent.
  void dragCancel(double t) {
    advance(t);
    if (_dragFrom == null) return;
    _released = false;
    _releaseStretch(t);
    _offset.retarget(t, 0, spring: SheetTuning.spring);
    _transition(t, _index);
  }

  /// The sheet's visible rect in a container [containerHeight]
  /// pixels tall, transforms applied.
  Rect visibleRect(double containerHeight) {
    final t = now;
    final h = _height.valueAt(t);
    final s = _scaleAt(t);
    final bottom =
        containerHeight + (s - 1) * h / 2 + _shiftAt(t) + _offset.valueAt(t);
    final k = math.sqrt(math.max(_stretchAt(t), 0.5));
    final w = width * s / k;
    final x = -_driftAt(t);
    return Rect.fromLTRB(
      (width - w) / 2 + x,
      bottom - h * s * k,
      (width + w) / 2 + x,
      bottom,
    );
  }
}

import 'dart:math' as math;
import 'dart:ui';

import 'package:apple_liquid_glass/src/motions/flex_integrator.dart';
import 'package:apple_liquid_glass/src/motions/flex_interaction.dart';
import 'package:apple_liquid_glass/src/motions/flex_spec.dart';
import 'package:apple_liquid_glass/src/motions/glass_press.dart';
import 'package:apple_liquid_glass/src/motions/lens_tuning.dart';
import 'package:apple_liquid_glass/src/motions/lens_values.dart';
import 'package:kinesis/motion.dart';
import 'package:meta/meta.dart';

/// The motion of a liquid selection lens: a pure function of the touches
/// it is fed and the time it is advanced to.
///
/// The lens frame rides three motion values on two springs: the travel
/// spring for the center, and the lift spring for the lift and for width
/// changes between slots.
/// On top of that runs UIKit's closed deformation loop: every frame the
/// visible center is filtered three times, the rate of change of its
/// speed becomes a drift of the lens's trailing edge plus a matching
/// stretch, and both follow their targets on a presentation spring. The
/// leading edge therefore rides the travel spring exactly. The loop steps
/// on a fixed [frameRate] in motion time, so the deformation is the same
/// on any display and under any time dilation.
///
/// A control that flexes ([LensTuning.chromeFlexes]) carries its own
/// flex of [chromeSize] under the finger, read as [chrome].
///
/// Feed pointer events with their timestamps and read [center], [size],
/// [scaleX] and [scaleY] at [now]: on screen the clock advances the motion,
/// in a test [advance] does. All lengths are pixels along the track, all
/// times seconds.
///
/// Every part rests within [MotionRest]: a scale over the lens's extent on
/// its own axis (the lifted width along the track, which holds while it
/// lands, and the current height across it), the lift over its largest
/// growth. The deformation loop sleeps once the lens is undeformed and
/// still. A finger held still counts: the lens rests lifted under it until
/// the finger moves or lifts. Each selection goes to [onEvent] as the
/// command that makes it runs.
final class LensMotion extends Motion {
  /// Creates a lens resting in [selected] among [slots].
  /// Empty slots have selection -1 and ignore input; other indices clamp
  /// to the available slots.
  ///
  /// [startDelay] overrides the tuning's delay between a selecting touch
  /// and the start of the motion. [chromeSize] is the size of the whole
  /// control, which flexes when the tuning says so.
  LensMotion({
    @internal required this.tuning,
    required List<LensSlot> slots,
    required int selected,
    required this.height,
    this.frameRate = 120,
    Size chromeSize = Size.zero,
    double? startDelay,
    this.onEvent,
  }) : startDelay = startDelay ?? tuning.startDelay,
       _slots = List.of(slots),
       _selected = _index(selected, slots.length),
       _restWidth = slots.isEmpty
           ? 0
           : slots[_index(selected, slots.length)].width {
    final slot = _slot;
    _travel = own(
      MotionValue<double>(slot.center, spring: tuning.travelSpring),
      rest: _length,
    );
    _width = own(
      MotionValue<double>(slot.width, spring: tuning.liftSpring),
      rest: _length,
    );
    _lift = own(
      MotionValue<double>(0, spring: tuning.liftSpring),
      rest: _liftRest,
    );
    _chrome = own(
      GlassPress(
        size: tuning.chromeFlexes ? chromeSize : Size.zero,
        law: FlexLaw(activationDelay: tuning.chromeLag),
      ),
    );
    _drift = own(
      MotionValue<double>(0, spring: tuning.presentationSpring),
      rest: _length,
    );
    _scaleX = own(
      MotionValue<double>(1, spring: tuning.presentationSpring),
      rest: _scaleXRest,
    );
    _scaleY = own(
      MotionValue<double>(1, spring: tuning.presentationSpring),
      rest: _scaleYRest,
    );
    _loop = own(_LensLoop(this, rate: frameRate));
    _previousVisible = slot.center;
  }

  /// Creates the lens of a UISegmentedControl resting in [selected]
  /// among [slots]; the other parameters are those of [LensMotion.new].
  LensMotion.segmented({
    required List<LensSlot> slots,
    required int selected,
    required double height,
    double frameRate = 120,
    Size chromeSize = Size.zero,
    double? startDelay,
    void Function(LensEvent event)? onEvent,
  }) : this(
         tuning: LensTuning.segmented,
         slots: slots,
         selected: selected,
         height: height,
         frameRate: frameRate,
         chromeSize: chromeSize,
         startDelay: startDelay,
         onEvent: onEvent,
       );

  /// Creates the lens of a floating UITabBar resting in [selected] among
  /// [slots]; the other parameters are those of [LensMotion.new].
  LensMotion.tabBar({
    required List<LensSlot> slots,
    required int selected,
    required double height,
    double frameRate = 120,
    Size chromeSize = Size.zero,
    double? startDelay,
    void Function(LensEvent event)? onEvent,
  }) : this(
         tuning: LensTuning.tabBar,
         slots: slots,
         selected: selected,
         height: height,
         frameRate: frameRate,
         chromeSize: chromeSize,
         startDelay: startDelay,
         onEvent: onEvent,
       );

  /// The measured behavior this lens reproduces.
  @internal
  final LensTuning tuning;

  /// The flex of a control that no finger touches: [chrome] of a lens
  /// while it rests.
  static const FlexValues chromeAtRest = FlexInteraction.rest;

  /// The resting height of the lens.
  final double height;

  /// The frames per second of motion time the deformation loop steps at:
  /// 120 for a ProMotion display, 60 for a 60 Hz one.
  final double frameRate;

  /// Seconds between a selecting touch and the start of the motion.
  final double startDelay;

  /// Hears each selection the lens makes.
  final void Function(LensEvent event)? onEvent;

  // Under Reduce Motion (the motion's traits) the lens never lifts, as
  // UIKit's lens does not (read from UIKit, notes private), and travels on
  // the tuning's reducedMotionTravelSpring or not at all. Its deformation
  // and the control's flex staying off are approximations, not recorded.
  bool get _reduced => traits.reduceMotion;

  bool get _slides => !_reduced || tuning.reducedMotionTravelSpring != null;

  Spring get _travelSpring => _reduced
      ? tuning.reducedMotionTravelSpring ?? tuning.travelSpring
      : tuning.travelSpring;

  void _travelTo(double t, LensSlot slot) {
    if (_slides) {
      _travel.retarget(t, slot.center, spring: _travelSpring);
      _width.retarget(t, slot.width);
    } else {
      _travel.snap(t, slot.center);
      _width.snap(t, slot.width);
    }
    _loop.wake(t);
  }

  static double _length() => MotionRest.length;

  double _liftRest() =>
      MotionRest.length /
      math.max(math.max(tuning.liftWidth, tuning.liftHeight), 1);

  double _scaleXRest() => MotionRest.scale(_restWidth + tuning.liftWidth);

  double _scaleYRest() => MotionRest.scale(size.height);

  List<LensSlot> _slots;
  int _selected;
  late final MotionValue<double> _travel;
  late final MotionValue<double> _width;
  late final MotionValue<double> _lift;
  late final GlassPress _chrome;
  _Pointer? _chromePointer;
  late final MotionValue<double> _drift;
  late final MotionValue<double> _scaleX;
  late final MotionValue<double> _scaleY;
  late final _LensLoop _loop;
  double _restWidth;

  final FlexIntegrator _flex = FlexIntegrator();
  Size? _loupeSize;
  FlexSpec _loupe = FlexSpec.smallLoupe;
  double? _previousVisible;
  bool _flag = false;

  _Pointer? _pointer;

  /// Whether the slot at an index can be selected; null makes every slot
  /// selectable.
  ///
  /// A touch landing on a slot that cannot be selected neither selects
  /// nor lifts the lens, but still swells the control (a disabled
  /// UITabBarItem on an iPhone 16 Pro, iOS 27.0.1: the bar grows under
  /// the finger, the lens stays). A drag released over such a slot
  /// returns to the selected one.
  bool Function(int index)? isSelectable;

  bool _selectable(int index) => isSelectable?.call(index) ?? true;

  /// The index of the selected slot, or -1 when there are no slots.
  int get selected => _selected;

  static int _index(int index, int count) =>
      count == 0 ? -1 : index.clamp(0, count - 1);

  LensSlot _slotFor(int index) => _slots.isEmpty
      ? (center: 0, width: 0)
      : _slots[_index(index, _slots.length)];

  LensSlot get _slot => _slotFor(_selected);

  /// The slots the lens can rest in.
  List<LensSlot> get slots => _slots;

  /// Replaces the slots, snapping the lens to the selected one.
  set slots(List<LensSlot> value) {
    _slots = List.of(value);
    _selected = _index(_selected, _slots.length);
    final slot = _slot;
    _travel.snap(now, slot.center);
    _width.snap(now, slot.width);
    _restWidth = slot.width;
    if (_slots.isEmpty) {
      unscheduleAll();
      _pointer = null;
      _flag = false;
      _lift.retarget(now, 0);
      _chrome.release(now);
    }
    _drift.snap(now, 0);
    _scaleX.snap(now, 1);
    _scaleY.snap(now, 1);
    _previousVisible = slot.center;
    _flex.reset(slot.center);
  }

  /// Replaces the slots after a change of the items around the lens, with
  /// [selected] its slot among them, at time [t].
  ///
  /// [shift] is how far the lens's coordinates moved under it along the
  /// track: the lens keeps its place on screen through it. On [spring] it
  /// then moves to its slot and takes the slot's width, as the items that
  /// stay do (not measured: UIKit's animated `insertSegment` and
  /// `setItems` were not captured); with no spring, an immediate one or a
  /// finger on the control, it snaps there as [slots] does.
  void reslot(
    double t,
    List<LensSlot> slots,
    int selected, {
    Spring? spring,
    double shift = 0,
  }) {
    advance(t);
    _selected = _index(selected, slots.length);
    if (spring == null ||
        spring.isImmediate ||
        _pointer != null ||
        slots.isEmpty ||
        _slots.isEmpty) {
      this.slots = slots;
      return;
    }
    _slots = List.of(slots);
    final slot = _slot;
    _restWidth = slot.width;
    if (shift != 0) {
      final velocity = _travel.velocityAt(t);
      _travel.snap(t, _travel.valueAt(t) + shift);
      _travel.setVelocity(t, velocity);
      _previousVisible = _visible(t);
      _flex.reset(_visible(t));
    }
    _travel.retarget(t, slot.center, spring: spring);
    _width.retarget(t, slot.width, spring: spring);
    _loop.wake(t);
  }

  /// The center the travel spring carries, before the deformation drift.
  double get travelCenter => _travel.valueAt(now);

  /// The visible center along the track, drift included.
  double get center => _visible(now);

  double _visible(double t) => _travel.valueAt(t) + _drift.valueAt(t);

  /// The lens bounds before the deformation scale: rest size plus lift.
  ({double width, double height}) get size {
    final lift = _lift.valueAt(now);
    return (
      width: _width.valueAt(now) + tuning.liftWidth * lift,
      height: height + tuning.liftHeight * lift,
    );
  }

  /// The deformation scale along the track.
  double get scaleX => _scaleX.valueAt(now);

  /// The deformation scale across the track.
  double get scaleY => _scaleY.valueAt(now);

  /// The lift progress, 0 resting and 1 fully lifted.
  double get lift => _lift.valueAt(now);

  /// The size of the whole control, which flexes under a finger when the
  /// tuning says so ([LensTuning.chromeFlexes]).
  Size get chromeSize => _chrome.size;

  set chromeSize(Size value) {
    if (tuning.chromeFlexes) _chrome.size = value;
  }

  /// The flex of the whole control now: its scales about its center and
  /// its drift along and across the track, [chromeAtRest] exactly while
  /// it rests. The control shows the drift times the scale
  /// ([GlassPress.lean]).
  FlexValues get chrome => _chrome.values;

  /// Whether the finger currently drags the lens.
  bool get isDragging => _pointer?.dragging ?? false;

  /// The index of the slot under [x]: where slots overlap, as a tab bar's
  /// buttons do, the selected one if it is among them, else the first (read
  /// from UIKit; a lift 47 points from one tab and 38 from the next selected
  /// the first on an iPhone 16 Pro). Off every slot, the nearest.
  int slotAt(double x) {
    bool under(LensSlot slot) => (slot.center - x).abs() <= slot.width / 2;
    if (_selected >= 0 &&
        _selected < _slots.length &&
        under(_slots[_selected])) {
      return _selected;
    }
    for (var i = 0; i < _slots.length; i++) {
      if (under(_slots[i])) return i;
    }
    var best = -1;
    var bestDistance = double.infinity;
    for (var i = 0; i < _slots.length; i++) {
      final distance = (_slots[i].center - x).abs();
      if (distance < bestDistance) {
        best = i;
        bestDistance = distance;
      }
    }
    return best;
  }

  /// A finger touched the track at [x], [y] across it; only the
  /// control's flex reads [y], in the control's own coordinates.
  void pointerDown(double t, double x, {double y = 0}) {
    advance(t);
    if (_slots.isEmpty || _pointer != null) return;
    final index = slotAt(x);
    if (!_selectable(index)) {
      final inert = _Pointer(offset: 0, pressedSelected: false, x: x);
      inert.inert = true;
      _pointer = inert;
      _pressChrome(t, inert, Offset(x, y));
      return;
    }
    final onSelected = index == _selected && _slides;
    final pointer = _Pointer(
      offset: center - x,
      pressedSelected: onSelected,
      x: x,
    );
    _pointer = pointer;
    _pressChrome(t, pointer, Offset(x, y));
    if (onSelected) {
      _flagOn(t);
      final liftAt = t + tuning.pressDelay;
      pointer.unliftNotBefore = t + tuning.pressHang;
      at(liftAt, (s) {
        if (!pointer.cancelled) _raise(s);
      });
    } else if (tuning.selectsOnPointerDown) {
      pointer.pressedSelected = true;
      pointer.offset = 0;
      _selectWithLift(t, index, hold: true);
    }
  }

  /// A finger already on the control at [x], [y] across it takes the lens
  /// from where it rests and starts to drag it, selecting nothing until it
  /// lifts: a finger that slides off a tab bar's minimized circle.
  void pointerDrag(double t, double x, {double y = 0}) {
    advance(t);
    if (_slots.isEmpty || _pointer != null) return;
    final pointer = _Pointer(offset: 0, pressedSelected: true, x: x);
    pointer.dragging = true;
    pointer.unfollowed = true;
    _pointer = pointer;
    _pressChrome(t, pointer, Offset(x, y));
    _flagOn(t);
    pointer.unliftNotBefore = t + tuning.pressHang;
    at(t + tuning.pressDelay, (s) {
      if (!pointer.cancelled) _raise(s);
    });
    _loop.wake(t);
  }

  /// The finger moved to [x], [y] across the track.
  void pointerMove(double t, double x, {double y = 0}) {
    advance(t);
    final pointer = _pointer;
    if (pointer != null && tuning.chromeFlexes) {
      _chrome.pointerMove(t, Offset(x, y));
    }
    if (pointer == null || !pointer.pressedSelected) return;
    pointer.dragging = true;
    pointer.x = x;
    pointer.unfollowed = true;
    _loop.wake(t);
  }

  /// The finger left the track at [x], [y] across it; the slot nearest the
  /// finger wins.
  void pointerUp(double t, double x, {double y = 0}) {
    advance(t);
    final pointer = _pointer;
    _pointer = null;
    if (pointer == null) return;
    if (tuning.chromeFlexes) _chrome.pointerMove(t, Offset(x, y));
    final lands =
        pointer.pressedSelected &&
        !pointer.inert &&
        pointer.unliftNotBefore <= t + tuning.releaseDelay;
    _releaseChrome(
      t,
      pointer,
      lag: lands ? tuning.chromeLandingLag : tuning.chromeReleaseLag,
    );
    if (pointer.inert) return;
    final under = slotAt(x);
    final index = _selectable(under) ? under : _selected;
    if (pointer.pressedSelected) {
      if (index != _selected) _setSelected(index);
      final slot = _slots[_selected];
      _restWidth = slot.width;
      at(t + tuning.releaseDelay, (s) => _travelTo(s, _slotFor(index)));
      final unliftAt = math.max(
        t + tuning.releaseDelay,
        pointer.unliftNotBefore,
      );
      at(unliftAt - tuning.flagLead, (s) => _flag = false);
      at(unliftAt, (s) => _lift.retarget(s, 0));
    } else {
      _selectWithLift(t, index, hold: false);
    }
  }

  /// The touch was cancelled; the lens returns to the selected slot.
  void pointerCancel(double t) {
    advance(t);
    final pointer = _pointer;
    _pointer = null;
    if (pointer == null) return;
    pointer.cancelled = true;
    _releaseChrome(t, pointer, lag: tuning.chromeReleaseLag);
    if (!pointer.pressedSelected) return;
    final slot = _slots[_selected];
    _travelTo(t, slot);
    _restWidth = slot.width;
    _flag = false;
    _lift.retarget(t, 0);
  }

  /// Selects the clamped [index] without a touch: the lens travels without
  /// lifting. With [notify] false, reconciles the parent's selection and
  /// cancels pending touch reactions without raising [LensSelected].
  void select(double t, int index, {bool notify = true}) {
    advance(t);
    if (_slots.isEmpty) return;
    final selected = _index(index, _slots.length);
    if (selected == _selected) return;
    if (!notify) {
      unscheduleAll();
      _flag = false;
      _lift.retarget(t, 0);
      if (_pointer == null) _chrome.release(t);
    }
    _selected = selected;
    if (notify) onEvent?.call(LensSelected(selected));
    final slot = _slots[selected];
    _flex.reset(_previousVisible ?? center);
    _travelTo(t, slot);
    _restWidth = slot.width;
  }

  /// Puts the lens at rest on the clamped [index] at once, without
  /// travel, lift or [LensSelected]: where a control that showed no selection
  /// shows one appear. Cancels a touch and pending reactions.
  void place(double t, int index) {
    advance(t);
    if (_slots.isEmpty) return;
    unscheduleAll();
    _pointer = null;
    _chrome.release(t);
    _flag = false;
    _selected = _index(index, _slots.length);
    _lift.snap(t, 0);
    slots = _slots;
  }

  void _frame(double t) {
    final pointer = _pointer;
    if (pointer != null && pointer.dragging) {
      _follow(t, pointer);
      pointer.unfollowed = false;
    }
    final visible = _visible(t);
    final previous = _previousVisible ?? visible;
    if (_flex.pf != null) {
      _flex.step(previous, _loop.frame);
      _retargetFlex(t);
    }
    _previousVisible = visible;
  }

  // Whether the deformation is still at [t] with nothing to follow:
  // undeformed, its targets at rest, the travel at rest and no move of the
  // finger waiting for the next frame.
  bool _still(double t) {
    if (_pointer?.unfollowed ?? false) return false;
    const length = MotionRest.length;
    final scaleX = _scaleXRest();
    final scaleY = _scaleYRest();
    return _travel.restsAt(t, length) &&
        _drift.target.abs() < length &&
        _drift.restsAt(t, length) &&
        (_scaleX.target - 1).abs() < scaleX &&
        _scaleX.restsAt(t, scaleX) &&
        (_scaleY.target - 1).abs() < scaleY &&
        _scaleY.restsAt(t, scaleY);
  }

  void _restDeformation(double t) {
    _drift.snap(t, 0);
    _scaleX.snap(t, 1);
    _scaleY.snap(t, 1);
    _previousVisible = _travel.target;
    _flex.reset(_travel.target);
  }

  void _retargetFlex(double t) {
    if (_reduced) {
      _drift.retarget(t, 0);
      _scaleX.retarget(t, 1);
      _scaleY.retarget(t, 1);
      return;
    }
    final width = _restWidth;
    if (width <= 0) return;
    final size = _flag
        ? Size(width + tuning.liftWidth, height + tuning.liftHeight)
        : Size(width, height);
    if (size != _loupeSize) {
      _loupeSize = size;
      _loupe = FlexSpec.loupeForSize(size);
    }
    final v = FlexInteraction.withMovement(
      FlexInteraction.rest,
      spec: _loupe,
      size: size,
      acceleration: Offset(_flex.af, 0),
      velocity: Offset(_flex.vf, 0),
    );
    _drift.retarget(t, v.driftX);
    _scaleX.retarget(t, v.scaleX);
    _scaleY.retarget(t, v.scaleY);
  }

  void _follow(double t, _Pointer pointer) {
    final first = _slots.first.center;
    final last = _slots.last.center;
    final u = pointer.x + pointer.offset;
    final (limit, stiffness) = tuning.rubberBand;
    final target = RubberBand(
      first,
      last,
      dimension: limit,
      coefficient: stiffness,
    ).show(u);
    _travel.retarget(
      t,
      target,
      spring: _reduced
          ? tuning.reducedMotionTravelSpring ?? tuning.followSpring
          : tuning.followSpring,
    );
    final under = slotAt(_travel.valueAt(t));
    if (_slots[under].width != _width.target) {
      _width.retarget(t, _slots[under].width);
      _restWidth = _slots[under].width;
    }
  }

  void _selectWithLift(double t, int index, {required bool hold}) {
    final from = _slots[_selected].center;
    if (index != _selected) _setSelected(index);
    final slot = _slots[index];
    _flagOn(t);
    final start = t + startDelay;
    final distance = (slot.center - from).abs();
    final hang =
        tuning.hangTime +
        tuning.hangTimePerPixel *
            math.max(0, distance - tuning.hangReferenceDistance);
    _restWidth = slot.width;
    at(start, (s) {
      _travelTo(s, _slotFor(index));
      _raise(s);
    });
    final landing = (tuning.hangFromTouch ? t : start) + hang;
    if (hold) {
      _pointer?.unliftNotBefore = landing;
    } else {
      at(landing - tuning.flagLead, (s) => _flag = false);
      at(landing, (s) => _lift.retarget(s, 0));
    }
  }

  void _flagOn(double t) {
    _flag = true;
    _flex.reset(_previousVisible ?? center);
  }

  void _pressChrome(double t, _Pointer pointer, Offset at) {
    if (!tuning.chromeFlexes) return;
    _chromePointer = pointer;
    pointer.swellsAt = t + tuning.chromeLag;
    _chrome.pointerDown(t, at);
  }

  void _releaseChrome(double t, _Pointer pointer, {required double lag}) {
    if (!tuning.chromeFlexes) return;
    at(math.max(t + lag, pointer.swellsAt), (s) {
      if (identical(_chromePointer, pointer)) _chrome.release(s);
    });
  }

  void _raise(double t) => _lift.retarget(t, _reduced ? 0 : 1);

  void _setSelected(int index) {
    _selected = index;
    onEvent?.call(LensSelected(index));
  }
}

/// Steps the lens's deformation loop at its frame rate while the lens
/// travels, deforms or follows a finger; at rest it snaps the lens flat
/// onto its travel and primes the filter there.
final class _LensLoop extends MotionLoop {
  _LensLoop(this._lens, {required super.rate});

  final LensMotion _lens;

  @override
  bool step(double t) {
    _lens._frame(t);
    return !_lens._still(t);
  }

  @override
  void restFrom(double t) {
    super.restFrom(t);
    _lens._restDeformation(_lens.now);
  }
}

class _Pointer {
  _Pointer({
    required this.offset,
    required this.pressedSelected,
    required this.x,
  });

  double offset;
  bool pressedSelected;
  bool dragging = false;
  bool cancelled = false;
  bool inert = false;
  double x;
  double unliftNotBefore = 0;
  double swellsAt = 0;

  // A move the lens has not followed yet: the next frame follows it.
  bool unfollowed = false;
}

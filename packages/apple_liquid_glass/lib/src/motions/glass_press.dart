import 'dart:math' as math;
import 'dart:ui';

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/src/motions/flex_interaction.dart';
import 'package:apple_liquid_glass/src/motions/flex_spec.dart';
import 'package:apple_liquid_glass/src/motions/touch_glow.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/motion.dart';
import 'package:meta/meta.dart';

/// How a [GlassPress] takes a touch: whether it stretches after a dragging
/// finger and glows, and how late it takes the touch up.
@immutable
final class FlexLaw {
  /// Creates a law.
  const FlexLaw({
    this.stretches = true,
    this.glows = false,
    this.activationDelay = 0,
    this.touchDelay = 0,
  });

  /// A glass button's: it stretches, glows and takes every touch
  /// [GlassPress.touchDelay] after its stamp.
  static const button = FlexLaw(glows: true, touchDelay: GlassPress.touchDelay);

  /// Whether a dragging finger stretches the surface and shifts it after
  /// the finger; without it the flex only lifts.
  final bool stretches;

  /// Whether the press carries the touch glow.
  final bool glows;

  /// Seconds between the flex taking up a touch and it following the
  /// finger.
  final double activationDelay;

  /// Seconds between a touch's own stamp and the flex taking it up: the
  /// touch-down, every move and the release.
  final double touchDelay;
}

/// UIKit's flex interaction on one glass surface: the lift, the stretch
/// and shift toward a finger that drags, and the touch glow.
///
/// The tuning comes from the surface's size ([FlexSpec.forSize]). A touch
/// scales the whole surface by [FlexSpec.liftScaleFor], the lift over its
/// long side; the press rides the tracking spring, the release the scale
/// spring, so a small button rings below its size while a wide one barely
/// does. The surface stays lifted for the whole touch, even far outside. A
/// finger that drags stretches it along the drag, narrows it across and
/// shifts it toward the finger: a quarter as much per pixel inside the
/// surface as beyond its edge, over the spec's stretch threshold. With
/// [FlexLaw.glows] it glows by [TouchGlowMotion], the glow measured on the
/// tab bar and the open menu, with the peaks of its spec, a
/// [TouchGlowMotion.buttonDiameter] spot and [FlexLaw.touchDelay] as its
/// rise lag: the glow rises as the flex takes up the touch.
///
/// The flex takes up every touch [FlexLaw.touchDelay] after the touch's
/// own stamp, as UIKit's button does; whether the surface is pressed
/// ([isPressed]) follows the touch at once. A tap that
/// lifts sooner shows no glow, as the tab bar's law shows none for a tap
/// under its rise lag; the menu's least lit time
/// ([TouchGlowMotion.minimumLit]) is not measured on a button.
///
/// As a [PointerFollower] it takes the touch in its region's box, whose size
/// it takes at the touch-down.
///
/// Under Reduce Motion (the motion's [Motion.traits]) the surface still
/// glows but never lifts, stretches or shifts. This approximates the
/// platform's behavior; it is not measured.
///
/// Times are seconds and positions pixels in the surface's own space. The
/// channels rest within a tenth of a pixel over the long side and the glow
/// within a visible opacity step; a finger held still counts, so a held
/// surface stops asking for frames once its lift and glow are in place.
final class GlassPress extends Motion implements PointerFollower {
  /// Creates the press of a surface of [size] at rest, taking touches by
  /// [law].
  GlassPress({Size size = Size.zero, this.law = FlexLaw.button})
    : _size = size,
      _spec = FlexSpec.forSize(size);

  /// Creates the press of a search field of [size]: it lifts like a glass
  /// button of its size [searchDelay] after the contact. No drag on it was
  /// measured, so it does not stretch.
  GlassPress.search({Size size = Size.zero})
    : this(
        size: size,
        law: const FlexLaw(stretches: false, activationDelay: searchDelay),
      );

  /// The time from a touch on a search field to the start of its lift
  /// (fitted 0.051 s, rounded to 0.05; the lift itself is the glass
  /// button's).
  static const double searchDelay = 0.05;

  /// Seconds between a touch's own time stamp and a glass button's flex
  /// taking it up: the touch-down, every move and the release.
  ///
  /// UIKit's glass button starts its lift 22.5 - 29.2 ms after the touch's
  /// stamp (median 26.1, iPhone 16 Pro: the last three taps of
  /// `button-glass-44x44-taps` and the five touches on the button in a
  /// scroll view of `tracking/scroll-delay`) and its return 22.1 - 28.3 ms
  /// after the release's (median 26.0, the seven `*-hold800` captures):
  /// delivery 10 - 25 ms, then the frame the flex begins on. Fed this late,
  /// the drag-off and alert lean replays halve their error. The first
  /// touch after the button appears starts 38 - 47 ms after its stamp, the
  /// next display frame coming ~21 ms after the one before instead of 8.3;
  /// that one-time setup is not reproduced.
  static const double touchDelay = 0.026;

  /// How the press takes a touch.
  final FlexLaw law;

  Size _size;
  FlexSpec _spec;

  double _scaleRest() => MotionRest.scale(math.max(_size.width, _size.height));
  static double _length() => MotionRest.length;

  late final _scaleX = own(MotionValue<double>(1), rest: _scaleRest);
  late final _scaleY = own(MotionValue<double>(1), rest: _scaleRest);
  late final _driftX = own(MotionValue<double>(0), rest: _length);
  late final _driftY = own(MotionValue<double>(0), rest: _length);
  late final _glow = own(
    TouchGlowMotion(
      flex: _spec,
      diameter: TouchGlowMotion.buttonDiameter,
      riseLag: law.touchDelay,
    ),
  );

  static const _activation = #activation;

  bool _pressed = false;
  Offset? _down;
  Offset _position = Offset.zero;
  bool _active = false;

  /// The size of the surface at rest.
  Size get size => _size;

  set size(Size value) {
    if (value == _size) return;
    _size = value;
    _spec = FlexSpec.forSize(value);
    if (law.glows) _glow.flex = _spec;
  }

  /// The scale of the fully lifted surface.
  double get liftedScale => _spec.liftScaleFor(_size);

  /// Whether a finger is down on the surface.
  bool get isPressed => _pressed;

  /// Whether the flex follows the finger: from [FlexLaw.activationDelay]
  /// after it takes up the touch until it takes up the release.
  bool get isActive => _active;

  /// Whether the surface rests undeformed: settled with no finger on it.
  bool get isAtRest => !_pressed && isSettled;

  /// The lift: the mean of [scaleX] and [scaleY], which the stretch leaves
  /// alone.
  double get scale => scaleAt(now);

  /// The lift at time [t] as the press stands, its pending reactions not
  /// run: for an owner that samples ahead of its cursor.
  double scaleAt(double t) => (_scaleX.valueAt(t) + _scaleY.valueAt(t)) / 2;

  /// The horizontal scale, lift and drag stretch combined.
  double get scaleX => _scaleX.valueAt(now);

  /// The vertical scale, lift and drag stretch combined.
  double get scaleY => _scaleY.valueAt(now);

  /// How far the surface's center shows shifted toward the finger: the
  /// drift times the scale, as UIKit scales the drifted surface.
  ///
  /// Replays the glass button's drag-off captures to 0.03 pt rms on the
  /// simulator and 0.07 on the device (120 x 44, a 150 pt drag).
  Offset get lean =>
      Offset(_driftX.valueAt(now) * scaleX, _driftY.valueAt(now) * scaleY);

  /// The flex's four channels.
  FlexValues get values => (
    scaleX: scaleX,
    scaleY: scaleY,
    driftX: _driftX.valueAt(now),
    driftY: _driftY.valueAt(now),
  );

  /// The touch glow, or null when it shows nothing.
  ///
  /// How bright the spot gets is the glass's own, which the renderer reads
  /// from the surface ([GlassTouchGlow.gainOn]). The press itself is the
  /// same for every glass (UIKit gives the clear configurations no press of
  /// their own, read from UIKit, notes private).
  GlassTouchGlow? get touchGlow => law.glows ? _glow.glow : null;

  @override
  void down(PointerDownInput input) {
    size = input.regionSize;
    pointerDown(input.time, input.position);
  }

  @override
  void move(PointerMoveInput input) => pointerMove(input.time, input.position);

  @override
  void up(PointerUpInput input) => pointerUp(input.time, input.position);

  @override
  void cancel(PointerCancelInput input) => pointerCancel(input.time);

  @override
  void hover(PointerHoverInput input) {}

  /// A finger touched the surface at [position].
  void pointerDown(double t, Offset position) {
    advance(t);
    _pressed = true;
    if (law.glows) _glow.pointerDown(t, position);
    _later(t, (s) => _flexDown(s, position));
  }

  /// The finger moved to [position].
  void pointerMove(double t, Offset position) {
    advance(t);
    if (!_pressed) return;
    if (law.glows) _glow.pointerMove(t, position);
    _later(t, (s) => _flexMove(s, position));
  }

  /// The finger left the surface at [position].
  void pointerUp(double t, Offset position) {
    advance(t);
    if (!_pressed) return;
    pointerMove(t, position);
    _release(t);
  }

  /// The touch was cancelled; the surface returns without activating.
  void pointerCancel(double t) {
    advance(t);
    release(t);
  }

  /// Ends the touch at [t] without activating and without advancing: for
  /// an owner that lets go of the surface from a reaction of its own.
  void release(double t) {
    if (!_pressed) return;
    _release(t);
  }

  void _release(double t) {
    _pressed = false;
    if (law.glows) _glow.release(t);
    _later(t, _flexRelease);
  }

  // A touch stamped earlier than the cursor runs at its own time, as the
  // flex would have taken it up then.
  void _later(double t, void Function(double t) action) {
    final due = t + law.touchDelay;
    if (due <= now) {
      action(due);
    } else {
      at(due, action);
    }
  }

  void _flexDown(double t, Offset position) {
    _down = position;
    _position = position;
    if (law.activationDelay <= 0) {
      _activate(t);
    } else {
      at(t + law.activationDelay, _activate, slot: _activation);
    }
  }

  void _flexMove(double t, Offset position) {
    if (_down == null) return;
    _position = position;
    if (_active) _retarget(t, targets, tracking: true);
  }

  void _flexRelease(double t) {
    unschedule(_activation);
    _down = null;
    _active = false;
    _retarget(t, FlexInteraction.rest, tracking: false);
  }

  void _activate(double t) {
    if (_down == null) return;
    _active = true;
    _retarget(t, targets, tracking: true);
  }

  void _retarget(double t, FlexValues to, {required bool tracking}) {
    final spring = _spec.channelSpring;
    chaseFlexChannel(_scaleX, t, to.scaleX, spring, tracking: tracking);
    chaseFlexChannel(_scaleY, t, to.scaleY, spring, tracking: tracking);
    chaseFlexChannel(_driftX, t, to.driftX, spring, tracking: tracking);
    chaseFlexChannel(_driftY, t, to.driftY, spring, tracking: tracking);
  }

  /// What the channels head to now: the dynamic targets of the finger
  /// while the flex is active ([FlexInteraction.dynamicTargets]), rest
  /// otherwise.
  @internal
  FlexValues get targets {
    final down = _down;
    if (!_active || down == null || traits.reduceMotion) {
      return FlexInteraction.rest;
    }
    final at = _position;
    return FlexInteraction.dynamicTargets(
      spec: _spec,
      size: _size,
      translation: at - down,
      inBounds: _clamped(at) - down,
      stretch: law.stretches,
    );
  }

  Offset _clamped(Offset p) =>
      Offset(p.dx.clamp(0.0, _size.width), p.dy.clamp(0.0, _size.height));
}

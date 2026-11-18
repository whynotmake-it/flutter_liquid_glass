import 'dart:math' as math;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/src/motions/flex_spec.dart' show FlexSpec;
import 'package:apple_liquid_glass/src/motions/glass_press.dart'
    show GlassPress;
import 'package:apple_liquid_glass/src/motions/tab_bar_layout.dart';
import 'package:flutter/painting.dart';
import 'package:kinesis/motion.dart';
import 'package:meta/meta.dart';

/// The springs of the touch glow of a pressed glass surface.
@internal
abstract final class TouchGlowTuning {
  /// The spring the glows rise on.
  static const riseSpring = Spring.response(0.1);

  /// The spring the glows fall, grow and turn dragging on.
  static const fallSpring = Spring.response(0.5);
}

/// The touch glow of a pressed glass surface as a function of time:
/// UIKit's flex interaction glows, measured on an iPhone on iOS 27's tab
/// bar and open menu, which share the law and differ in [diameter],
/// [riseLag] and their peaks. A glass button glows by the same law
/// ([GlassPress]), with [buttonDiameter] and its touch delay as [riseLag].
///
/// A touch raises both glows on a critically damped
/// [TouchGlowTuning.riseSpring] after [riseLag]; they hold while the
/// finger stays down. A finger that moves [dragDistance] from where it
/// landed turns the spot into its dragging state: twice as wide at half
/// the strength, on [TouchGlowTuning.fallSpring]. Lifting the finger lets
/// both glows fall on [TouchGlowTuning.fallSpring] after [releaseLag]
/// while the spot spreads to [releaseGrowth] times its size. The spot
/// follows the finger.
///
/// Peaks come from the surface's [FlexSpec] - its big glow opacity
/// for the wash, its little glow opacity for the spot - so a 62 pixel
/// tall bar peaks at 0.845 and 0.2845, and an open menu
/// ([FlexSpec.menu]) at 0 and 0.5.
///
/// Under a finger the rise rests within [MotionRest.opacity] and the
/// spot's size and strength within a visible step; after it the glow rests
/// once both glows read zero ([hideBelow]) and the fall is within
/// [MotionRest.opacity]. A finger held still counts: the glow rests lit
/// until the finger moves or lifts.
final class TouchGlowMotion extends Motion {
  /// Creates a resting glow with the peaks of a surface's [flex] spec.
  @internal
  TouchGlowMotion({
    required this.flex,
    required this.diameter,
    required this.riseLag,
    this.minimumLit = 0,
  });

  /// Creates the glow of a floating tab bar: the peaks of the flex spec of
  /// the measured 274 x 62 pt bar, a [tabBarDiameter] spot and
  /// [tabBarRiseLag] (tab bar passport).
  factory TouchGlowMotion.tabBar() => TouchGlowMotion(
    flex: FlexSpec.forSize(const Size(274, TabBarLayout.height)),
    diameter: tabBarDiameter,
    riseLag: tabBarRiseLag,
  );

  /// The flex spec of the surface, which a surface that changes size sets
  /// again.
  @internal
  FlexSpec flex;

  /// The opacity the wash rises to.
  double get washPeak => flex.bigGlowOpacity;

  /// The opacity the spot rises to.
  double get spotPeak => flex.littleGlowOpacity;

  /// How long after the touch the glows start to rise, in seconds.
  final double riseLag;

  /// The tab bar's [riseLag]: fitted to its device rows (tab-bar.md, Spec -
  /// touch glow).
  static const double tabBarRiseLag = 0.042;

  /// The least time, in seconds, the glow rises before a release lets it
  /// fall: a lift sooner than that starts the fall this long after the
  /// rise began. Zero lets the fall follow the lift after [releaseLag].
  final double minimumLit;

  double _riseAt = 0;

  /// How long after the release the glows start to fall, in seconds.
  static const double releaseLag = 0.02;

  /// The diameter of the spot before it grows, in pixels.
  final double diameter;

  /// The tab bar's [diameter]: its LittleGlow layer is a 93 pt disc
  /// (tab-bar.md, Spec - touch glow).
  static const double tabBarDiameter = 93;

  /// A glass button's [diameter]: not measured (glass-button passport).
  static const double buttonDiameter = 66;

  /// How many times its size the spot grows to after a release.
  static const double releaseGrowth = 4;

  /// How many times its size the spot grows to while dragged.
  static const double dragGrowth = 2;

  /// The share of its strength the spot keeps while dragged.
  static const double dragStrength = 0.5;

  /// How far the finger moves from its landing before the spot turns
  /// dragging, in pixels.
  static const double dragDistance = 50;

  /// Each glow's opacity reads zero below this.
  static const double hideBelow = 0.005;

  /// How much the wash adds to every channel at opacity 1: the offset of
  /// its color matrix.
  static const double washOffset = 0.05;

  /// The strength of the spot's center at opacity 1, as a share of its
  /// color matrix's gain.
  static const double spotCore = 0.38;

  /// The spot's Gaussian standard deviation as a share of its diameter.
  static const double spotSpread = 0.568;

  double _progressRest() {
    if (_down != null) return MotionRest.opacity;
    final peak = math.max(math.max(washPeak, spotPeak), hideBelow);
    return math.min(MotionRest.opacity, hideBelow / peak);
  }

  double _scaleRest() =>
      _down == null ? double.infinity : MotionRest.scale(diameter);
  double _strengthRest() =>
      _down == null ? double.infinity : MotionRest.opacity;

  late final _progress = own(
    MotionValue<double>(0, spring: TouchGlowTuning.riseSpring),
    rest: _progressRest,
  );
  late final _scale = own(
    MotionValue<double>(1, spring: TouchGlowTuning.fallSpring),
    rest: _scaleRest,
  );
  late final _strength = own(
    MotionValue<double>(1, spring: TouchGlowTuning.fallSpring),
    rest: _strengthRest,
  );
  Offset _center = Offset.zero;
  Offset? _down;
  bool _dragging = false;
  static const _riseSlot = #rise;
  static const _dragSlot = #drag;
  static const _fallSlot = #fall;

  /// Whether a finger is down.
  bool get isDown => _down != null;

  /// A finger touched at [position] at time [t].
  void pointerDown(double t, Offset position) {
    advance(t);
    unschedule(_dragSlot);
    unschedule(_fallSlot);
    _center = position;
    _down = position;
    _dragging = false;
    _scale.snap(t, 1);
    _strength.snap(t, 1);
    _riseAt = t + riseLag;
    at(_riseAt, _rise, slot: _riseSlot);
  }

  void _rise(double at) =>
      _progress.retarget(at, 1, spring: TouchGlowTuning.riseSpring);

  /// The finger moved to [position] at time [t].
  void pointerMove(double t, Offset position) {
    advance(t);
    final down = _down;
    if (down == null) return;
    _center = position;
    if (_dragging || (position - down).distance < dragDistance) return;
    _dragging = true;
    at(t + riseLag, (at) {
      _scale.retarget(at, dragGrowth, spring: TouchGlowTuning.fallSpring);
      _strength.retarget(at, dragStrength, spring: TouchGlowTuning.fallSpring);
    }, slot: _dragSlot);
  }

  /// The finger lifted, or its touch was cancelled, at time [t].
  void pointerUp(double t) {
    advance(t);
    release(t);
  }

  /// Ends the touch at [t] without advancing: for an owner that lets go
  /// from a reaction of its own.
  void release(double t) {
    if (_down == null) return;
    _down = null;
    unschedule(_riseSlot);
    unschedule(_dragSlot);
    if (minimumLit > 0 && _riseAt > t) at(_riseAt, _rise, slot: _riseSlot);
    final start = math.max(t + releaseLag, _riseAt + minimumLit);
    at(start, (at) {
      _progress.retarget(at, 0, spring: TouchGlowTuning.fallSpring);
      _scale.retarget(at, releaseGrowth, spring: TouchGlowTuning.fallSpring);
    }, slot: _fallSlot);
  }

  /// The wash's opacity at time [t], from [now] on.
  double washOpacity(double t) {
    advance(t);
    return _wash(t);
  }

  /// The spot's opacity at time [t], from [now] on.
  double spotOpacity(double t) {
    advance(t);
    return _spot(t);
  }

  /// The spot's scale over [diameter] at time [t], from [now] on.
  double spotScale(double t) {
    advance(t);
    return _scale.valueAt(t);
  }

  /// The glow to paint now.
  GlassTouchGlow? get glow {
    final t = now;
    final wash = _wash(t);
    final spot = _spot(t);
    if (wash == 0 && spot == 0) return null;
    return GlassTouchGlow(
      wash: washOffset * wash,
      center: _center,
      radius: spotSpread * diameter * _scale.valueAt(t),
      spot: spotCore * spot,
    );
  }

  double _wash(double t) {
    final value = washPeak * _progress.valueAt(t).clamp(0.0, 1.0);
    return value < hideBelow ? 0 : value;
  }

  double _spot(double t) {
    final value =
        spotPeak * _progress.valueAt(t).clamp(0.0, 1.0) * _strength.valueAt(t);
    return value < hideBelow ? 0 : value;
  }
}

import 'dart:math' as math;

import 'package:kinesis/motion.dart';
import 'package:meta/meta.dart';

/// UIKit's tuning for glass bar items that change: the
/// `GlassContainerToolbarPTSettings` iOS 27 runs when a toolbar's items
/// are replaced and when a navigation bar's buttons change on a push or
/// a pop.
///
/// Read live from the tuning (springs in SwiftUI's duration / bounce
/// terms, here as response / damping ratio = 1 - bounce) and placed in
/// time by the frame-by-frame recordings of `setToolbarItems(_:animated:)`
/// and of pushes.
@immutable
class GlassBarTransitionSpec {
  /// Creates a spec from explicit values.
  @internal
  const GlassBarTransitionSpec({
    this.frameSpring = const Spring.response(0.416, dampingRatio: 0.75),
    this.frameDelay = 0.05,
    this.birthStaggerDelay = 0.1,
    this.contentSpring = const Spring.response(0.416, dampingRatio: 0.75),
    this.contentDelay = 0.05,
    this.appearScale = 0.2,
    this.appearBlur = 10,
    this.pulseDelay = 0.065,
    this.pulseUpSpring = const Spring.response(0.292, dampingRatio: 0.5),
    this.pulseMaxScale = 1.2,
    this.pulseMaxPoints = 16,
    this.pulseHeightDownDelay = 0.113,
    this.pulseHeightDownSpring = const Spring.response(
      0.416,
      dampingRatio: 0.584,
    ),
    this.pulseWidthDownDelay = 0.142,
    this.pulseWidthDownSpring = const Spring.response(0.416, dampingRatio: 0.5),
    this.segmentDelay = 0.030,
    this.oversizedInPlace = true,
  });

  /// The spring a capsule's frame moves on: `transition.springDuration`
  /// 0.416 s, bounce 0.25.
  @internal
  final Spring frameSpring;

  /// The time from the change to the start of the frame motion, in
  /// seconds (fitted jointly to the device and simulator recordings of
  /// `setToolbarItems(_:animated:)`, measured from the call).
  final double frameDelay;

  /// The time from the change to the start of the frame motion of a
  /// capsule that moves while a capsule of its side grows out of a
  /// survivor, in seconds: the survivor waits for the newborn (fitted
  /// 0.1 s; the tuning's `transition.minDelay` / `maxDelay` are 0.083 /
  /// 0.166).
  final double birthStaggerDelay;

  /// The spring items appear, leave and travel on (fitted 0.40 / 0.80 on
  /// the recordings, the transition spring within that spread).
  @internal
  final Spring contentSpring;

  /// The time from the change to the start of the item motion, in
  /// seconds (fitted).
  final double contentDelay;

  /// The scale an item or a capsule is born at and leaves at:
  /// `appearance.scale`.
  final double appearScale;

  /// The blur of an item that is born or leaves, at its smallest:
  /// `appearance.blurRadius`.
  final double appearBlur;

  /// The time from the change to the start of the size pulse, in seconds
  /// (fitted 0.065 s from the call; a frame or two before the tuning's
  /// `transition.minDelay` 0.083, which counts from the commit).
  final double pulseDelay;

  /// The spring a changed capsule swells on: `scalePulse.scaleUp` 0.292 s,
  /// bounce 0.5.
  @internal
  final Spring pulseUpSpring;

  /// The largest relative swell: `scalePulse.maxScaleWidth/Height`.
  final double pulseMaxScale;

  /// The largest swell in points: `scalePulse.maxPointScaleWidth/Height`.
  final double pulseMaxPoints;

  /// The time from the start of the swell to the return of the height:
  /// `scalePulse.scaleDownHeightDelay`.
  final double pulseHeightDownDelay;

  /// The spring the height returns on: 0.416 s, bounce 0.416.
  @internal
  final Spring pulseHeightDownSpring;

  /// The time from the start of the swell to the return of the width:
  /// `scalePulse.scaleDownWidthDelay`.
  final double pulseWidthDownDelay;

  /// The spring the width returns on: 0.416 s, bounce 0.5.
  @internal
  final Spring pulseWidthDownSpring;

  /// The time from the change to the start of a group that appears or
  /// leaves in place, in seconds: on a side of the bar that had no group
  /// or keeps none, or too large for its survivor (see [oversizedInPlace]).
  ///
  /// Such a group does not grow out of a neighbour: it stands at its own
  /// place, scaled by [pulseScaleFor] its length per axis, blurred by
  /// [appearBlur] and transparent, and comes in (or goes) on
  /// [frameSpring], scale, opacity and blur on one progress (free fits
  /// 0.39 - 0.41 s / 0.75 - 0.77 over 16 groups). Fitted to
  /// `setToolbarItems(_:animated:)` filling and emptying a toolbar side:
  /// 0.020 - 0.044 s from the call, replay optimum 0.026 - 0.030 (iPhone
  /// 16 Pro, iOS 27.0.1).
  final double segmentDelay;

  /// Whether a group too large for the group it would grow out of (or
  /// shrink into) appears (or leaves) in place instead.
  ///
  /// A group born beside a group of its side that stays grows out of that
  /// survivor: its own box fitted inside the survivor's box before the
  /// change (the size of each axis at most the survivor's, the place as
  /// near its own as fits), at [appearScale]; a group that goes shrinks
  /// into the survivor's box after the change the same way. When the group
  /// is wider or taller than the survivor, a toolbar shows it in place
  /// (`setToolbarItems(_:animated:)`: `[reply share folder]` beside `[compose]`
  /// or `[heart]` in place, `[heart]` out of `[Show Preferences]` and out of
  /// `[compose]`), while a navigation bar still grows it out of the
  /// survivor's own box (`[plus more]` out of `[1x]` on a push, back into it on
  /// a pop; iPhone 16 Pro, iOS 27.0.1, probe scene navseg set b).
  final bool oversizedInPlace;

  /// iOS 27's values for a toolbar whose items are replaced.
  static const standard = GlassBarTransitionSpec();

  /// iOS 27's values for a navigation bar on a push or a pop, which starts
  /// later than a toolbar's item replacement: the capsules' frames after
  /// 0.062 s (center replay optimum 0.060 - 0.062 over four pushes and
  /// four pops), groups coming or going in place after 0.058 s (0.050 -
  /// 0.063 over eight groups, replay optimum 0.058), measured from the
  /// `pushViewController` / `popViewController` call.
  static const navigation = GlassBarTransitionSpec(
    frameDelay: 0.062,
    segmentDelay: 0.058,
    oversizedInPlace: false,
  );

  /// The swell of a capsule [length] long, as a factor.
  double pulseScaleFor(double length) =>
      length <= 0 ? 1 : math.min(pulseMaxScale, 1 + pulseMaxPoints / length);
}

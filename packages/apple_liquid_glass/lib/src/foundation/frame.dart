import 'package:apple_liquid_glass/src/foundation/body.dart';
import 'package:apple_liquid_glass/src/foundation/outline.dart';
import 'package:apple_liquid_glass/src/foundation/touch_glow.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/painting.dart';

/// One frame of one glass surface: where its body is drawn, how far it is
/// lifted, the tint it turns to and how a touch lights it.
///
/// A frame is what a control's motion produces; how the body looks at that
/// lift and tint (its optics, frost, fill and shadows) is the renderer's.
/// Renderers apply [rect], [scaleX] and [scaleY] at paint, so a frame never
/// lays anything out, and the surface's content moves and scales with the
/// body.
@immutable
final class GlassFrame {
  /// Creates a frame of a body of [shape].
  const GlassFrame({
    this.shape = LiquidRoundedSuperellipse.capsule,
    this.rect,
    this.scaleX = 1,
    this.scaleY = 1,
    this.tint,
    this.tintAmount = 1,
    this.lift = 0,
    this.glow,
    this.opacity = 1,
    this.outline,
  }) : assert(
         outline == null || (rect == null && scaleX == 1 && scaleY == 1),
         'An outline body is drawn where its path is.',
       );

  /// The outline of the body.
  final LiquidShape shape;

  /// Where the body is drawn in the box the surface was laid out in, or
  /// null to fill that box. Hit testing keeps that box, as UIKit hit-tests
  /// a view's model rather than its presentation.
  final Rect? rect;

  /// The horizontal scale of the body and its content about the center of
  /// [rect].
  final double scaleX;

  /// The vertical scale of the body and its content about the center of
  /// [rect].
  final double scaleY;

  /// A color, already resolved for the context, that the body draws in
  /// place of its glass's tint in this frame, or null to keep it: a
  /// switch's track turning on.
  final Color? tint;

  /// How much of [tint] the body takes in place of its glass's own look,
  /// 0 none to 1 all: a body that crosses from a tinted source into its
  /// own glass, as a tinted button's glass grows into its menu.
  final double tintAmount;

  /// How far a lens or knob is lifted, 0 resting and 1 lifted: a resting
  /// one is an opaque platter, a lifted one clear glass. Other roles ignore
  /// it.
  final double lift;

  /// The glow a finger raises on the body, in the body's own coordinates
  /// ([GlassBody]), or null for none.
  final GlassTouchGlow? glow;

  /// How present the body and its content are, 0 gone to 1 fully there:
  /// a body appearing or leaving in place fades its glass, refraction and
  /// lighting included, with its content.
  final double opacity;

  /// The body's own edge when [shape] does not describe it, or null to
  /// draw [shape]. With an outline, [shape] still rounds the corners of
  /// the box the outline spans for what a renderer cannot draw from the
  /// outline, and [rect], [scaleX] and [scaleY] keep their defaults.
  final GlassOutline? outline;

  /// Below this [lift] a lens or knob draws no glass.
  ///
  /// Above it the glass appears over the first quarter of the lift.
  /// Engineering defaults from Morph, not measured; a lens crossing it
  /// changes by at most 2% of its blend: invisible, NEAR.
  static const double restingLift = 0.005;

  static const double _glassLiftSpan = 0.25;

  /// How far a lens or knob lifted by [lift] has turned into glass, 0 an
  /// opaque platter to 1 all glass: the one curve every renderer and every
  /// control that draws under a lens follows.
  static double glassnessAt(double lift) =>
      lift <= restingLift ? 0 : (lift / _glassLiftSpan).clamp(0.0, 1.0);

  /// A copy of this frame with the given fields replaced.
  GlassFrame copyWith({
    LiquidShape? shape,
    Rect? rect,
    double? scaleX,
    double? scaleY,
    Color? tint,
    double? tintAmount,
    double? lift,
    GlassTouchGlow? glow,
    double? opacity,
    GlassOutline? outline,
  }) => GlassFrame(
    shape: shape ?? this.shape,
    rect: rect ?? this.rect,
    scaleX: scaleX ?? this.scaleX,
    scaleY: scaleY ?? this.scaleY,
    tint: tint ?? this.tint,
    tintAmount: tintAmount ?? this.tintAmount,
    lift: lift ?? this.lift,
    glow: glow ?? this.glow,
    opacity: opacity ?? this.opacity,
    outline: outline ?? this.outline,
  );

  /// The body before its scale, in the box the surface was laid out in, or
  /// null to fill the box.
  Rect? get bodyRect => outline?.bounds ?? rect;

  /// Where this frame draws the body in a box of [size].
  GlassBody bodyIn(Size size) => GlassBody.of(this, size);

  @override
  bool operator ==(Object other) =>
      other is GlassFrame &&
      other.shape == shape &&
      other.rect == rect &&
      other.scaleX == scaleX &&
      other.scaleY == scaleY &&
      other.tint == tint &&
      other.tintAmount == tintAmount &&
      other.lift == lift &&
      other.glow == glow &&
      other.opacity == opacity &&
      other.outline == outline;

  @override
  int get hashCode => Object.hash(
    shape,
    rect,
    scaleX,
    scaleY,
    tint,
    tintAmount,
    lift,
    glow,
    opacity,
    outline,
  );
}

import 'dart:ui' show lerpDouble;

import 'package:flutter/painting.dart';

/// Represents a shape that can be used by a `LiquidGlass` widget.
///
/// The set of shapes is closed and sealed: use [LiquidRoundedSuperellipse],
/// [LiquidOval] or [LiquidRoundedRectangle]. `switch`es over a [LiquidShape]
/// are exhaustive, and adding a shape in a future release is a compile-time
/// error for them rather than a silent fall-through.
///
/// Every shape is also an [OutlinedBorder], so it can be used wherever Flutter
/// accepts a [ShapeBorder], and two shapes of one kind lerp into each other.
/// The glass renderer ignores [side]; it is only painted when the shape is
/// used as a regular border, for example in a [ShapeDecoration].
///
/// Corner radii are plain numbers, not a [BorderRadiusGeometry]: glass draws
/// circular corners, all four alike or the top pair apart from the bottom
/// pair, and nothing else a border radius can say.
sealed class LiquidShape extends OutlinedBorder {
  const LiquidShape({super.side = BorderSide.none});

  OutlinedBorder get _equivalentOutlinedBorder;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return _equivalentOutlinedBorder.getInnerPath(
      rect,
      textDirection: textDirection,
    );
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return _equivalentOutlinedBorder.getOuterPath(
      rect,
      textDirection: textDirection,
    );
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    _equivalentOutlinedBorder.paint(canvas, rect, textDirection: textDirection);
  }

  /// Fills the shape over [rect] with the canvas's own primitive for it
  /// (a rounded superellipse, an oval or a rounded rectangle), which draws
  /// and blurs faster than its path.
  @override
  void paintInterior(
    Canvas canvas,
    Rect rect,
    Paint paint, {
    TextDirection? textDirection,
  }) => _equivalentOutlinedBorder.paintInterior(
    canvas,
    rect,
    paint,
    textDirection: textDirection,
  );

  @override
  bool get preferPaintInterior => true;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          other is LiquidShape &&
          other.side == side;

  @override
  int get hashCode => side.hashCode;
}

/// Represents a squircle shape that can be used by a `LiquidGlass` widget.
///
/// Works like a [RoundedSuperellipseBorder], with one radius for all four
/// corners, or one for the two top corners and another for the two bottom
/// ones ([LiquidRoundedSuperellipse.vertical]), like a floating iOS sheet
/// (38 pt on top, 54 pt below on an iPhone 16 Pro).
final class LiquidRoundedSuperellipse extends LiquidShape {
  /// Creates a new [LiquidRoundedSuperellipse] with four corners of [radius].
  ///
  /// The glass ignores [side]; see [LiquidShape].
  const LiquidRoundedSuperellipse({
    required double radius,
    super.side = BorderSide.none,
  }) : topRadius = radius,
       bottomRadius = radius;

  /// Creates a new [LiquidRoundedSuperellipse] whose two top corners have
  /// the radius [top] and whose two bottom corners the radius [bottom], as
  /// [BorderRadius.vertical] does.
  ///
  /// The glass ignores [side]; see [LiquidShape].
  const LiquidRoundedSuperellipse.vertical({
    required double top,
    required double bottom,
    super.side = BorderSide.none,
  }) : topRadius = top,
       bottomRadius = bottom;

  LiquidRoundedSuperellipse._lerp(
    LiquidRoundedSuperellipse a,
    LiquidRoundedSuperellipse b,
    double t,
  ) : topRadius = lerpDouble(a.topRadius, b.topRadius, t)!,
      bottomRadius = lerpDouble(a.bottomRadius, b.bottomRadius, t)!,
      super(side: BorderSide.lerp(a.side, b.side, t));

  /// A capsule. A corner radius past half the box's shorter side draws as
  /// half of it, so these corners are as round as any box allows.
  static const capsule = LiquidRoundedSuperellipse(radius: 10000);

  /// The radius of the two top corners.
  final double topRadius;

  /// The radius of the two bottom corners.
  final double bottomRadius;

  /// The four corners as a [BorderRadius], for Flutter's clips and paths of
  /// the same outline.
  BorderRadius get borderRadius => BorderRadius.vertical(
    top: Radius.circular(topRadius),
    bottom: Radius.circular(bottomRadius),
  );

  @override
  OutlinedBorder get _equivalentOutlinedBorder =>
      RoundedSuperellipseBorder(borderRadius: borderRadius, side: side);

  @override
  LiquidRoundedSuperellipse copyWith({
    BorderSide? side,
    double? topRadius,
    double? bottomRadius,
  }) {
    return LiquidRoundedSuperellipse.vertical(
      side: side ?? this.side,
      top: topRadius ?? this.topRadius,
      bottom: bottomRadius ?? this.bottomRadius,
    );
  }

  @override
  LiquidRoundedSuperellipse scale(double t) {
    return LiquidRoundedSuperellipse.vertical(
      top: topRadius * t,
      bottom: bottomRadius * t,
      side: side.scale(t),
    );
  }

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) =>
      a is LiquidRoundedSuperellipse
      ? LiquidRoundedSuperellipse._lerp(a, this, t)
      : super.lerpFrom(a, t);

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) =>
      b is LiquidRoundedSuperellipse
      ? LiquidRoundedSuperellipse._lerp(this, b, t)
      : super.lerpTo(b, t);

  @override
  bool operator ==(Object other) =>
      super == other &&
      other is LiquidRoundedSuperellipse &&
      other.topRadius == topRadius &&
      other.bottomRadius == bottomRadius;

  @override
  int get hashCode => Object.hash(side, topRadius, bottomRadius);

  @override
  String toString() => topRadius == bottomRadius
      ? 'LiquidRoundedSuperellipse(radius: $topRadius, side: $side)'
      : 'LiquidRoundedSuperellipse.vertical(top: $topRadius, '
            'bottom: $bottomRadius, side: $side)';
}

/// Represents an ellipse shape that can be used by a `LiquidGlass` widget.
///
/// Works like an [OvalBorder].
final class LiquidOval extends LiquidShape {
  /// Creates a new [LiquidOval] with the given [side].
  ///
  /// The glass ignores [side]; see [LiquidShape].
  const LiquidOval({super.side = BorderSide.none});

  @override
  OutlinedBorder get _equivalentOutlinedBorder => OvalBorder(side: side);

  @override
  LiquidOval copyWith({BorderSide? side}) {
    return LiquidOval(
      side: side ?? this.side,
    );
  }

  @override
  LiquidOval scale(double t) {
    return LiquidOval(
      side: side.scale(t),
    );
  }

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) => a is LiquidOval
      ? LiquidOval(side: BorderSide.lerp(a.side, side, t))
      : super.lerpFrom(a, t);

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) => b is LiquidOval
      ? LiquidOval(side: BorderSide.lerp(side, b.side, t))
      : super.lerpTo(b, t);

  @override
  String toString() => 'LiquidOval(side: $side)';
}

/// Represents a rounded rectangle shape that can be used by a `LiquidGlass`
/// widget.
///
/// Works like a [RoundedRectangleBorder] with four circular corners of one
/// radius.
final class LiquidRoundedRectangle extends LiquidShape {
  /// Creates a new [LiquidRoundedRectangle] with four corners of [radius].
  ///
  /// The glass ignores [side]; see [LiquidShape].
  const LiquidRoundedRectangle({
    required this.radius,
    super.side = BorderSide.none,
  });

  LiquidRoundedRectangle._lerp(
    LiquidRoundedRectangle a,
    LiquidRoundedRectangle b,
    double t,
  ) : radius = lerpDouble(a.radius, b.radius, t)!,
      super(side: BorderSide.lerp(a.side, b.side, t));

  /// The radius of the corners.
  final double radius;

  /// The four corners as a [BorderRadius], for Flutter's clips and paths of
  /// the same outline.
  BorderRadius get borderRadius => BorderRadius.all(Radius.circular(radius));

  @override
  OutlinedBorder get _equivalentOutlinedBorder =>
      RoundedRectangleBorder(borderRadius: borderRadius, side: side);

  @override
  LiquidRoundedRectangle copyWith({
    BorderSide? side,
    double? radius,
  }) {
    return LiquidRoundedRectangle(
      side: side ?? this.side,
      radius: radius ?? this.radius,
    );
  }

  @override
  LiquidRoundedRectangle scale(double t) {
    return LiquidRoundedRectangle(
      radius: radius * t,
      side: side.scale(t),
    );
  }

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) => a is LiquidRoundedRectangle
      ? LiquidRoundedRectangle._lerp(a, this, t)
      : super.lerpFrom(a, t);

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) => b is LiquidRoundedRectangle
      ? LiquidRoundedRectangle._lerp(this, b, t)
      : super.lerpTo(b, t);

  @override
  bool operator ==(Object other) =>
      super == other &&
      other is LiquidRoundedRectangle &&
      other.radius == radius;

  @override
  int get hashCode => Object.hash(side, radius);

  @override
  String toString() => 'LiquidRoundedRectangle(radius: $radius, side: $side)';
}

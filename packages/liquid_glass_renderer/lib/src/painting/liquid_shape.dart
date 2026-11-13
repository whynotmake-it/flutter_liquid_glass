import 'package:flutter/painting.dart';

/// Represents a shape that can be used by a `LiquidGlass` widget.
///
/// The set of shapes is closed and sealed: use [LiquidRoundedSuperellipse],
/// [LiquidOval] or [LiquidRoundedRectangle]. `switch`es over a [LiquidShape]
/// are exhaustive, and adding a shape in a future release is a compile-time
/// error for them rather than a silent fall-through.
///
/// Every shape is also an [OutlinedBorder], so it can be used wherever Flutter
/// accepts a [ShapeBorder]. The glass renderer ignores [side]; it is only
/// painted when the shape is used as a regular border, for example in a
/// [ShapeDecoration].
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
/// ones, like a floating iOS sheet (38 pt on top, 54 pt below on an iPhone 16
/// Pro).
final class LiquidRoundedSuperellipse extends LiquidShape {
  /// Creates a new [LiquidRoundedSuperellipse] with corners of
  /// [borderRadius], or with the two bottom ones of [bottomRadius] when it is
  /// given.
  ///
  /// The glass ignores [side]; see [LiquidShape].
  const LiquidRoundedSuperellipse({
    required this.borderRadius,
    this.bottomRadius,
    super.side = BorderSide.none,
  });

  /// The radius of the squircle's corners, of its two top corners when
  /// [bottomRadius] is given.
  final double borderRadius;

  /// The radius of the two bottom corners, or `null` for [borderRadius].
  final double? bottomRadius;

  /// The four corners as a [BorderRadius], for Flutter's clips and paths of
  /// the same outline.
  BorderRadius get radii => BorderRadius.vertical(
    top: Radius.circular(borderRadius),
    bottom: Radius.circular(bottomRadius ?? borderRadius),
  );

  @override
  OutlinedBorder get _equivalentOutlinedBorder =>
      RoundedSuperellipseBorder(borderRadius: radii, side: side);

  @override
  LiquidRoundedSuperellipse copyWith({
    BorderSide? side,
    double? borderRadius,
    double? bottomRadius,
  }) {
    return LiquidRoundedSuperellipse(
      side: side ?? this.side,
      borderRadius: borderRadius ?? this.borderRadius,
      bottomRadius: bottomRadius ?? this.bottomRadius,
    );
  }

  @override
  ShapeBorder scale(double t) {
    return LiquidRoundedSuperellipse(
      borderRadius: borderRadius * t,
      bottomRadius: bottomRadius == null ? null : bottomRadius! * t,
      side: side.scale(t),
    );
  }

  @override
  bool operator ==(Object other) =>
      super == other &&
      other is LiquidRoundedSuperellipse &&
      other.borderRadius == borderRadius &&
      other.bottomRadius == bottomRadius;

  @override
  int get hashCode => Object.hash(side, borderRadius, bottomRadius);

  @override
  String toString() =>
      'LiquidRoundedSuperellipse($side, $borderRadius, $bottomRadius)';
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
  OutlinedBorder copyWith({BorderSide? side}) {
    return LiquidOval(
      side: side ?? this.side,
    );
  }

  @override
  ShapeBorder scale(double t) {
    return LiquidOval(
      side: side.scale(t),
    );
  }

  @override
  String toString() => 'LiquidOval($side)';
}

/// Represents a rounded rectangle shape that can be used by a `LiquidGlass`
/// widget.
///
/// Works like a [RoundedRectangleBorder].
final class LiquidRoundedRectangle extends LiquidShape {
  /// Creates a new [LiquidRoundedRectangle] with the given [borderRadius].
  ///
  /// The glass ignores [side]; see [LiquidShape].
  const LiquidRoundedRectangle({
    required this.borderRadius,
    super.side = BorderSide.none,
  });

  /// The radius of the corners.
  final double borderRadius;

  @override
  OutlinedBorder get _equivalentOutlinedBorder => RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(borderRadius)),
    side: side,
  );

  @override
  LiquidRoundedRectangle copyWith({
    BorderSide? side,
    double? borderRadius,
  }) {
    return LiquidRoundedRectangle(
      side: side ?? this.side,
      borderRadius: borderRadius ?? this.borderRadius,
    );
  }

  @override
  ShapeBorder scale(double t) {
    return LiquidRoundedRectangle(
      borderRadius: borderRadius * t,
      side: side.scale(t),
    );
  }

  @override
  bool operator ==(Object other) =>
      super == other &&
      other is LiquidRoundedRectangle &&
      other.borderRadius == borderRadius;

  @override
  int get hashCode => Object.hash(side, borderRadius);

  @override
  String toString() => 'LiquidRoundedRectangle($side, $borderRadius)';
}

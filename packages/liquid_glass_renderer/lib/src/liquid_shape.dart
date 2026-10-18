import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:meta/meta.dart';

/// Represents a shape that can be used by a [LiquidGlass] widget.
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
sealed class LiquidShape extends OutlinedBorder with Equatable {
  const LiquidShape({super.side = BorderSide.none});

  /// Corner radius in logical pixels; `0` for shapes without corners.
  @internal
  double get cornerRadius;

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
  List<Object?> get props => [side];
}

/// Represents a squircle shape that can be used by a [LiquidGlass] widget.
///
/// Works like a [RoundedSuperellipseBorder].
final class LiquidRoundedSuperellipse extends LiquidShape {
  /// Creates a new [LiquidRoundedSuperellipse] with the given [borderRadius].
  ///
  /// The glass ignores [side]; see [LiquidShape].
  const LiquidRoundedSuperellipse({
    required this.borderRadius,
    super.side = BorderSide.none,
  });

  /// The radius of the squircle.
  ///
  /// This is the radius of the corners of the squircle.
  final double borderRadius;

  @internal
  @override
  double get cornerRadius => borderRadius;

  @override
  OutlinedBorder get _equivalentOutlinedBorder => RoundedSuperellipseBorder(
    borderRadius: BorderRadius.all(Radius.circular(borderRadius)),
    side: side,
  );

  @override
  LiquidRoundedSuperellipse copyWith({
    BorderSide? side,
    double? borderRadius,
  }) {
    return LiquidRoundedSuperellipse(
      side: side ?? this.side,
      borderRadius: borderRadius ?? this.borderRadius,
    );
  }

  @override
  ShapeBorder scale(double t) {
    return LiquidRoundedSuperellipse(
      borderRadius: borderRadius * t,
      side: side.scale(t),
    );
  }

  @override
  List<Object?> get props => [...super.props, borderRadius];
}

/// Represents an ellipse shape that can be used by a [LiquidGlass] widget.
///
/// Works like an [OvalBorder].
final class LiquidOval extends LiquidShape {
  /// Creates a new [LiquidOval] with the given [side].
  ///
  /// The glass ignores [side]; see [LiquidShape].
  const LiquidOval({super.side = BorderSide.none});

  @internal
  @override
  double get cornerRadius => 0;

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
}

/// Represents a rounded rectangle shape that can be used by a [LiquidGlass]
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

  /// The radius of the rounded rectangle.
  ///
  /// This is the radius of the corners of the rounded rectangle.
  final double borderRadius;

  @internal
  @override
  double get cornerRadius => borderRadius;

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
  List<Object?> get props => [...super.props, borderRadius];
}

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

/// Represents a shape that can be used by a [LiquidGlass] widget.
///
/// At the moment, only [LiquidGlassSquircle] is supported, but that will change
/// in the near future.
sealed class LiquidGlassShape extends OutlinedBorder with EquatableMixin {
  const LiquidGlassShape({super.side = BorderSide.none});

  @protected
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
class LiquidGlassSquircle extends LiquidGlassShape {
  /// Creates a new [LiquidGlassSquircle] with the given [borderRadius].
  const LiquidGlassSquircle({
    required this.borderRadius,
    super.side = BorderSide.none,
  });

  /// The radius of the squircle.
  ///
  /// This is the radius of the corners of the squircle.
  final Radius borderRadius;

  @override
  OutlinedBorder get _equivalentOutlinedBorder => RoundedSuperellipseBorder(
        borderRadius: BorderRadius.all(borderRadius),
        side: side,
      );

  @override
  LiquidGlassSquircle copyWith({
    BorderSide? side,
    Radius? borderRadius,
  }) {
    return LiquidGlassSquircle(
      side: side ?? this.side,
      borderRadius: borderRadius ?? this.borderRadius,
    );
  }

  @override
  ShapeBorder scale(double t) {
    return LiquidGlassSquircle(
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
@Deprecated('Not supported yet!')
class LiquidGlassEllipse extends LiquidGlassShape {
  /// Creates a new [LiquidGlassEllipse] with the given [side].
  @Deprecated('Not supported yet!')
  const LiquidGlassEllipse({super.side = BorderSide.none});

  @override
  OutlinedBorder get _equivalentOutlinedBorder => const OvalBorder();

  @override
  OutlinedBorder copyWith({BorderSide? side}) {
    return LiquidGlassEllipse(
      side: side ?? this.side,
    );
  }

  @override
  ShapeBorder scale(double t) {
    return LiquidGlassEllipse(
      side: side.scale(t),
    );
  }
}

/// Represents a rounded rectangle shape that can be used by a [LiquidGlass]
/// widget.
///
/// Works like a [RoundedRectangleBorder].
@Deprecated('Not supported yet!')
class LiquidGlassRoundedRectangle extends LiquidGlassShape {
  /// Creates a new [LiquidGlassRoundedRectangle] with the given [borderRadius].
  @Deprecated('Not supported yet!')
  const LiquidGlassRoundedRectangle({
    required this.borderRadius,
    super.side = BorderSide.none,
  });

  /// The radius of the rounded rectangle.
  ///
  /// This is the radius of the corners of the rounded rectangle.
  final Radius borderRadius;

  @override
  OutlinedBorder get _equivalentOutlinedBorder => RoundedRectangleBorder(
        borderRadius: BorderRadius.all(borderRadius),
        side: side,
      );

  @override
  LiquidGlassRoundedRectangle copyWith({
    BorderSide? side,
    Radius? borderRadius,
  }) {
    return LiquidGlassRoundedRectangle(
      side: side ?? this.side,
      borderRadius: borderRadius ?? this.borderRadius,
    );
  }

  @override
  ShapeBorder scale(double t) {
    return LiquidGlassRoundedRectangle(
      borderRadius: borderRadius * t,
      side: side.scale(t),
    );
  }

  @override
  List<Object?> get props => [...super.props, borderRadius];
}

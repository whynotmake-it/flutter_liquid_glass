import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

sealed class LiquidGlassShape extends OutlinedBorder with EquatableMixin {
  const LiquidGlassShape({this.side = BorderSide.none});

  @override
  final BorderSide side;

  @protected
  OutlinedBorder get equivalentOutlinedBorder;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return equivalentOutlinedBorder.getInnerPath(rect,
        textDirection: textDirection);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return equivalentOutlinedBorder.getOuterPath(rect,
        textDirection: textDirection);
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    equivalentOutlinedBorder.paint(canvas, rect, textDirection: textDirection);
  }

  @override
  List<Object?> get props => [side];
}

class LiquidGlassSquircle extends LiquidGlassShape {
  const LiquidGlassSquircle({
    required this.borderRadius,
    super.side = BorderSide.none,
  });

  final BorderRadius borderRadius;

  @override
  OutlinedBorder get equivalentOutlinedBorder => RoundedSuperellipseBorder(
        borderRadius: borderRadius,
        side: side,
      );

  @override
  LiquidGlassSquircle copyWith({
    BorderSide? side,
    BorderRadius? borderRadius,
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

class LiquidGlassEllipse extends LiquidGlassShape {
  const LiquidGlassEllipse({super.side = BorderSide.none});

  @override
  OutlinedBorder get equivalentOutlinedBorder => OvalBorder();

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

class LiquidGlassRoundedRectangle extends LiquidGlassShape {
  const LiquidGlassRoundedRectangle({
    required this.borderRadius,
    super.side = BorderSide.none,
  });

  final BorderRadius borderRadius;

  @override
  OutlinedBorder get equivalentOutlinedBorder => RoundedRectangleBorder(
        borderRadius: borderRadius,
        side: side,
      );

  @override
  LiquidGlassRoundedRectangle copyWith({
    BorderSide? side,
    BorderRadius? borderRadius,
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

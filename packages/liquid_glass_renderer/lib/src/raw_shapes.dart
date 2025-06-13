// ignore_for_file: dead_code

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_shape.dart';

enum RawShapeType {
  none,
  squircle,
  ellipse,
  roundedRectangle,
}

class RawShape with EquatableMixin {
  const RawShape({
    required this.type,
    required this.center,
    required this.size,
    required this.cornerRadius,
  });

  static const none = RawShape(
    type: RawShapeType.none,
    center: Offset.zero,
    size: Size.zero,
    cornerRadius: 0,
  );

  factory RawShape.fromLiquidGlassShape(
    LiquidGlassShape shape, {
    required Offset center,
    required Size size,
  }) {
    switch (shape) {
      case LiquidGlassSquircle():
        _assertSameRadius(shape.borderRadius);
        return RawShape(
            type: RawShapeType.squircle,
            center: center,
            size: size,
            cornerRadius: shape.borderRadius.topLeft.x);
      case LiquidGlassEllipse():
        throw UnsupportedError('Ellipse shape is not supported yet!');
        return RawShape(
          type: RawShapeType.ellipse,
          center: center,
          size: size,
          cornerRadius: 0,
        );
      case LiquidGlassRoundedRectangle():
        throw UnsupportedError('RoundedRectangle shape is not supported yet!');
        _assertSameRadius(shape.borderRadius);
        return RawShape(
          type: RawShapeType.roundedRectangle,
          center: center,
          size: size,
          cornerRadius: shape.borderRadius.topLeft.x,
        );
    }
  }

  final RawShapeType type;
  final Offset center;
  final Size size;
  final double cornerRadius;

  Offset get topLeft =>
      Offset(center.dx - size.width / 2, center.dy - size.height / 2);

  Rect get rect => topLeft & size;

  @override
  List<Object?> get props => [type, center, size, cornerRadius];
}

void _assertSameRadius(BorderRadius borderRadius) {
  assert(
    borderRadius.topLeft == borderRadius.topRight &&
        borderRadius.bottomLeft == borderRadius.bottomRight,
    'All corners must have the same radius for a liquid glass shape.',
  );
}

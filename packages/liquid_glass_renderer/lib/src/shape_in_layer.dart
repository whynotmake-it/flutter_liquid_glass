// ignore_for_file: dead_code, deprecated_member_use_from_same_package

import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/src/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/internal/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_renderer/src/liquid_shape.dart';
import 'package:meta/meta.dart';

@internal
enum RawShapeType {
  // none(0), unused in CPU code
  squircle(1),
  ellipse(2),
  roundedRectangle(3);

  const RawShapeType(this.shaderIndex);

  final double shaderIndex;

  static RawShapeType fromLiquidGlassShape(LiquidShape shape) {
    switch (shape) {
      case LiquidRoundedSuperellipse():
        return RawShapeType.squircle;
      case LiquidOval():
        return RawShapeType.ellipse;
      case LiquidRoundedRectangle():
        return RawShapeType.roundedRectangle;
    }
  }
}

/// The geometry of a single shape.
///
/// Can be part of multiple blended shapes in [RenderLiquidGlassGeometry], or on its
/// own.
@internal
class ShapeGeometry extends Equatable {
  ShapeGeometry({
    required this.renderObject,
    required this.shape,
    required this.glassContainsChild,
    required this.shapeBounds,
    this.shapeToGeometry,
  })  : rawCornerRadius = _getRadiusFromGlassShape(shape),
        rawShapeType = RawShapeType.fromLiquidGlassShape(shape);

  static double _getRadiusFromGlassShape(LiquidShape shape) {
    switch (shape) {
      case LiquidRoundedSuperellipse():
        _assertSameRadius(shape.borderRadius);
        return shape.borderRadius.x;
      case LiquidRoundedRectangle():
        _assertSameRadius(shape.borderRadius);
        return shape.borderRadius.x;
      case LiquidOval():
        return 0;
    }
  }

  final RenderLiquidGlass renderObject;

  final LiquidShape shape;

  final RawShapeType rawShapeType;

  final double rawCornerRadius;

  final bool glassContainsChild;

  /// Bounds in geometry-local coordinates (for painting)
  final Rect shapeBounds;

  final Matrix4? shapeToGeometry;

  @override
  List<Object?> get props => [
        renderObject,
        shape,
        glassContainsChild,
        shapeBounds,
      ];
}

/// Shape data in both layer and screen coordinate spaces
@internal
class ShapeInLayerInfo extends Equatable {
  ShapeInLayerInfo({
    required this.renderObject,
    required this.shape,
    required this.glassContainsChild,
    required this.layerBounds,
    required this.relativeLayerBounds,
    required this.screenBounds,
    required this.shapeToLayer,
  })  : rawCornerRadius = _getRadiusFromGlassShape(shape),
        rawShapeType = RawShapeType.fromLiquidGlassShape(shape);

  static double _getRadiusFromGlassShape(LiquidShape shape) {
    switch (shape) {
      case LiquidRoundedSuperellipse():
        _assertSameRadius(shape.borderRadius);
        return shape.borderRadius.x;
      case LiquidRoundedRectangle():
        _assertSameRadius(shape.borderRadius);
        return shape.borderRadius.x;
      case LiquidOval():
        return 0;
    }
  }

  final RenderLiquidGlass renderObject;

  final LiquidShape shape;

  final RawShapeType rawShapeType;

  final double rawCornerRadius;

  final bool glassContainsChild;

  /// Bounds in layer-local coordinates (for painting)
  ///
  // TODO rename
  final Rect layerBounds;

  /// Bounds in layer-relative coordinates
  final RelativeRect relativeLayerBounds;

  /// Bounds in screen coordinates (for geometry texture)
  final Rect screenBounds;

  /// Transform from shape to layer (for painting contents)
  final Matrix4 shapeToLayer;

  @override
  List<Object?> get props => [
        renderObject,
        shape,
        glassContainsChild,
        layerBounds,
        screenBounds,
        shapeToLayer,
      ];
}

void _assertSameRadius(Radius borderRadius) {
  assert(
    borderRadius.x == borderRadius.y,
    'The radius must have equal x and y values for a liquid glass shape.',
  );
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/internal/glass_drag_builder.dart';
import 'package:meta/meta.dart';
import 'package:motor/motor.dart';

/// A widget that provides a squash and stretch effect to its child based on
/// user interaction.
///
/// Will listen to drag gestures from the user without interfering with other
/// gestures.
class LiquidStretch extends StatelessWidget {
  /// Creates a new [LiquidStretch] widget with the given [child],
  /// [interactionScale], and [stretch].
  const LiquidStretch({
    required this.child,
    this.interactionScale = 1.05,
    this.stretch = .5,
    this.resistance = .08,
    this.hitTestBehavior = HitTestBehavior.opaque,
    this.gestureMode = GestureMode.listener,
    super.key,
  });

  /// The scale factor to apply when the user is interacting with the widget.
  ///
  /// A value of 1.0 means no scaling.
  ///
  /// A value greater than 2.0 means the widget will grow to double its
  /// original size.
  ///
  /// A value less than 1.0 means the widget will scale down.
  ///
  /// Defaults to 1.05.
  final double interactionScale;

  /// The factor to multiply the drag offset by to determine the stretch
  /// amount in pixels.
  ///
  /// A value of 0.0 means no stretch, while a value of 1.0 means the stretch
  /// would match the drag offset exactly (which you probably don't want).
  ///
  /// Defaults to 0.5.
  final double stretch;

  /// The resistance factor to apply to the drag offset.
  ///
  /// The higher the resisance, the more sticky the drag will feel.
  /// See [OffsetResistanceExtension.withResistance] for details on how this
  /// works.
  ///
  /// Defaults to 0.08.
  final double resistance;

  /// The hit test behavior for the internal gesture Listener.
  ///
  /// Defaults to [HitTestBehavior.opaque].
  final HitTestBehavior hitTestBehavior;

  /// {@macro gesture_mode}
  ///
  /// Defaults to [GestureMode.listener].
  final GestureMode gestureMode;

  /// The child widget to apply the stretch effect to.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (stretch == 0 && interactionScale == 1.0) {
      return child;
    }

    return GlassDragBuilder(
      behavior: hitTestBehavior,
      gestureMode: gestureMode,
      builder: (context, value, child) {
        final scale = value == null ? 1.0 : interactionScale;
        return SingleMotionBuilder(
          value: scale,
          motion: const Motion.smoothSpring(
            duration: Duration(milliseconds: 300),
            snapToEnd: true,
          ),
          builder: (context, value, child) => Transform.scale(
            scale: value,
            child: child,
          ),
          child: MotionBuilder(
            value: value?.withResistance(resistance) ?? Offset.zero,
            motion: value == null
                ? const Motion.bouncySpring(snapToEnd: true)
                : const Motion.interactiveSpring(snapToEnd: true),
            converter: const OffsetMotionConverter(),
            builder: (context, value, child) => RawLiquidStretch(
              stretchPixels: value * stretch,
              child: child,
            ),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// {@template raw_liquid_stretch}
/// Use this widget to apply a custom stretch effect in pixels to its child.
///
/// You can control the stretch effect by providing an [Offset] in pixels
/// via the [stretchPixels] property.
///
/// If you simply want to apply a stretch effect based on user drag gestures,
/// consider using [LiquidStretch] instead, which provides built-in drag
/// handling and resistance.
/// {@endtemplate}
class RawLiquidStretch extends SingleChildRenderObjectWidget {
  /// {@macro raw_liquid_stretch}
  const RawLiquidStretch({
    required this.stretchPixels,
    required super.child,
    super.key,
  });

  /// The stretch offset in pixels.
  final Offset stretchPixels;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderRawLiquidStretch(stretchPixels: stretchPixels);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderRawLiquidStretch renderObject,
  ) {
    renderObject.stretchPixels = stretchPixels;
  }
}

@internal
class RenderRawLiquidStretch extends RenderProxyBox {
  RenderRawLiquidStretch({
    required Offset stretchPixels,
  }) : _stretchPixels = stretchPixels;

  Offset _stretchPixels;

  /// The stretch offset in pixels.
  Offset get stretchPixels => _stretchPixels;
  set stretchPixels(Offset value) {
    if (_stretchPixels == value) {
      return;
    }
    _stretchPixels = value;
    markNeedsPaint();
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    return hitTestChildren(result, position: position);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final transform = _getEffectiveTransform();
    if (transform == null) {
      return super.hitTestChildren(result, position: position);
    }

    return result.addWithPaintTransform(
      transform: transform,
      position: position,
      hitTest: (BoxHitTestResult result, Offset position) {
        return super.hitTestChildren(result, position: position);
      },
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) {
      return;
    }

    final transform = _getEffectiveTransform();
    if (transform == null) {
      super.paint(context, offset);
      return;
    }

    // Check if the matrix is singular
    final det = transform.determinant();
    if (det == 0 || !det.isFinite) {
      layer = null;
      return;
    }

    layer = context.pushTransform(
      needsCompositing,
      offset,
      transform,
      super.paint,
      oldLayer: layer is TransformLayer ? layer as TransformLayer? : null,
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final effectiveTransform = _getEffectiveTransform();
    if (effectiveTransform != null) {
      transform.multiply(effectiveTransform);
    }
  }

  Matrix4? _getEffectiveTransform() {
    if (_stretchPixels == Offset.zero) {
      return null;
    }

    final scale = getScale(
      stretchPixels: _stretchPixels,
      size: size,
    );

    final matrix = Matrix4.identity()
      // ignore: deprecated_member_use To support older Flutter versions
      ..scale(scale.dx, scale.dy, 1)
      // ignore: deprecated_member_use To support older Flutter versions
      ..translate(_stretchPixels.dx, _stretchPixels.dy);

    return matrix;
  }

  @internal
  Offset getScale({
    required Offset stretchPixels,
    required Size size,
  }) {
    if (size.isEmpty) {
      return const Offset(1, 1);
    }

    final stretchX = stretchPixels.dx.abs();
    final stretchY = stretchPixels.dy.abs();

    // Convert pixel stretch to relative stretch based on size
    final relativeStretchX = size.width > 0 ? stretchX / size.width : 0.0;
    final relativeStretchY = size.height > 0 ? stretchY / size.height : 0.0;

    // Use a consistent stretch factor for both dimensions
    const stretchFactor = 1.0;
    const volumeFactor = 0.5;

    final baseScaleX = 1 + relativeStretchX * stretchFactor;
    final baseScaleY = 1 + relativeStretchY * stretchFactor;

    // Calculate magnitude in relative space for volume preservation
    final magnitude = math.sqrt(
      relativeStretchX * relativeStretchX + relativeStretchY * relativeStretchY,
    );
    final targetVolume = 1 + magnitude * volumeFactor;
    final currentVolume = baseScaleX * baseScaleY;
    final volumeCorrection = math.sqrt(targetVolume / currentVolume);

    final finalScaleX = baseScaleX * volumeCorrection;
    final finalScaleY = baseScaleY * volumeCorrection;

    return Offset(finalScaleX, finalScaleY);
  }
}

/// Provides [withResistance] method to apply drag resistance to an [Offset].
extension OffsetResistanceExtension on Offset {
  /// Returns a new [Offset] with a given [resistance] applied, which will
  /// hold it back the further it deviates from [Offset.zero].
  ///
  /// Applies a non-linear damping effect that reduces the offset's magnitude
  /// while preserving its direction. Higher resistance values create stronger
  /// damping.
  /// Larger offsets are reduced more aggressively than smaller ones,
  /// creating a natural "stretch resistance" effect commonly used in scrolling.
  Offset withResistance(double resistance) {
    if (resistance == 0) return this;

    final magnitude = math.sqrt(dx * dx + dy * dy);
    if (magnitude == 0) return Offset.zero;

    final resistedMagnitude = magnitude / (1 + magnitude * resistance);
    final scale = resistedMagnitude / magnitude;

    return Offset(dx * scale, dy * scale);
  }
}

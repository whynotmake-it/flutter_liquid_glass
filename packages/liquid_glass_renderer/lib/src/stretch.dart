import 'dart:math' as math;

import 'package:flutter/material.dart';
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
    super.key,
  });

  /// The scale factor to apply when the user is interacting with the widget.
  ///
  /// A value of 1.0 means no scaling.
  /// A value greater than 1.0 means the widget will scale up.
  /// A value less than 1.0 means the widget will scale down.
  ///
  /// Defaults to 1.05.
  final double interactionScale;

  /// The factor to multiply the drag offset by to determine the stretch
  /// amount.
  ///
  /// A value of 0.0 means no stretch.
  ///
  /// Defaults to 0.5.
  final double stretch;

  /// The child widget to apply the stretch effect to.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (stretch == 0 && interactionScale == 1.0) {
      return child;
    }

    return GlassDragBuilder(
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
            value: value?.withResistance(.08) ?? Offset.zero,
            motion: value == null
                ? const Motion.bouncySpring(snapToEnd: true)
                : const Motion.interactiveSpring(snapToEnd: true),
            converter: const OffsetMotionConverter(),
            builder: (context, value, child) => _RawGlassStretch(
              stretch: value * stretch,
              child: child!,
            ),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _RawGlassStretch extends StatelessWidget {
  const _RawGlassStretch({
    required this.stretch,
    required this.child,
  });

  final Offset stretch;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scale = getScale(stretch: stretch);
    final matrix = Matrix4.identity()
      ..scaleByDouble(scale.dx, scale.dy, 1, 1)
      ..translateByDouble(stretch.dx, stretch.dy, 0, 1);
    return Transform(
      transform: matrix,
      child: child,
    );
  }
}

/// Creates a jelly transform matrix based on velocity for organic squash and
/// stretch effect.
///
/// [stretch] is the current stretch offset, where positive x means stretching

/// Creates a jelly transform matrix based on velocity for organic squash and
/// stretch effect.
///
/// [stretch] is the current stretch offset, where positive x means stretching
/// to the right, and positive y means stretching downwards.
///
/// A value of 0 means no resistance
@internal
Offset getScale({
  required Offset stretch,
}) {
  final stretchX = stretch.dx.abs();
  final stretchY = stretch.dy.abs();

  const stretchFactor = 0.01;
  const volumeFactor = 0.005;

  final baseScaleX = 1 + stretchX * stretchFactor;
  final baseScaleY = 1 + stretchY * stretchFactor;

  final magnitude = math.sqrt(stretchX * stretchX + stretchY * stretchY);
  final targetVolume = 1 + magnitude * volumeFactor;
  final currentVolume = baseScaleX * baseScaleY;
  final volumeCorrection = math.sqrt(targetVolume / currentVolume);

  final finalScaleX = baseScaleX * volumeCorrection;
  final finalScaleY = baseScaleY * volumeCorrection;

  return Offset(finalScaleX, finalScaleY);
}

extension on Offset {
  Offset withResistance(double resistance) {
    if (resistance == 0) return this;

    final magnitude = math.sqrt(dx * dx + dy * dy);
    if (magnitude == 0) return Offset.zero;

    final resistedMagnitude = magnitude / (1 + magnitude * resistance);
    final scale = resistedMagnitude / magnitude;

    return Offset(dx * scale, dy * scale);
  }
}

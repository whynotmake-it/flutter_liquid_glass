import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

class GlassDragBuilder extends StatefulWidget {
  const GlassDragBuilder({
    required this.builder,
    this.child,
    super.key,
  });

  final ValueWidgetBuilder<Offset?> builder;
  final Widget? child;

  @override
  State<GlassDragBuilder> createState() => _GlassDragBuilderState();
}

class _GlassDragBuilderState extends State<GlassDragBuilder> {
  Offset? currentDragOffset;

  bool get isDragging => currentDragOffset != null;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) => setState(() {
        setState(() {
          currentDragOffset = Offset.zero;
        });
      }),
      onPointerMove: (event) => setState(() {
        currentDragOffset = (currentDragOffset ?? Offset.zero) + event.delta;
      }),
      onPointerUp: (event) => setState(() {
        currentDragOffset = null;
      }),
      child: widget.builder(context, currentDragOffset, widget.child),
    );
  }
}

class GlassStretch extends StatelessWidget {
  const GlassStretch({
    this.interactionScale = 1.05,
    this.stretch = .5,
    required this.child,
    super.key,
  });

  final double interactionScale;
  final double stretch;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GlassDragBuilder(
      builder: (context, value, child) {
        final scale = value == null ? 1.0 : interactionScale;
        return SingleMotionBuilder(
          value: scale,
          motion:
              const Motion.smoothSpring(duration: Duration(milliseconds: 300)),
          builder: (context, value, child) => Transform.scale(
            scale: value,
            child: child,
          ),
          child: MotionBuilder(
            value: value?.withResistance(.08) ?? Offset.zero,
            motion: value == null
                ? const Motion.bouncySpring()
                : const Motion.interactiveSpring(),
            converter: const OffsetMotionConverter(),
            builder: (context, value, child) => RawGlassStretch(
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

class RawGlassStretch extends StatelessWidget {
  const RawGlassStretch({
    required this.stretch,
    required this.child,
    super.key,
  });

  final Offset stretch;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scale = getScale(stretch: stretch);
    final matrix = Matrix4.identity()
      ..scale(scale.dx, scale.dy)
      ..translate(stretch.dx, stretch.dy);
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

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/src/effects/effect_springs.dart';
import 'package:liquid_glass_renderer/src/effects/glass_drag_builder.dart';
import 'package:meta/meta.dart';

/// A widget that provides a squash and stretch effect to its child based on
/// user interaction.
///
/// By default, listens to drag gestures from the user without interfering
/// with other gestures. See [gestureMode].
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
  /// A value of 2.0 means the widget will grow to double its original size.
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
  /// The higher the resistance, the more sticky the drag will feel: a drag
  /// of `d` pixels stretches as `d / (1 + |d| * resistance)` would, keeping
  /// its direction, so larger drags are held back more.
  ///
  /// Defaults to 0.08.
  final double resistance;

  /// The hit test behavior for the internal gesture handler.
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
      builder: (context, drag, child) => _StretchMotion(
        scale: drag == null ? 1.0 : interactionScale,
        offset: drag == null
            ? Offset.zero
            : drag / (1 + drag.distance * resistance),
        dragging: drag != null,
        stretch: stretch,
        child: child,
      ),
      child: child,
    );
  }
}

/// Springs the scale and the stretch of a [LiquidStretch] toward the drag's
/// targets: the stretch follows a finger on the interactive spring and
/// springs back on the bouncy one, the scale settles on a smooth one.
class _StretchMotion extends StatefulWidget {
  const _StretchMotion({
    required this.scale,
    required this.offset,
    required this.dragging,
    required this.stretch,
    required this.child,
  });

  final double scale;
  final Offset offset;
  final bool dragging;
  final double stretch;
  final Widget? child;

  @override
  State<_StretchMotion> createState() => _StretchMotionState();
}

class _StretchMotionState extends State<_StretchMotion>
    with TickerProviderStateMixin {
  static final _scaleSpring = smoothSpring(const Duration(milliseconds: 300));

  late final _scale = AnimationController.unbounded(
    value: widget.scale,
    vsync: this,
  );
  late final _x = AnimationController.unbounded(
    value: widget.offset.dx,
    vsync: this,
  );
  late final _y = AnimationController.unbounded(
    value: widget.offset.dy,
    vsync: this,
  );
  late final _motion = Listenable.merge([_scale, _x, _y]);

  SpringDescription get _offsetSpring =>
      widget.dragging ? interactiveSpring : bouncySpring;

  @override
  void didUpdateWidget(_StretchMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scale != oldWidget.scale) {
      springTo(_scale, _scaleSpring, widget.scale);
    }
    if (widget.dragging != oldWidget.dragging) {
      // A stretch in flight keeps going to the same place on the new spring.
      if (_x.isAnimating) springTo(_x, _offsetSpring, oldWidget.offset.dx);
      if (_y.isAnimating) springTo(_y, _offsetSpring, oldWidget.offset.dy);
    }
    if (widget.offset != oldWidget.offset) {
      springTo(_x, _offsetSpring, widget.offset.dx);
      springTo(_y, _offsetSpring, widget.offset.dy);
    }
  }

  @override
  void dispose() {
    _scale.dispose();
    _x.dispose();
    _y.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _motion,
      builder: (context, child) => Transform.scale(
        scale: _scale.value,
        child: RawLiquidStretch(
          stretchPixels: Offset(_x.value, _y.value) * widget.stretch,
          child: child,
        ),
      ),
      child: widget.child,
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
    required this._stretchPixels,
  });

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

    if (!transform.determinant().isFinite) {
      layer = null;
      return;
    }

    layer = context.pushTransform(
      needsCompositing,
      offset,
      transform,
      super.paint,
      oldLayer: switch (layer) {
        final TransformLayer old => old,
        _ => null,
      },
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

    final scale = _scale();

    // About the center, so opposite drags mirror each other: about the origin
    // right and down stretches travel further, and about the edge opposite
    // the drag that edge jumps when one axis crosses zero. The centered scale
    // moves each edge by about half the stretch, so a translation of 1.5
    // stretches moves the leading edge about twice the stretch and the
    // trailing one about once.
    final center = size.center(Offset.zero);
    final translation = _stretchPixels * 1.5;
    return Matrix4.identity()
      ..translateByDouble(
        center.dx + translation.dx,
        center.dy + translation.dy,
        0,
        1,
      )
      ..scaleByDouble(scale.dx, scale.dy, 1, 1)
      ..translateByDouble(-center.dx, -center.dy, 0, 1);
  }

  Offset _scale() {
    if (size.isEmpty) return const Offset(1, 1);
    final relativeStretchX = _stretchPixels.dx.abs() / size.width;
    final relativeStretchY = _stretchPixels.dy.abs() / size.height;
    final baseScaleX = 1 + relativeStretchX;
    final baseScaleY = 1 + relativeStretchY;
    final magnitude = math.sqrt(
      relativeStretchX * relativeStretchX + relativeStretchY * relativeStretchY,
    );
    final areaGrowth = 1 + magnitude * 0.5;
    final correction = math.sqrt(areaGrowth / (baseScaleX * baseScaleY));
    return Offset(baseScaleX * correction, baseScaleY * correction);
  }
}

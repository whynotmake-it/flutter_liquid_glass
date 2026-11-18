import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/rendering/live_paint_size.dart';

/// Clips its child to [shape] with Impeller's specialized clip layers for
/// ovals, rounded rects and superellipses, or not at all while
/// [clipBehavior] is [Clip.none].
///
/// With a [live] frame the clip follows the frame's shape and rect size at
/// paint instead of [shape] and the layout size.
@internal
class OptimizedClip extends StatelessWidget {
  const OptimizedClip({
    required this.shape,
    required this.clipBehavior,
    required this.child,
    this.outset = 0,
    this.live,
    super.key,
  }) : assert(live == null || outset == 0, 'A live clip has no outset.');

  final LiquidShape shape;

  final Clip clipBehavior;

  /// Extra room outside the widget bounds retained by the clip, which a
  /// [live] clip has none of.
  final double outset;

  /// The live frame whose shape and rect the clip follows at paint.
  final ValueListenable<LiquidGlassShapeFrame>? live;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (clipBehavior == Clip.none) {
      return child;
    }
    if (live case final live?) {
      return _LiveClip(live: live, clipBehavior: clipBehavior, child: child);
    }
    if (outset > 0) {
      return ClipPath(
        clipBehavior: clipBehavior,
        clipper: _OutsetShapeBorderClipper(shape: shape, outset: outset),
        child: child,
      );
    }
    return switch (shape) {
      LiquidRoundedSuperellipse(:final borderRadius) => ClipRSuperellipse(
        clipBehavior: clipBehavior,
        borderRadius: borderRadius,
        child: child,
      ),
      LiquidRoundedRectangle(:final borderRadius) => ClipRRect(
        clipBehavior: clipBehavior,
        borderRadius: borderRadius,
        child: child,
      ),
      LiquidOval() => ClipOval(
        clipBehavior: clipBehavior,
        child: child,
      ),
    };
  }
}

class _OutsetShapeBorderClipper extends CustomClipper<Path> {
  const _OutsetShapeBorderClipper({required this.shape, required this.outset});

  final LiquidShape shape;
  final double outset;

  @override
  Path getClip(Size size) =>
      shape.getOuterPath((Offset.zero & size).inflate(outset));

  @override
  bool shouldReclip(covariant _OutsetShapeBorderClipper oldClipper) =>
      oldClipper.shape != shape || oldClipper.outset != outset;
}

class _LiveClip extends SingleChildRenderObjectWidget {
  const _LiveClip({
    required this.live,
    required this.clipBehavior,
    required super.child,
  });

  final ValueListenable<LiquidGlassShapeFrame> live;
  final Clip clipBehavior;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLiveClip(clipBehavior: clipBehavior)..live = live;

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderLiveClip renderObject,
  ) {
    renderObject
      ..clipBehavior = clipBehavior
      ..live = live;
  }
}

class _RenderLiveClip extends RenderProxyBox with LivePaintSize {
  _RenderLiveClip({required this._clipBehavior});

  Clip _clipBehavior;
  Clip get clipBehavior => _clipBehavior;
  set clipBehavior(Clip value) {
    if (_clipBehavior == value) return;
    _clipBehavior = value;
    markNeedsPaint();
  }

  LiquidShape get _shape => live!.value.shape;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!_shape.getOuterPath(Offset.zero & size).contains(position)) {
      return false;
    }
    return super.hitTest(result, position: position);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) {
      layer = null;
      return;
    }
    // A shape written into a live glass marks the glass to repaint, which
    // repaints this clip below it, so the shape read here is current.
    final shape = _shape;
    final bounds = Offset.zero & paintSize;
    final old = layer;
    layer = switch (shape) {
      LiquidRoundedSuperellipse(:final borderRadius) =>
        context.pushClipRSuperellipse(
          needsCompositing,
          offset,
          bounds,
          borderRadius.toRSuperellipse(bounds),
          super.paint,
          clipBehavior: _clipBehavior,
          oldLayer: old is ClipRSuperellipseLayer ? old : null,
        ),
      LiquidRoundedRectangle(:final borderRadius) => context.pushClipRRect(
        needsCompositing,
        offset,
        bounds,
        borderRadius.toRRect(bounds),
        super.paint,
        clipBehavior: _clipBehavior,
        oldLayer: old is ClipRRectLayer ? old : null,
      ),
      LiquidOval() => context.pushClipPath(
        needsCompositing,
        offset,
        bounds,
        shape.getOuterPath(bounds),
        super.paint,
        clipBehavior: _clipBehavior,
        oldLayer: old is ClipPathLayer ? old : null,
      ),
    };
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/rendering.dart';

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
    required this.child,
    this.clipBehavior = Clip.antiAlias,
    this.outset = 0,
    this.live,
    super.key,
  });

  final LiquidShape shape;

  final Clip clipBehavior;

  /// Extra room outside the widget bounds retained by the clip.
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
      return _LiveClip(
        live: live,
        clipBehavior: clipBehavior,
        outset: outset,
        child: child,
      );
    }
    if (outset > 0) {
      return ClipPath(
        clipBehavior: clipBehavior,
        clipper: _OutsetShapeBorderClipper(shape: shape, outset: outset),
        child: child,
      );
    }
    return switch (shape) {
      LiquidRoundedSuperellipse(:final radii) => ClipRSuperellipse(
        clipBehavior: clipBehavior,
        borderRadius: radii,
        child: child,
      ),
      LiquidRoundedRectangle(:final borderRadius) => ClipRRect(
        clipBehavior: clipBehavior,
        borderRadius: BorderRadius.circular(borderRadius),
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
    required this.outset,
    required super.child,
  });

  final ValueListenable<LiquidGlassShapeFrame> live;
  final Clip clipBehavior;
  final double outset;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLiveClip(clipBehavior: clipBehavior, outset: outset)..live = live;

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderLiveClip renderObject,
  ) {
    renderObject
      ..clipBehavior = clipBehavior
      ..outset = outset
      ..live = live;
  }
}

class _RenderLiveClip extends RenderProxyBox with LivePaintSize {
  _RenderLiveClip({required this._clipBehavior, required this._outset});

  Clip _clipBehavior;
  Clip get clipBehavior => _clipBehavior;
  set clipBehavior(Clip value) {
    if (_clipBehavior == value) return;
    _clipBehavior = value;
    markNeedsPaint();
  }

  double _outset;
  double get outset => _outset;
  set outset(double value) {
    if (_outset == value) return;
    _outset = value;
    markNeedsPaint();
  }

  LiquidShape get _shape => live!.value.shape;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final bounds = (Offset.zero & size).inflate(_outset);
    if (!_shape.getOuterPath(bounds).contains(position)) return false;
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
    final bounds = (Offset.zero & paintSize).inflate(_outset);
    final old = layer;
    layer = switch (shape) {
      LiquidRoundedSuperellipse(:final radii) when _outset == 0 =>
        context.pushClipRSuperellipse(
          needsCompositing,
          offset,
          bounds,
          radii.toRSuperellipse(bounds),
          super.paint,
          clipBehavior: _clipBehavior,
          oldLayer: old is ClipRSuperellipseLayer ? old : null,
        ),
      LiquidRoundedRectangle(:final borderRadius) when _outset == 0 =>
        context.pushClipRRect(
          needsCompositing,
          offset,
          bounds,
          BorderRadius.circular(borderRadius).toRRect(bounds),
          super.paint,
          clipBehavior: _clipBehavior,
          oldLayer: old is ClipRRectLayer ? old : null,
        ),
      _ => context.pushClipPath(
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

import 'package:apple_liquid_glass/foundation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';
import 'package:liquid_glass_renderer/painting.dart';

/// Clips its child to a glass body, so content laid over the glass ends
/// where the renderer draws the glass's edge.
class GlassClip extends StatelessWidget {
  /// Clips [child] to a body of [shape] that fills the child's box.
  const GlassClip({required LiquidShape this.shape, super.key, this.child})
    : frame = null;

  /// Clips [child] to the body each of [frame]'s frames draws in the
  /// child's box: its outline, or its shape where it is drawn. The clip
  /// follows the frames without a rebuild.
  const GlassClip.live({
    required MotionSelection<GlassFrame> this.frame,
    super.key,
    this.child,
  }) : shape = null;

  /// The body of a clip that fills the box, or null for [frame]'s.
  final LiquidShape? shape;

  /// The frames whose bodies clip, or null for [shape]'s.
  final MotionSelection<GlassFrame>? frame;

  /// The clipped widget.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return switch (shape) {
      LiquidRoundedSuperellipse(:final borderRadius) => ClipRSuperellipse(
        borderRadius: borderRadius,
        child: child,
      ),
      LiquidRoundedRectangle(:final borderRadius) => ClipRRect(
        borderRadius: borderRadius,
        child: child,
      ),
      LiquidOval() => ClipOval(child: child),
      null => ClipPath(clipper: _FrameClip(frame!), child: child),
    };
  }
}

class _FrameClip extends CustomClipper<Path> {
  _FrameClip(this.frame) : super(reclip: frame);

  final ValueListenable<GlassFrame> frame;

  @override
  Path getClip(Size size) {
    return frame.value.bodyIn(size).edgeInBox;
  }

  @override
  bool shouldReclip(_FrameClip oldClipper) => oldClipper.frame != frame;
}

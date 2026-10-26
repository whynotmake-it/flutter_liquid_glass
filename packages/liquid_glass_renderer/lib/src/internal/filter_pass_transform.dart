import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/internal/glass_composition_probe.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_capture.dart';
import 'package:meta/meta.dart';

/// Transform from [owner]'s local coordinates to the logical coordinates of
/// the render pass whose fragment coordinates its image filters see.
///
/// Filter fragment coordinates are local to the enclosing render pass. At the
/// root that is the screen; inside a [LiquidGlassCapture] it is the capture's
/// pixel-snapped clip. Inside a seeded fractional-opacity pass ([seeding]) it
/// is that pass, which the engine bounds by the enclosing clips (including
/// any capture's). A seeded pass around the effect itself (never inside a
/// capture) is the innermost: pass [passOrigin], its screen-space top-left, to
/// measure from it. The innermost pass wins. [translation] is retained
/// compositor motion applied below [owner].
@internal
Matrix4 filterPassTransform(
  RenderObject owner, {
  required bool seeding,
  required double devicePixelRatio,
  Offset translation = Offset.zero,
  Offset? passOrigin,
}) {
  final Matrix4 transform;
  final capture = RenderLiquidGlassCapture.enclosing(owner);
  if (passOrigin != null) {
    transform = owner.getTransformTo(null)
      ..leftTranslateByDouble(-passOrigin.dx, -passOrigin.dy, 0, 1);
  } else if (seeding) {
    final origin = GlassCompositionProbe.seededPassOrigin(
      owner,
      devicePixelRatio,
    );
    transform = owner.getTransformTo(null)
      ..leftTranslateByDouble(-origin.dx, -origin.dy, 0, 1);
  } else if (capture != null) {
    transform = owner.getTransformTo(capture);
    final origin = capture.passOrigin;
    transform.leftTranslateByDouble(-origin.dx, -origin.dy, 0, 1);
  } else {
    transform = owner.getTransformTo(null);
  }
  if (translation != Offset.zero) {
    transform.multiply(
      Matrix4.translationValues(translation.dx, translation.dy, 0),
    );
  }
  return transform;
}

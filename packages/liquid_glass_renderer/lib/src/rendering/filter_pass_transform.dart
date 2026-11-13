import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/rendering/follower_transform.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_composition_probe.dart';
import 'package:liquid_glass_renderer/src/rendering/transform_tracking_render_object_mixin.dart';
import 'package:meta/meta.dart';

/// Transform from [owner]'s local coordinates to the logical coordinates of
/// the render pass its image filters run in, plus [translation], retained
/// compositor motion applied below [owner].
///
/// Filter fragment coordinates are local to the innermost enclosing pass: the
/// screen at the root, else a seeded fractional-opacity pass ([seeding])
/// bounded by the enclosing clips.
@internal
Matrix4 filterPassTransform(
  RenderObject owner, {
  required bool seeding,
  required double devicePixelRatio,
  required Offset translation,
}) {
  final Matrix4 transform;
  if (seeding) {
    final origin = GlassCompositionProbe.seededPassOrigin(
      owner,
      devicePixelRatio,
    );
    transform = screenTransformOf(owner)
      ..leftTranslateByDouble(-origin.dx, -origin.dy, 0, 1);
  } else {
    transform = screenTransformOf(owner);
  }
  if (translation != Offset.zero) {
    transform.multiply(
      Matrix4.translationValues(translation.dx, translation.dy, 0),
    );
  }
  return transform;
}

/// [node]'s transform to the screen, taken once a frame while a tracked
/// object composites (see
/// [TransformTrackingRenderObjectMixin.transformToScreen]).
@internal
Matrix4 screenTransformOf(RenderObject node) =>
    node is TransformTrackingRenderObjectMixin
    ? node.transformToScreen()
    : transformToNow(node);

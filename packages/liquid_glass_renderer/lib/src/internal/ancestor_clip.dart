import 'package:flutter/rendering.dart';

/// The clip [ancestor] applies to [child], in [ancestor]'s coordinates, or
/// `null` when it does not clip. Impeller derives a backdrop pass's coverage
/// from these clips, so glass and captures use the same list to predict the
/// pass origin their filters see.
Rect? clipOfAncestor(RenderObject ancestor, RenderObject child) {
  return switch (ancestor) {
    RenderClipRect(:final clipBehavior, :final clipper, :final size) =>
      clipBehavior == Clip.none
          ? null
          : clipper?.getClip(size) ?? Offset.zero & size,
    RenderClipOval(:final clipBehavior, :final clipper, :final size) =>
      clipBehavior == Clip.none
          ? null
          : clipper?.getClip(size) ?? Offset.zero & size,
    RenderClipRRect(:final clipBehavior, :final clipper, :final size) =>
      clipBehavior == Clip.none
          ? null
          : clipper?.getClip(size).outerRect ?? Offset.zero & size,
    RenderClipRSuperellipse(
      :final clipBehavior,
      :final clipper,
      :final size,
    ) =>
      clipBehavior == Clip.none
          ? null
          : clipper?.getClip(size).outerRect ?? Offset.zero & size,
    RenderClipPath(:final clipBehavior, :final clipper, :final size) =>
      clipBehavior == Clip.none
          ? null
          : clipper?.getClip(size).getBounds() ?? Offset.zero & size,
    RenderView(:final size) => Offset.zero & size,
    _ => ancestor.describeApproximatePaintClip(child),
  };
}

/// Intersection of every ancestor clip of [node] in screen coordinates, or
/// `null` when nothing above [node] clips.
Rect? screenClipAbove(RenderObject node) {
  Rect? result;
  var child = node;
  for (
    var ancestor = child.parent;
    ancestor != null;
    child = ancestor, ancestor = ancestor.parent
  ) {
    final clip = clipOfAncestor(ancestor, child);
    if (clip == null) continue;
    final screenClip = MatrixUtils.transformRect(
      ancestor.getTransformTo(null),
      clip,
    );
    result = result?.intersect(screenClip) ?? screenClip;
  }
  return result;
}

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

/// The clip [ancestor] paints around [child], in [ancestor]'s coordinates.
///
/// Unlike [clipOfAncestor], a viewport only counts while its content
/// overflows, mirroring [RenderViewportBase.paint]; its approximate clip API
/// reports per-sliver semantics instead.
Rect? paintClipOfAncestor(RenderObject ancestor, RenderObject child) {
  return switch (ancestor) {
    final RenderViewportBase viewport =>
      // ignore: invalid_use_of_protected_member
      viewport.clipBehavior == Clip.none || !viewport.hasVisualOverflow
          ? null
          : Offset.zero & viewport.size,
    _ => clipOfAncestor(ancestor, child),
  };
}

/// Intersection of the paint clips above [node], in [node]'s coordinates, or
/// `null` when nothing above it clips.
///
/// Walks once to the root, stopping after an ancestor for which [stopAt]
/// returns true. The root view is skipped: its bounds are the screen, which
/// is the texture edge. Clips under a rotation or skew are skipped too, as
/// their bounding box would overstate what they keep.
Rect? localPaintClipAbove(
  RenderObject node, {
  bool Function(RenderObject ancestor)? stopAt,
}) {
  Rect? result;
  var toAncestor = Matrix4.identity();
  var child = node;
  for (
    var ancestor = child.parent;
    ancestor != null && ancestor.parent != null;
    child = ancestor, ancestor = ancestor.parent
  ) {
    final step = Matrix4.identity();
    ancestor.applyPaintTransform(child, step);
    toAncestor = step..multiply(toAncestor);
    final clip = paintClipOfAncestor(ancestor, child);
    if (clip != null && _isRectilinear(toAncestor)) {
      final toNode = Matrix4.tryInvert(toAncestor);
      if (toNode != null) {
        final local = MatrixUtils.transformRect(toNode, clip);
        result = result?.intersect(local) ?? local;
      }
    }
    if (stopAt?.call(ancestor) ?? false) break;
  }
  return result;
}

bool _isRectilinear(Matrix4 transform) {
  final m = transform.storage;
  const epsilon = 1e-9;
  return m[1].abs() < epsilon &&
      m[4].abs() < epsilon &&
      m[3].abs() < epsilon &&
      m[7].abs() < epsilon;
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

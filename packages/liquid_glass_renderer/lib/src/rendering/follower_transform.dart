import 'package:flutter/rendering.dart';
import 'package:meta/meta.dart';

/// What every glass of a frame asks about the same ancestors: their
/// transforms to the screen and whether any clip lies above them, kept at
/// repaint boundaries, where the paths of glass nearby join.
///
/// Holds while the view's composer composes, between paint and the scene,
/// when nothing moves a render object.
@internal
final class FrameAncestors {
  /// The memo of the frame the composer composes, if any.
  static FrameAncestors? current;

  final _transforms = <RenderObject, (Matrix4, bool)>{};
  final Set<RenderObject> _clearAbove = Set.identity();

  /// Whether no clip is painted strictly above [boundary]. Its own clip
  /// depends on the child asking, what lies above it does not.
  bool clearAbove(RenderObject boundary) => _clearAbove.contains(boundary);

  /// Remembers that no clip is painted strictly above [boundary].
  void noteClearAbove(RenderObject boundary) => _clearAbove.add(boundary);

  final Set<RenderObject> _opaqueAbove = Set.identity();

  /// Whether no fractional or zero opacity lies strictly above [boundary], up
  /// to the glass enclosing it.
  bool opaqueAbove(RenderObject boundary) => _opaqueAbove.contains(boundary);

  /// Remembers that no such opacity lies above [boundary].
  void noteOpaqueAbove(RenderObject boundary) => _opaqueAbove.add(boundary);
}

/// [node]'s transform to [ancestor], or to the screen in logical pixels when
/// [ancestor] is null, as [RenderObject.getTransformTo] gives it, except that
/// a follower maps where its leader is in this frame.
///
/// A [FollowerLayer] takes its transform from its leader only when it adds
/// itself to the scene, so [RenderObject.getTransformTo] through a
/// [RenderFollowerLayer] reads the last frame's (identity before the first).
/// Glass decides after paint and before the scene is built, when the
/// leader's layers already hold this frame's offsets.
@internal
Matrix4 transformToNow(RenderObject node, [RenderObject? ancestor]) =>
    transformToNowOrLast(node, ancestor).transform;

/// [transformToNow], and whether a follower on the way could not be mapped
/// yet (before its first frame, or while it repaints and its layer is not in
/// the leader's tree), so the transform holds that follower's last frame.
@internal
({Matrix4 transform, bool last}) transformToNowOrLast(
  RenderObject node, [
  RenderObject? ancestor,
]) {
  final transform = Matrix4.identity();
  final last = _applyFromTop(node, ancestor, transform);
  return (transform: transform, last: last);
}

bool _applyFromTop(
  RenderObject node,
  RenderObject? ancestor,
  Matrix4 transform,
) {
  final parent = node.parent;
  if (parent == null || identical(node, ancestor)) return false;
  // As getTransformTo(null) does, leave out the root view's own transform
  // (the device pixel ratio).
  if (ancestor == null && parent.parent == null) return false;
  final bool last;
  final memo = ancestor == null && parent.isRepaintBoundary
      ? FrameAncestors.current?._transforms
      : null;
  if (memo == null) {
    last = _applyFromTop(parent, ancestor, transform);
  } else if (memo[parent] case (final held, final heldLast)) {
    transform.setFrom(held);
    last = heldLast;
  } else {
    last = _applyFromTop(parent, ancestor, transform);
    memo[parent] = (transform.clone(), last);
  }
  return applyPaintTransformNow(parent, node, transform) || last;
}

/// [parent]'s [RenderObject.applyPaintTransform] for [child], with a
/// follower mapped where its leader is in this frame (see
/// [transformToNow]); returns whether it applied a follower's last frame
/// instead.
@internal
bool applyPaintTransformNow(
  RenderObject parent,
  RenderObject child,
  Matrix4 transform,
) {
  final layer = parent is RenderFollowerLayer ? parent.layer : null;
  final established = layer == null ? null : _established(layer);
  if (established == null) {
    parent.applyPaintTransform(child, transform);
    return parent is RenderFollowerLayer;
  }
  final offset = layer!.unlinkedOffset ?? Offset.zero;
  established.leftTranslateByDouble(-offset.dx, -offset.dy, 0, 1);
  transform.multiply(established);
  return false;
}

/// [layer]'s [ContainerLayer.applyTransform] for [child], with a
/// [FollowerLayer] mapped as [followerTransformNow] maps it.
@internal
void applyTransformNow(ContainerLayer layer, Layer? child, Matrix4 transform) {
  if (layer is FollowerLayer) {
    transform.multiply(followerTransformNow(layer));
  } else {
    layer.applyTransform(child, transform);
  }
}

/// The transform [follower]'s addToScene pushes this frame: from its
/// children's coordinates to its parent's, where its leader is now, or its
/// unlinked offset while it has no leader. Read once [follower] and its
/// leader are painted (see [transformToNow]).
@internal
Matrix4 followerTransformNow(FollowerLayer follower) {
  if (_established(follower) case final established?) return established;
  final offset = follower.unlinkedOffset ?? Offset.zero;
  return Matrix4.translationValues(offset.dx, offset.dy, 0);
}

// What [follower]'s addToScene establishes this frame: the map from its
// children's coordinates to its parent's, or null where that cannot be told
// yet (no leader, a follower not in the leader's tree while it repaints, a
// degenerate map), and Flutter's own last transform stands.
Matrix4? _established(FollowerLayer follower) {
  final leader = follower.link.leader;
  if (leader == null) return null;
  final fromLeader = <ContainerLayer>[];
  for (ContainerLayer? at = leader; at != null; at = at.parent) {
    fromLeader.add(at);
  }
  final fromFollower = <ContainerLayer>[];
  var common = -1;
  for (ContainerLayer? at = follower; at != null; at = at.parent) {
    fromFollower.add(at);
    common = fromLeader.indexWhere((layer) => identical(layer, at));
    if (common >= 0) break;
  }
  if (common < 0) return null;
  final forward = _chain(fromLeader.sublist(0, common + 1));
  leader.applyTransform(null, forward);
  final linked = follower.linkedOffset ?? Offset.zero;
  forward.translateByDouble(linked.dx, linked.dy, 0, 1);
  final inverse = _chain(fromFollower);
  if (inverse.invert() == 0) return null;
  inverse.multiply(forward);
  return inverse;
}

// The map from [layers]'s first to its last, each the child of the next.
Matrix4 _chain(List<ContainerLayer> layers) {
  final transform = Matrix4.identity();
  for (var i = layers.length - 1; i > 0; i--) {
    applyTransformNow(layers[i], layers[i - 1], transform);
  }
  return transform;
}

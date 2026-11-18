import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/widgets.dart';
import 'package:meta/meta.dart';

/// Keeps [motion] told where [source] is, in every frame's resolve phase
/// while it is shown.
@internal
class SourceFollower extends SingleChildRenderObjectWidget {
  /// Tells [motion] where [source] is.
  const SourceFollower({
    required this.source,
    required this.motion,
    super.child,
    super.key,
  });

  /// The source followed.
  final MotionSource source;

  /// The motion told.
  final Sourced motion;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSourceFollower(source, motion);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    final follower = renderObject as _RenderSourceFollower;
    follower.source = source;
    follower.motion = motion;
  }
}

class _RenderSourceFollower extends RenderProxyBox with MotionResolveHost {
  _RenderSourceFollower(this.source, this.motion);

  MotionSource source;
  Sourced motion;
  SourceGeometry? _told;
  bool _first = true;

  @override
  bool get resolvesEveryFrame => true;

  @override
  void resolve() {
    final geometry = source.geometry;
    if (!_first && geometry == _told) return;
    _first = false;
    _told = geometry;
    motion.sourceMoved(motion.clock.now, geometry);
  }
}

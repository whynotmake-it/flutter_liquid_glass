part of 'liquid_glass_render_object.dart';

/// The retained frame of a [LiquidGlassRenderObject], which its subclasses
/// in the rendering library share.
extension LiquidGlassRenderObjectFrame on LiquidGlassRenderObject {
  /// The state the last painted frame committed.
  GlassFrameState get frameState => _frameState;

  /// The shapes the last frame committed, and the ones it draws.
  FrameShapes get frameShapes => _frame;

  /// Collects this frame's shapes into [candidate] without recording pictures
  /// or painting children; returns their bounds in this layer, or null
  /// without any.
  Rect? collectFrameGeometry(List<CommittedGeometry> candidate) {
    Rect? boundingBox;
    link.updatePaintOrder(this);
    final painted = link.painted;
    for (final geometryRo in painted.where(_collects)) {
      final transform = geometryRo.pollRelativeTransforms(this).transform!;
      final geometry = geometryRo.maybeRebuildGeometry(defaultAppearance);
      if (geometry == null) continue;
      candidate.add(CommittedGeometry(geometryRo, geometry, transform));
      final geoBounds = MatrixUtils.transformRect(transform, geometry.bounds);
      boundingBox = boundingBox == null
          ? geoBounds
          : boundingBox.expandToInclude(geoBounds);
    }
    // A shape under a follower that repaints maps it only once the follower
    // is back in its leader's tree, which the compositing poll sees.
    if (!painted.any((shape) => shape.transformMayLag)) _framePoll.markPolled();
    assert(
      debugCheckOpacityBetweenShapesAndLayer(this, link.shapes),
      'Warns about an Opacity between a shape and its layer.',
    );
    return boundingBox;
  }

  /// Commits the collected [candidate] to the retained frame state without
  /// deciding the frame's [GlassFrameState], so retained compositor ticks
  /// can refresh contributors without crossing an idle boundary.
  void commitFrameGeometry(List<CommittedGeometry> candidate) {
    setCompositorTranslation(Offset.zero);
    _frame.commit(candidate);
    _shadows.shapesCommitted();
    _retainedStructure = [
      for (final committed in candidate)
        for (final shape in committed.cache.shapes)
          (
            shape: shape.renderObject,
            castsShadows: shape.shadows.isNotEmpty,
            ancestors: [..._ancestorsOf(shape.renderObject)],
          ),
    ];
    _ancestorClips.update(this, shapeRenderObjects);
    onFrameGeometryCommitted();
  }

  Iterable<RenderObject> _ancestorsOf(RenderObject shape) sync* {
    for (
      var node = shape.parent;
      node != null && !identical(node, this);
      node = node.parent
    ) {
      yield node;
    }
  }

  /// Whether the shapes [collectFrameGeometry] would collect now are at
  /// least one and are the last committed frame's, in its order, with the
  /// same shadows and ancestors: a retained update cannot follow a change of
  /// these, which needs a paint. It records nothing, so it can be asked
  /// before paint.
  bool retainedStructureHolds() {
    final retained = _retainedStructure;
    var at = 0;
    for (final geometry in paintedShapes.where(_collects)) {
      for (final shape in geometry.gatheredShapes) {
        if (at == retained.length) return false;
        final (shape: kept, :castsShadows, :ancestors) = retained[at++];
        if (!identical(kept, shape) ||
            castsShadows != shape.layerShadows.isNotEmpty ||
            !_ancestorsOf(shape).sameAs(ancestors)) {
          return false;
        }
      }
    }
    return at > 0 && at == retained.length;
  }

  /// Whether [geometries] are the encoded inputs
  /// ([CommittedGeometry.sameInputs]).
  bool encodedInputsMatch(List<CommittedGeometry> geometries) {
    final encoded = _encodedGeometryInputs;
    if (geometries.length != encoded.length) return false;
    for (var index = 0; index < geometries.length; index++) {
      if (!geometries[index].sameInputs(encoded[index])) return false;
    }
    return true;
  }
}

bool _collects(RenderLiquidGlassGeometry geometry) =>
    geometry.attached && geometry.hasSize;

typedef _RetainedShape = ({
  RenderObject shape,
  bool castsShadows,
  List<RenderObject> ancestors,
});

extension on Iterable<RenderObject> {
  bool sameAs(List<RenderObject> nodes) {
    var at = 0;
    for (final node in this) {
      if (at == nodes.length || !identical(nodes[at++], node)) return false;
    }
    return at == nodes.length;
  }
}

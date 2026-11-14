part of 'liquid_glass_render_object.dart';

/// The retained frame of a [LiquidGlassRenderObject], which its subclasses
/// in the rendering library share.
extension LiquidGlassRenderObjectFrame on LiquidGlassRenderObject {
  /// The state the last painted frame committed.
  GlassFrameState get frameState => _frameState;

  /// The shapes the last frame committed, in paint order.
  List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)>
  get shapesWithGeometry => _shapesWithGeometry;

  /// Whether [geometries] holds at least one shape this effect can draw (see
  /// [LiquidGlassRenderObject.encodesMatte]).
  bool hasDrawableGlass(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
  ) =>
      !encodesMatte ||
      geometries.any(
        (entry) => entry.$2.shapes.any(
          (shape) => matteShapeBasis(shape, entry.$3) != null,
        ),
      );

  /// Collects this frame's shapes into [candidate] without recording pictures
  /// or painting children; returns their bounds in this layer, or null
  /// without any.
  Rect? collectFrameGeometry(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> candidate,
  ) {
    Rect? boundingBox;
    link.updatePaintOrder(this);
    final painted = paintedShapes;
    // A shape coming back onstage keeps its registration and geometry, so the
    // link would not tell the matte it changed.
    if (!listEquals(painted, _lastPaintedShapes)) link.markDirty();
    _lastPaintedShapes = painted;
    for (final geometryRo in painted) {
      final transformPoll = geometryRo.pollRelativeTransforms(this);
      final geometry = geometryRo.maybeRebuildGeometry();
      final transform = transformPoll.transform;
      if (geometry == null || transform == null) continue;
      candidate.add((geometryRo, geometry, transform));
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
  /// [shapesWithGeometry] is also the compositor-translation poll's
  /// baseline: it always reflects the last painted frame, including idle
  /// and drawable-empty ones.
  void commitFrameGeometry(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> candidate,
  ) {
    setCompositorTranslation(Offset.zero);
    _shapesWithGeometry
      ..clear()
      ..addAll(candidate);
    _shadows.shapesCommitted();
    _retainedStructure = _geometryStructure(candidate);
    _ancestorClips.update(this, shapeRenderObjects);
    onFrameGeometryCommitted();
  }

  /// The structural identity of a frame's geometry: render objects, whether
  /// they carry shadows, and their ancestry to this layer. Retained updates
  /// compare it to detect topology changes that need a normal paint.
  List<Object> _geometryStructure(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
  ) => [
    for (final entry in geometries)
      for (final shape in entry.$2.shapes) ...[
        shape.renderObject,
        shape.shadows.isNotEmpty,
        for (
          var node = shape.renderObject.parent;
          node != null && !identical(node, this);
          node = node.parent
        )
          node,
      ],
  ];

  /// Whether the shapes [collectFrameGeometry] would collect now are at
  /// least one and have the structure of the last committed frame
  /// ([_geometryStructure]), in the paint order the link holds. It records
  /// nothing, so it can be asked before paint.
  bool retainedStructureHolds() {
    final structure = _retainedStructure;
    var at = 0;
    for (final geometry in link.shapes) {
      // Collecting skips a geometry with no transform to this layer.
      if (!geometry.attached ||
          !geometry.hasSize ||
          !isGlassShapePainted(geometry, this)) {
        continue;
      }
      for (final shape in geometry.gatheredShapes) {
        if (at + 2 > structure.length ||
            !identical(structure[at], shape) ||
            structure[at + 1] != shape.layerShadows.isNotEmpty) {
          return false;
        }
        at += 2;
        for (
          var node = shape.parent;
          node != null && !identical(node, this);
          node = node.parent
        ) {
          if (at == structure.length || !identical(structure[at], node)) {
            return false;
          }
          at++;
        }
      }
    }
    return at > 0 && at == structure.length;
  }

  /// Whether [geometries] still matches the encoded inputs exactly: same
  /// render objects, same geometry caches, same transforms.
  bool encodedInputsMatch(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
  ) {
    if (geometries.length != _encodedGeometryInputs.length) return false;
    for (var index = 0; index < geometries.length; index++) {
      final (renderObject, cache, transform) = geometries[index];
      final encoded = _encodedGeometryInputs[index];
      if (!identical(renderObject, encoded.renderObject) ||
          !identical(cache, encoded.cache) ||
          !MatrixUtils.matrixEquals(transform, encoded.transform)) {
        return false;
      }
    }
    return true;
  }
}

final class _EncodedGeometryInput {
  _EncodedGeometryInput(
    this.renderObject,
    this.cache,
    Matrix4 transform,
  ) : transform = transform.clone();

  RenderLiquidGlassGeometry renderObject;
  GeometryCache cache;
  final Matrix4 transform;

  void update(
    RenderLiquidGlassGeometry newRenderObject,
    GeometryCache newCache,
    Matrix4 newTransform,
  ) {
    renderObject = newRenderObject;
    cache = newCache;
    transform.setFrom(newTransform);
  }
}

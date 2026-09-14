// Keep explicit canvas save/translate/draw/restore order easy to audit.
// ignore_for_file: cascade_invocations

part of 'liquid_glass_render_object.dart';

// Scope replay. Live normal children stay in their native ancestry; contained
// holders move between branches. NEST_GLASS_CONTENTS remains excluded.
class _IndependentRealOpacityLayer extends ContainerLayer {
  final _original = LayerHandle<ContainerLayer>(ContainerLayer());
  final _groups = <_RealOpacityGroup>[];
  final _drawableShapes = <RenderBox>{};
  List<RenderObject> _localOpacityScopes = [];
  List<RenderObject> _sharedOpacityScopes = [];
  final _scopeTree = RetainedGlassOpacityTree();
  final _passes = <_RealOpacityPass>[];
  final _retiredFilters = <_RetiredRealOpacityFilter>[];
  _RealOpacityPass? _latestOpaquePass;
  LiquidGlassRenderObject? _owner;
  List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> _geometry = [];
  Offset _offset = Offset.zero;
  Object? _paintKey;

  ContainerLayer get original => _original.layer!;

  void prepare(
    LiquidGlassRenderObject owner,
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometry,
    Offset offset,
  ) {
    final key = (
      owner.settings,
      owner.defaultAppearance,
      owner.devicePixelRatio,
      owner.backdropKey,
      owner.gpuGeometryRenderer,
      offset,
    );
    var same = _paintKey == key && _geometry.length == geometry.length;
    Offset? sharedTranslation;
    if (same) {
      for (var i = 0; i < geometry.length; i++) {
        final delta = _exactOpacityTranslation(_geometry[i].$3, geometry[i].$3);
        if (!identical(_geometry[i].$1, geometry[i].$1) ||
            !identical(_geometry[i].$2, geometry[i].$2) ||
            delta == null ||
            (sharedTranslation != null && delta != sharedTranslation)) {
          same = false;
          break;
        }
        sharedTranslation = delta;
      }
    }
    removeAllChildren();
    if (!same) _clearPasses();
    if (same && sharedTranslation != null && sharedTranslation != Offset.zero) {
      for (final pass in _passes) {
        pass.rebase(sharedTranslation);
      }
      for (final cached in _retiredFilters) {
        cached.placement += sharedTranslation;
      }
    }
    _owner = owner;
    _paintKey = key;
    _geometry = geometry.map((g) => (g.$1, g.$2, g.$3.clone())).toList();
    _offset = offset;
    final previousGroups = _groups.toList();
    _groups.clear();
    _drawableShapes.clear();
    for (final (_, cache, transform) in _geometry) {
      for (final shape in cache.shapes) {
        // Preserve source ancestry even for singular shapes, but never turn
        // a wholly singular scope into an empty isolated SDF pass.
        if (owner._matteShapeBasis(
              transform,
              shape.shapeToGeometry ?? LiquidGlassRenderObject._identity,
            ) !=
            null) {
          _drawableShapes.add(shape.renderObject);
        }
        final scopes = <RenderObject>[];
        for (
          var node = shape.renderObject.parent;
          node != null && !identical(node, owner);
          node = node.parent
        ) {
          if (node is RenderOpacity || node is RenderAnimatedOpacity) {
            scopes.add(node);
          }
        }
        _RealOpacityGroup? group;
        for (final candidate in _groups.reversed.take(1)) {
          if (_sameRealIdentities(candidate.scopes, scopes)) {
            group = candidate;
            break;
          }
        }
        if (group == null) {
          group = _RealOpacityGroup(scopes);
          _groups.add(group);
        }
        group.shapes.add(shape.renderObject);
      }
    }
    _localOpacityScopes = independentGlassOpacityScopes(
      _groups.map((group) => group.scopes),
    );
    _sharedOpacityScopes = _groups.isEmpty
        ? []
        : [
            for (final scope in _groups.first.scopes)
              if (!_localOpacityScopes.contains(scope)) scope,
          ];
    // A reparent can change native clip ancestry without changing geometry.
    if (same) {
      var sameScopes = previousGroups.length == _groups.length;
      for (var i = 0; sameScopes && i < _groups.length; i++) {
        sameScopes =
            _sameRealIdentities(previousGroups[i].scopes, _groups[i].scopes) &&
            _sameRealIdentities(previousGroups[i].shapes, _groups[i].shapes);
      }
      if (!sameScopes) _clearPasses();
    }
    // Repaint may change clip ancestry without changing image inputs. Rewire
    // native/display-list branches lazily, retaining the existing GPU frames.
    for (final pass in _passes) {
      pass.needsRecording = true;
    }
  }

  void sync(Offset translation) {
    final owner = _owner;
    if (owner == null) return;
    // The native outer scope owns its alpha; use its state only to select the
    // presentation. Replaying it in _scopeTree would fade the result twice.
    final externalFractional = owner._compositionProbe.hasFractionalAncestor;
    var opaque = true;
    for (var i = 0; i < _groups.length; i++) {
      final group = _groups[i];
      group.alpha = glassOpacityChainState(
        group.scopes,
        // Full-optics capture can use the original composition when native
        // opacity quantizes to 255. Keep lifetime tied to animation status,
        // not this presentation classification.
      );
      opaque &=
          group.alpha == 255 || !group.shapes.any(_drawableShapes.contains);
    }
    if (opaque && !externalFractional) {
      _selectOriginal();
      return;
    }

    final survivors = <RenderBox>[];
    for (final (_, cache, _) in _geometry) {
      for (final shape in cache.shapes) {
        if (_groups.any(
          (g) => g.alpha == 255 && g.shapes.contains(shape.renderObject),
        )) {
          survivors.add(shape.renderObject);
        }
      }
    }
    final selected = <_RealOpacityPass>[];
    void select(List<RenderBox> shapes, int alpha, {bool hybrid = false}) {
      if (!shapes.any(_drawableShapes.contains)) return;
      _RealOpacityPass? pass;
      for (final candidate in _passes) {
        if (_sameRealIdentities(candidate.shapes, shapes) &&
            candidate.usesCanvasComposition == hybrid) {
          pass = candidate;
          break;
        }
      }
      if (pass == null) {
        for (final candidate in _passes) {
          if (candidate.frame == null &&
              !selected.contains(candidate) &&
              _sameRealIdentities(candidate.shapes, shapes)) {
            // A recovered shader still owns its immutable encoded samplers.
            // Both presentations use that same optics program; switch the
            // layer arrangement instead of encoding the subset again.
            candidate.useCapturePresentation(capture: hybrid);
            pass = candidate;
            break;
          }
        }
      }
      if (pass == null) {
        pass = _buildPass(owner, List.of(shapes), canvasFractional: hybrid);
        _passes.add(pass);
      }
      if (pass.needsRecording) {
        _recordPass(pass, owner);
      }
      pass.layer.alpha = alpha;
      pass.effect.layer!.offset = translation;
      pass.filterClip.layer!.clipRect = pass.bounds
          .inflate(owner._contourOutset)
          .shift(translation)
          .expandToPixelBuckets(owner.devicePixelRatio)
          .shift(_offset - translation);
      pass.layer.seedBounds = owner._paintBounds
          .shift(translation)
          .expandToPixelBuckets(owner.devicePixelRatio)
          .shift(_offset)
          .expandToInclude(
            pass.filterClip.layer!.clipRect!.shift(translation),
          );
      pass.clips.sync();
      pass.syncFilter(owner);
      selected.add(pass);
    }

    // Fractional passes must stay in source order, including opaque sources
    // between them. Keep each run's matte stable throughout alpha-only ticks.
    // At binary endpoints the survivor union retains the original blending.
    final fractional =
        externalFractional ||
        _groups.any(
          (group) =>
              group.alpha > 0 &&
              group.alpha < 255 &&
              group.shapes.any(_drawableShapes.contains),
        );
    final sharedOnly = areGlassOpacityScopesOpaque(_localOpacityScopes);
    if (fractional && sharedOnly) {
      select(
        [
          for (final (_, cache, _) in _geometry)
            for (final shape in cache.shapes) shape.renderObject,
        ],
        255,
        hybrid: true,
      );
    } else if (fractional) {
      for (final group in _groups) {
        if (group.alpha > 0) {
          select(group.shapes, 255, hybrid: true);
        }
      }
    } else if (survivors.isNotEmpty) {
      select(survivors, 255);
      _latestOpaquePass = selected.last;
    }
    if (!fractional) _scopeTree.clear();
    final desired = <Layer>[
      if (fractional)
        _scopeTree.select([
          for (final pass in selected)
            (
              sharedOnly
                  ? _sharedOpacityScopes
                  : _groups
                        .firstWhere(
                          (group) =>
                              _sameRealIdentities(group.shapes, pass.shapes),
                        )
                        .scopes,
              pass.layer,
              pass.layer.seedBounds,
            ),
        ])
      else
        ...selected.map((p) => p.layer),
    ];
    final current = <Layer>[];
    for (var child = firstChild; child != null; child = child.nextSibling) {
      current.add(child);
    }
    if (!_sameRealIdentities(current, desired)) {
      removeAllChildren();
      for (final layer in desired) {
        append(layer);
      }
    }
    for (final pass in selected) {
      pass.syncRefractionCapture(
        owner,
        translation,
        _offset,
        inputBounds: _scopeTree.captureBoundsFor(pass.layer),
      );
    }
    _prunePasses(selected);
  }

  void _selectOriginal() {
    _scopeTree.clear();
    if (!identical(firstChild, original) || !identical(lastChild, original)) {
      removeAllChildren();
      append(original);
    }
    if (_passes.isNotEmpty) _prunePasses(const []);
  }

  _RealOpacityPass _buildPass(
    LiquidGlassRenderObject owner,
    List<RenderBox> shapes, {
    required bool canvasFractional,
  }) {
    final subset = <(RenderLiquidGlassGeometry, GeometryCache, Matrix4)>[];
    Rect? bounds;
    for (final (renderObject, cache, transform) in _geometry) {
      final selected = cache.shapes
          .where((s) => shapes.contains(s.renderObject))
          .toList();
      if (selected.isEmpty) continue;
      var localBounds = selected.first.shapeBounds;
      for (final shape in selected.skip(1)) {
        localBounds = localBounds.expandToInclude(shape.shapeBounds);
      }
      localBounds = selected.length == cache.shapes.length
          ? cache.bounds
          : localBounds
                .inflate(cache.blend * .25)
                .snapToPixels(owner.devicePixelRatio);
      // Keep each original geometry entry: its blend marker starts its own
      // group. A partial group gets its selected bounds and material center.
      subset.add((
        renderObject,
        GeometryCache(
          bounds: localBounds,
          shapes: selected,
          path: cache.path,
          blend: cache.blend,
          matteRevision: cache.matteRevision,
        ),
        transform,
      ));
      final transformed = MatrixUtils.transformRect(transform, localBounds);
      bounds = bounds?.expandToInclude(transformed) ?? transformed;
    }

    if (const bool.fromEnvironment('WEAK_OPACITY_FILTER', defaultValue: true)) {
      for (var i = _retiredFilters.length - 1; i >= 0; i--) {
        final cached = _retiredFilters[i];
        if (_sameRealIdentities(cached.shapes, shapes) &&
            cached.capturesRefraction == canvasFractional) {
          // Transfer to one active owner before permitting uniform updates.
          _retiredFilters.removeAt(i);
          final filter = cached.filter.target;
          final shader = cached.shader.target;
          if (shader != null) {
            GpuAllocationDiagnostics.filterRecoveryHits++;
            final recovered =
                _RealOpacityPass(
                    shapes,
                    null,
                    shader,
                    subset,
                    bounds!,
                    usesCanvasComposition: canvasFractional,
                    capturesRefraction: cached.capturesRefraction,
                  )
                  .._mapping = cached.capturesRefraction || filter == null
                      ? null
                      : cached.mapping
                  .._captureMapping =
                      cached.capturesRefraction && filter != null
                      ? cached.mapping
                      : null
                  ..placement = cached.placement;
            try {
              recovered.backdrop.layer!
                ..filter = filter
                // Capture passes read the sequential enclosing surface, just
                // like fresh passes; only ordinary passes share backdrop input.
                ..backdropKey = cached.capturesRefraction
                    ? null
                    : owner.backdropKey;
              recovered.syncFilter(owner);
              return recovered;
            } catch (_) {
              recovered.dispose();
              rethrow;
            }
          }
        }
      }
      GpuAllocationDiagnostics.filterRecoveryMisses++;
    }

    // The allocator owns the borrowed handles currently used by the owner.
    // Pin BOTH originals before any subset render can replace/dispose them.
    if (!owner._ownsGeometryImages) {
      final geometry = owner._geometryImage!.clone();
      ui.Image? material;
      try {
        material = owner._materialImage?.clone();
      } catch (_) {
        geometry.dispose();
        rethrow;
      }
      owner
        .._geometryImage = geometry
        .._materialImage = material
        .._ownsGeometryImages = true;
    }
    ui.Image? geometry;
    ui.Image? materialImage;
    FragmentShader? shader;
    _RealOpacityPass? pass;
    try {
      late final _GpuGeometryFrame frame;
      _RealOpacityPass? alternate;
      for (final candidate in _passes) {
        if (_sameRealIdentities(candidate.shapes, shapes) &&
            candidate.frame != null) {
          alternate = candidate;
          break;
        }
      }
      final fullSet =
          canvasFractional &&
          _geometry.every(
            (entry) => entry.$2.shapes.every(
              (shape) => shapes.contains(shape.renderObject),
            ),
          );
      if (alternate != null) {
        final encoded = alternate.frame!;
        geometry = encoded.image.clone();
        materialImage = encoded.materialImage?.clone();
        frame = (
          image: geometry,
          materialImage: materialImage,
          matteBounds: encoded.matteBounds,
          materialCenter: encoded.materialCenter,
          appearances: encoded.appearances,
        );
      } else if (fullSet) {
        geometry = owner._geometryImage!.clone();
        materialImage = owner._materialImage?.clone();
        frame = (
          image: geometry,
          materialImage: materialImage,
          matteBounds: owner._geometryMatteBounds,
          materialCenter: owner._materialCenterInMatte,
          appearances: owner._shapeAppearances,
        );
      } else {
        try {
          final borrowed = owner._buildGpuGeometryImage(subset, bounds!);
          geometry = borrowed.image.clone();
          materialImage = borrowed.materialImage?.clone();
          frame = (
            image: geometry,
            materialImage: materialImage,
            matteBounds: borrowed.matteBounds,
            materialCenter: borrowed.materialCenter,
            appearances: List<LiquidGlassAppearance>.unmodifiable(
              borrowed.appearances,
            ),
          );
        } finally {
          // Also release partial borrowed output when allocation/cloning fails.
          // Owner-pinned originals are independent of these allocator handles.
          owner.gpuGeometryRenderer!.releaseOutput();
        }
      }
      final (mixed, tintOnly, uniform) = _classifyShapeAppearances(
        frame.appearances,
        owner.defaultAppearance,
      );
      final programIndex = !mixed
          ? 0
          : tintOnly
          ? 2
          : 1;
      final program = owner.independentOpacityPrograms![programIndex];
      shader = program.fragmentShader();
      pass = _RealOpacityPass(
        shapes,
        frame,
        shader,
        subset,
        bounds!,
        usesCanvasComposition: canvasFractional,
        capturesRefraction: canvasFractional,
      )..placement = alternate?.placement ?? Offset.zero;
      {
        final boundShader = shader;
        owner._writeCommonShaderUniforms(
          boundShader,
          uniform ?? owner.defaultAppearance,
          frame.materialCenter,
        );
        boundShader
          ..setFloatUniforms(initialIndex: 2, (value) {
            value
              ..setOffset(frame.matteBounds.topLeft * owner.devicePixelRatio)
              ..setSize(frame.matteBounds.size * owner.devicePixelRatio);
          })
          ..setImageSampler(1, frame.image);
        if (frame.materialImage != null) {
          final material = frame.materialImage!;
          if (tintOnly) {
            boundShader.setImageSampler(
              2,
              material,
              filterQuality: FilterQuality.low,
            );
          } else {
            boundShader
              ..setImageSampler(2, material)
              ..setImageSampler(3, material, filterQuality: FilterQuality.low);
          }
        }
        if (canvasFractional) {
          boundShader
            ..setImageSampler(0, frame.image)
            ..setFloat(0, 1)
            ..setFloat(1, 1);
          owner._writeCoordinateMapping(boundShader, (
            owner.devicePixelRatio,
            0,
            0,
            owner.devicePixelRatio,
            0,
            0,
          ));
        }
      }
      pass.syncFilter(owner);
      return pass;
    } catch (_) {
      if (pass != null) {
        pass.dispose();
      } else {
        shader?.dispose();
        geometry?.dispose();
        materialImage?.dispose();
      }
      rethrow;
    }
  }

  void _recordPass(_RealOpacityPass pass, LiquidGlassRenderObject owner) {
    pass.layer.removeAllChildren();
    pass.clips.update(owner, pass.shapes);
    final context = PaintingContext(
      pass.layer,
      owner._paintBounds.shift(_offset),
    );
    // pushLayer finishes the child context's shadow recording before returning.
    // This outer context never obtains a canvas or starts its own recording.
    pass.clips.pushLayer(context, pass.effect.layer!, (context, offset) {
      owner._paintLayerShadows(context, offset, pass.subset);
      pass.filterClip.layer = context.pushClipRect(
        true,
        offset,
        pass.bounds
            .inflate(owner._contourOutset)
            .expandToPixelBuckets(owner.devicePixelRatio),
        (context, offset) {
          context.pushLayer(pass.backdrop.layer!, (_, _) {}, offset);
        },
      );
    }, _offset);
    pass.needsRecording = false;
  }

  // At most G isolated passes plus the current/latest survivor union. Keeping
  // an unselected pass preserves its cache without attaching it to the scene.
  void _prunePasses(List<_RealOpacityPass> selected) {
    if (_passes.isEmpty) return;
    _RealOpacityGroup? isolatedGroup(_RealOpacityPass pass) {
      for (final group in _groups) {
        if (_sameRealIdentities(pass.shapes, group.shapes)) return group;
      }
      return null;
    }

    // The latest survivor slot may alias an isolated pass. In particular an
    // unchanged opaque sibling must survive a transient all-alpha255 frame.
    // Replacing this slot never retains historical unions or builds a pass.
    final unfinished = _groups.any(
      (group) => isUnfinishedGlassOpacityChain(group.scopes),
    );
    final externalUnfinished = _owner!._compositionProbe.hasUnfinishedAncestor;
    for (var i = _passes.length - 1; i >= 0; i--) {
      final pass = _passes[i];
      if (selected.contains(pass)) continue;
      final group = isolatedGroup(pass);
      final retainExternal =
          externalUnfinished &&
          pass.usesCanvasComposition &&
          (group == null || !group.scopes.any(isSettledTransparentGlassScope));
      final retain =
          retainExternal ||
          (group != null
              ? isUnfinishedGlassOpacityChain(group.scopes) ||
                    (unfinished && group.alpha == 255)
              : unfinished && identical(pass, _latestOpaquePass));
      if (!retain) {
        if (identical(pass, _latestOpaquePass)) _latestOpaquePass = null;
        final preserveShader =
            const bool.fromEnvironment(
              'WEAK_OPACITY_FILTER',
              defaultValue: true,
            ) &&
            (!pass.usesCanvasComposition || pass.capturesRefraction) &&
            pass.layer.hasSubmitted &&
            pass.backdrop.layer?.filter != null;
        if (preserveShader) {
          _retiredFilters
            ..removeWhere(
              (cached) =>
                  _sameRealIdentities(cached.shapes, pass.shapes) &&
                  cached.capturesRefraction == pass.capturesRefraction,
            )
            ..add(
              _RetiredRealOpacityFilter(
                List.of(pass.shapes),
                (pass.capturesRefraction
                    ? pass._captureMapping
                    : pass._mapping)!,
                WeakReference(pass.backdrop.layer!.filter!),
                WeakReference(pass.shader),
                pass.placement,
                capturesRefraction: pass.capturesRefraction,
              ),
            );
          if (_retiredFilters.length > _groups.length + 1) {
            _retiredFilters.removeAt(0);
          }
        }
        _passes.removeAt(i).dispose(preserveShader: preserveShader);
      }
    }
  }

  void _clearPasses({bool keepRetiredFilters = false}) {
    if (!keepRetiredFilters) _retiredFilters.clear();
    _scopeTree.clear();
    _latestOpaquePass = null;
    for (final pass in _passes) {
      pass.dispose();
    }
    _passes.clear();
  }

  void releaseHiddenPasses() {
    // Restore holder ownership before disposing the no-longer-submitted
    // passes. Keep the original branch ready for a later fade-in.
    _selectOriginal();
    // The hidden tree and image handles are released normally. Weak entries
    // own no resources and may serve a later fade of unchanged geometry.
    _clearPasses(
      // ignore: avoid_redundant_argument_values
      keepRetiredFilters: const bool.fromEnvironment(
        'WEAK_OPACITY_FILTER',
        defaultValue: true,
      ),
    );
  }

  @override
  void dispose() {
    removeAllChildren();
    _clearPasses();
    _original.layer = null;
    _scopeTree.dispose();
    _owner = null;
    _geometry = [];
    _groups.clear();
    _drawableShapes.clear();
    _localOpacityScopes = [];
    super.dispose();
  }
}

bool _sameRealIdentities(List<Object> a, List<Object> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!identical(a[i], b[i])) return false;
  }
  return true;
}

// Conservative translation-only reuse; perspective and changed bases miss.
Offset? _exactOpacityTranslation(Matrix4 before, Matrix4 after) {
  if (MatrixUtils.matrixEquals(before, after)) return Offset.zero;
  final a = before.storage;
  final b = after.storage;
  if (a[3] != 0 || a[7] != 0 || a[11] != 0 || a[15] != 1) return null;
  for (var i = 0; i < 16; i++) {
    if (i != 12 && i != 13 && a[i] != b[i]) return null;
  }
  final delta = Offset(b[12] - a[12], b[13] - a[13]);
  return delta.dx.isFinite && delta.dy.isFinite ? delta : null;
}

class _RealOpacityGroup {
  _RealOpacityGroup(this.scopes);
  final List<RenderObject> scopes;
  final shapes = <RenderBox>[];
  int alpha = 255;
}

class _RetiredRealOpacityFilter {
  _RetiredRealOpacityFilter(
    this.shapes,
    this.mapping,
    this.filter,
    this.shader,
    this.placement, {
    this.capturesRefraction = false,
  });
  final List<RenderBox> shapes;
  final (double, double, double, double, double, double) mapping;
  final WeakReference<ImageFilter> filter;
  final WeakReference<FragmentShader> shader;
  final bool capturesRefraction;
  Offset placement;
}

class _RealOpacityPass {
  _RealOpacityPass(
    this.shapes,
    this.frame,
    this.shader,
    this.subset,
    this.bounds, {
    this.usesCanvasComposition = false,
    this.capturesRefraction = false,
  });
  final List<RenderBox> shapes;
  final _GpuGeometryFrame? frame;
  final FragmentShader shader;
  bool usesCanvasComposition;
  bool capturesRefraction;
  FragmentShader? get refractionShader => capturesRefraction ? shader : null;
  final List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> subset;
  Rect bounds;
  Offset placement = Offset.zero;
  bool needsRecording = true;
  final _handle = LayerHandle<_RealScopeAlphaLayer>(_RealScopeAlphaLayer());
  final effect = LayerHandle<OffsetLayer>(OffsetLayer());
  final backdrop = LayerHandle<BackdropFilterLayer>(BackdropFilterLayer());
  final filterClip = LayerHandle<ClipRectLayer>();
  final clips = RetainedGlassClip(includeOpacity: false);
  (double, double, double, double, double, double)? _mapping;
  (double, double, double, double, double, double)? _captureMapping;
  _RealScopeAlphaLayer get layer => _handle.layer!;

  void useCapturePresentation({required bool capture}) {
    usesCanvasComposition = capture;
    capturesRefraction = capture;
    _mapping = null;
    _captureMapping = null;
    backdrop.layer!
      ..filter = null
      ..backdropKey = null;
    needsRecording = true;
  }

  void syncRefractionCapture(
    LiquidGlassRenderObject owner,
    Offset translation,
    Offset paintOffset, {
    Rect? inputBounds,
  }) {
    final shader = refractionShader;
    final capture = backdrop.layer;
    if (shader == null || capture == null) return;
    // Sample the enclosing seed, whose input origin need not equal the output
    // filter clip. Local scopes supply seed bounds; external input bounds come
    // from ancestor clips and the enclosing view. Geometry stays encoded.
    final captureBounds =
        inputBounds?.shift(-paintOffset) ?? Offset.zero & owner.size;
    final ownerToScreen = owner.getTransformTo(null);
    var screenCaptureBounds = inputBounds != null
        ? MatrixUtils.transformRect(ownerToScreen, captureBounds)
        : null;
    RenderObject child = owner;
    // A containing owner's seed already establishes the input surface. Clips
    // between it and this owner still constrain native painting, but must not
    // relocate its texture origin (notably nested glass child clips).
    RenderObject? enclosingSeed;
    if (inputBounds == null) {
      for (var node = owner.parent; node != null; node = node.parent) {
        if (node is LiquidGlassRenderObject &&
            node._compositionProbe.hasActiveSeed) {
          enclosingSeed = node;
          break;
        }
      }
    }
    var insideSeed = enclosingSeed != null;
    for (
      var ancestor = child.parent;
      ancestor != null;
      child = ancestor, ancestor = ancestor.parent
    ) {
      if (insideSeed) {
        if (!identical(ancestor, enclosingSeed)) continue;
        insideSeed = false;
      }
      final clip = ancestor is RenderClipRect
          ? (ancestor.clipBehavior == Clip.none
                ? null
                : ancestor.clipper?.getClip(ancestor.size) ??
                      Offset.zero & ancestor.size)
          : ancestor is RenderClipOval
          ? (ancestor.clipBehavior == Clip.none
                ? null
                : ancestor.clipper?.getClip(ancestor.size) ??
                      Offset.zero & ancestor.size)
          : ancestor is RenderClipRRect
          ? (ancestor.clipBehavior == Clip.none
                ? null
                : ancestor.clipper?.getClip(ancestor.size).outerRect ??
                      Offset.zero & ancestor.size)
          : ancestor is RenderClipRSuperellipse
          ? (ancestor.clipBehavior == Clip.none
                ? null
                : ancestor.clipper?.getClip(ancestor.size).outerRect ??
                      Offset.zero & ancestor.size)
          : ancestor is RenderClipPath
          ? (ancestor.clipBehavior == Clip.none
                ? null
                : ancestor.clipper?.getClip(ancestor.size).getBounds() ??
                      Offset.zero & ancestor.size)
          : ancestor is RenderView
          ? Offset.zero & ancestor.size
          : ancestor.describeApproximatePaintClip(child);
      if (clip != null) {
        final screenClip = MatrixUtils.transformRect(
          ancestor.getTransformTo(null),
          clip,
        );
        screenCaptureBounds =
            screenCaptureBounds?.intersect(screenClip) ?? screenClip;
      }
    }
    final inputOrigin = screenCaptureBounds == null
        ? captureBounds.topLeft
        : MatrixUtils.transformPoint(
            Matrix4.inverted(ownerToScreen),
            screenCaptureBounds.topLeft,
          );
    final origin =
        (inputOrigin - translation - placement) * owner.devicePixelRatio;
    final basis = owner._currentCoordinateMapping();
    final mapping = (
      basis.$1,
      basis.$2,
      basis.$3,
      basis.$4,
      origin.dx,
      origin.dy,
    );
    if (_captureMapping == mapping) return;
    _captureMapping = mapping;
    owner._writeCoordinateMapping(shader, mapping);
    final optics = ImageFilter.shader(shader);
    capture.filter = owner.settings.effectiveFrost > 0
        ? ImageFilter.compose(
            inner: ImageFilter.blur(
              sigmaX: owner.settings.effectiveFrost,
              sigmaY: owner.settings.effectiveFrost,
              tileMode: TileMode.mirror,
            ),
            outer: optics,
          )
        : optics;
  }

  void rebase(Offset delta) {
    placement += delta;
    bounds = bounds.shift(delta);
    for (var i = 0; i < subset.length; i++) {
      final entry = subset[i];
      subset[i] = (
        entry.$1,
        entry.$2,
        Matrix4.translationValues(delta.dx, delta.dy, 0)..multiply(entry.$3),
      );
    }
    needsRecording = true;
  }

  void syncFilter(LiquidGlassRenderObject owner) {
    if (usesCanvasComposition) {
      if (backdrop.layer!.filter != null) return;
      backdrop.layer!.filter = owner.settings.effectiveFrost > 0
          ? ImageFilter.blur(
              sigmaX: owner.settings.effectiveFrost,
              sigmaY: owner.settings.effectiveFrost,
              tileMode: TileMode.mirror,
            )
          : const ColorFilter.mode(Colors.white, BlendMode.modulate);
      return;
    }
    final current = owner._currentCoordinateMapping();
    // Keep UVs and optical material center in the original encoded frame.
    final mapping = (
      current.$1,
      current.$2,
      current.$3,
      current.$4,
      current.$5 - placement.dx * owner.devicePixelRatio,
      current.$6 - placement.dy * owner.devicePixelRatio,
    );
    if (_mapping == mapping) {
      return;
    }
    _mapping = mapping;
    layer.hasSubmitted = false;
    owner._writeCoordinateMapping(shader, mapping);
    final filter = ImageFilter.shader(shader);
    final frost = owner.settings.effectiveFrost;
    final material = frost > 0
        ? ImageFilter.compose(
            inner: ImageFilter.blur(
              sigmaX: frost,
              sigmaY: frost,
              tileMode: TileMode.mirror,
            ),
            outer: filter,
          )
        : filter;
    backdrop.layer!
      ..filter = material
      ..backdropKey = owner.backdropKey;
  }

  void dispose({bool preserveShader = false}) {
    clips.dispose();
    if (GpuAllocationDiagnostics.enabled && backdrop.layer?.filter != null) {
      GpuAllocationDiagnostics.observe('retired_pass', this);
      GpuAllocationDiagnostics.observe('retired_layer', backdrop.layer!);
      GpuAllocationDiagnostics.observe('filter', backdrop.layer!.filter!);
    }
    effect.layer = null;
    backdrop.layer = null;
    filterClip.layer = null;
    _handle.layer = null;
    // The materialized filter already owns this shader and the same sampler
    // textures. Weak recovery adds no strong root or additional matte texture.
    // Otherwise release immediately, as on the ordinary invalidation path.
    if (!preserveShader) shader.dispose();
    frame?.image.dispose();
    frame?.materialImage?.dispose();
  }
}

class _RealScopeAlphaLayer extends ContainerLayer {
  bool hasSubmitted = false;
  Rect? _seedBounds;
  Rect? get seedBounds => _seedBounds;
  set seedBounds(Rect value) {
    if (_seedBounds == value) return;
    _seedBounds = value;
    markNeedsAddToScene();
  }

  int _alpha = 255;
  int get alpha => _alpha;
  set alpha(int value) {
    if (_alpha == value) return;
    _alpha = value;
    markNeedsAddToScene();
  }

  @override
  void addToScene(SceneBuilder builder) {
    if (_alpha == 255) {
      engineLayer = null;
      addChildrenToScene(builder);
      hasSubmitted = true;
      return;
    }
    final previous = engineLayer;
    engineLayer = builder.pushOpacity(
      _alpha,
      oldLayer: previous is OpacityEngineLayer ? previous : null,
    );
    final clip = _seedBounds == null
        ? null
        : builder.pushClipRect(_seedBounds!, clipBehavior: Clip.hardEdge);
    final seed = builder.pushBackdropFilter(
      const ColorFilter.matrix([
        1,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ]),
    );
    addChildrenToScene(builder);
    builder.pop();
    if (_seedBounds != null) builder.pop();
    builder.pop();
    // The native parent owns these children. Only its opacity handle is
    // retained for reuse; unused handles otherwise pin old subtrees until GC.
    seed.dispose();
    clip?.dispose();
    hasSubmitted = true;
  }
}

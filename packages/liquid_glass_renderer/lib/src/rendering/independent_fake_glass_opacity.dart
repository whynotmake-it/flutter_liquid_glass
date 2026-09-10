part of 'consolidated_fake_glass_layer.dart';

// Experimental retained replay. Ordinary foreground remains in its
// original render/layer ancestry. There are no extra native passes at alpha 1.
class _IndependentFakeOpacityLayer extends ContainerLayer {
  int debugRecordedPassCount = 0;
  final _original = LayerHandle<ContainerLayer>(ContainerLayer());
  final _passes = <_FakeOpacityPass>[];
  _FakeOpacityPass? _latestOpaquePass;
  final _groups = <_FakeOpacityGroup>[];
  List<RenderObject> _localOpacityScopes = [];
  final _scopeTree = RetainedGlassOpacityTree();
  RenderConsolidatedFakeGlassLayer? _owner;
  List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> _geometry = [];
  Offset _offset = Offset.zero;

  ContainerLayer get original => _original.layer!;

  void prepare(
    RenderConsolidatedFakeGlassLayer owner,
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometry,
    Offset offset,
  ) {
    removeAllChildren();
    _clearPasses();
    _owner = owner;
    _geometry = geometry;
    _offset = offset;
    // Rebuild identity chains only when paint refreshes the source metadata.
    _groups.clear();
    for (final (_, geometry, _) in _geometry) {
      for (final shape in geometry.shapes) {
        final scopes = <RenderObject>[];
        var ancestor = shape.renderObject.parent;
        while (ancestor != null && !identical(ancestor, owner)) {
          if (ancestor is RenderOpacity || ancestor is RenderAnimatedOpacity) {
            scopes.add(ancestor);
          }
          ancestor = ancestor.parent;
        }
        _FakeOpacityGroup? group;
        for (final candidate in _groups.reversed.take(1)) {
          if (_sameFakeIdentities(candidate.scopes, scopes)) {
            group = candidate;
            break;
          }
        }
        if (group == null) {
          group = _FakeOpacityGroup(scopes);
          _groups.add(group);
        }
        group.shapes.add(shape.renderObject);
      }
    }
    _localOpacityScopes = independentGlassOpacityScopes(
      _groups.map((group) => group.scopes),
    );
  }

  // Called by the preceding tracking sentinel BEFORE subtree dirtiness is
  // propagated. Alpha-only changes never request a late RenderObject repaint.
  void sync(Offset translation) {
    final owner = _owner;
    if (owner == null) return;
    var allOpaque = true;
    // Index loops keep the steady opaque path free of temporary collections
    // and iterators. Only cached scope objects are sampled, not ancestry.
    for (var i = 0; i < _groups.length; i++) {
      final group = _groups[i];
      group.alpha = glassOpacityChainState(group.scopes);
      allOpaque &= group.alpha == 255;
    }
    if (allOpaque ||
        (const bool.fromEnvironment(
              'HOIST_GLASS_OPACITY',
              defaultValue: true,
            ) &&
            areGlassOpacityScopesOpaque(_localOpacityScopes))) {
      _scopeTree.clear();
      if (!identical(firstChild, original) || !identical(lastChild, original)) {
        removeAllChildren();
        append(original);
      }
      if (_passes.isNotEmpty) _prunePasses(const []);
      return;
    }

    // Opaque survivors must share ONE filter/shadow pass, just as an
    // independently built survivor-only scene does. Fractional scope replay
    // is an approximation where independently filtered scopes overlap.
    final opaque = <RenderBox>[];
    for (final (_, geometry, _) in _geometry) {
      for (final shape in geometry.shapes) {
        if (_groups.any(
          (g) => g.alpha == 255 && g.shapes.contains(shape.renderObject),
        )) {
          opaque.add(shape.renderObject);
        }
      }
    }
    final selected = <_FakeOpacityPass>[];
    void select(List<RenderBox> shapes, int alpha) {
      _FakeOpacityPass? pass;
      for (final candidate in _passes) {
        if (_sameFakeIdentities(candidate.shapes, shapes)) {
          pass = candidate;
          break;
        }
      }
      if (pass == null) {
        pass = _FakeOpacityPass(List.of(shapes));
        _recordPass(pass, owner);
        _passes.add(pass);
      }
      pass.layer.alpha = alpha;
      pass.effect.layer!.offset = translation;
      pass.layer.seedBounds = owner._paintBounds
          .shift(translation)
          .expandToPixelBuckets(_geometry.first.$1.devicePixelRatio)
          .shift(_offset);
      pass.clips.sync();
      selected.add(pass);
    }

    // Keep fractional composition in source order; do not move an opaque
    // foreground behind an earlier fading source. Cache stable source runs.
    final fractional = _groups.any(
      (group) => group.alpha > 0 && group.alpha < 255,
    );
    if (fractional) {
      for (final group in _groups) {
        if (group.alpha > 0) select(group.shapes, 255);
      }
    } else if (opaque.isNotEmpty) {
      select(opaque, 255);
      _latestOpaquePass = selected.last;
    }
    if (!fractional) _scopeTree.clear();
    final desired = <Layer>[
      if (fractional)
        _scopeTree.select([
          for (final pass in selected)
            (
              _groups
                  .firstWhere(
                    (group) => _sameFakeIdentities(group.shapes, pass.shapes),
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
    if (!_sameFakeIdentities(current, desired)) {
      removeAllChildren();
      for (final layer in desired) {
        append(layer);
      }
    }
    _prunePasses(selected);
  }

  void _recordPass(
    _FakeOpacityPass pass,
    RenderConsolidatedFakeGlassLayer owner,
  ) {
    assert(() {
      debugRecordedPassCount++;
      return true;
    }(), 'Track lazy subset recording, not per-frame material work.');
    final subset = <(RenderLiquidGlassGeometry, GeometryCache, Matrix4)>[];
    final path = Path();
    Rect? bounds;
    for (final (renderObject, geometry, transform) in _geometry) {
      final shapes = geometry.shapes
          .where((shape) => pass.shapes.contains(shape.renderObject))
          .toList();
      if (shapes.isEmpty) continue;
      subset.add((
        renderObject,
        GeometryCache(
          bounds: geometry.bounds,
          shapes: shapes,
          path: geometry.path,
          blend: geometry.blend,
          matteRevision: geometry.matteRevision,
        ),
        transform,
      ));
      for (final shape in shapes) {
        if (shape.appearance.visibility <= 0) continue;
        final matrix = shape.shapeToGeometry == null
            ? transform
            : transform.multiplied(shape.shapeToGeometry!);
        final rect = Offset.zero & shape.renderObject.size;
        final transformed = MatrixUtils.transformRect(matrix, rect);
        bounds = bounds?.expandToInclude(transformed) ?? transformed;
        path.addPath(
          shape.shape.getOuterPath(rect),
          Offset.zero,
          matrix4: matrix.storage,
        );
      }
    }
    final materialBounds = bounds;
    if (materialBounds == null) return;
    pass.clips.update(owner, pass.shapes);
    final context = PaintingContext(
      pass.layer,
      owner._paintBounds.shift(_offset),
    );
    // The outer context only appends layers; it never starts a recorder.
    // RetainedGlassClip always pushes the effect via PaintingContext.pushLayer,
    // which finalizes this callback's child context after the surfaces below.
    pass.clips.pushLayer(context, pass.effect.layer!, (context, offset) {
      owner._paintShadows(context, offset, subset);
      if (owner._hasBackdropEffect) {
        context.pushClipPath(true, offset, materialBounds, path, (
          context,
          offset,
        ) {
          context.pushLayer(
            BackdropFilterLayer(
              filter: owner._cachedFilter ??= owner._buildBackdropFilter(),
            )..backdropKey = owner.backdropKey,
            (_, _) {},
            offset,
          );
        });
      }
      owner._paintSurfaces(context.canvas, offset, subset);
    }, _offset);
  }

  // At most G isolated passes plus the current/latest survivor union. Keeping
  // an unselected pass preserves its cache without attaching it to the scene.
  void _prunePasses(List<_FakeOpacityPass> selected) {
    if (_passes.isEmpty) return;
    _FakeOpacityGroup? isolatedGroup(_FakeOpacityPass pass) {
      for (final group in _groups) {
        if (_sameFakeIdentities(pass.shapes, group.shapes)) return group;
      }
      return null;
    }

    // The latest survivor slot may alias an isolated pass. In particular an
    // unchanged opaque sibling must survive a transient all-alpha255 frame.
    // Replacing this slot never retains historical unions or builds a pass.
    final unfinished = _groups.any(
      (group) => isUnfinishedGlassOpacityChain(group.scopes),
    );
    for (var i = _passes.length - 1; i >= 0; i--) {
      final pass = _passes[i];
      if (selected.contains(pass)) continue;
      final group = isolatedGroup(pass);
      final retain = group != null
          ? isUnfinishedGlassOpacityChain(group.scopes) ||
                (unfinished && group.alpha == 255)
          : unfinished && identical(pass, _latestOpaquePass);
      if (!retain) {
        if (identical(pass, _latestOpaquePass)) _latestOpaquePass = null;
        _passes.removeAt(i).dispose();
      }
    }
  }

  void _clearPasses() {
    _scopeTree.clear();
    _latestOpaquePass = null;
    for (final pass in _passes) {
      pass.dispose();
    }
    _passes.clear();
  }

  @override
  void dispose() {
    removeAllChildren();
    _clearPasses();
    _original.layer = null;
    _scopeTree.dispose();
    _owner = null;
    _groups.clear();
    _localOpacityScopes = [];
    _geometry = [];
    super.dispose();
  }
}

bool _sameFakeIdentities(List<Object> a, List<Object> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!identical(a[i], b[i])) return false;
  }
  return true;
}

class _FakeOpacityGroup {
  _FakeOpacityGroup(this.scopes);
  final List<RenderObject> scopes;
  int alpha = 255;
  final shapes = <RenderBox>[];
}

class _FakeOpacityPass {
  _FakeOpacityPass(this.shapes);
  final List<RenderBox> shapes;
  final _handle = LayerHandle<_FakeScopeAlphaLayer>(_FakeScopeAlphaLayer());
  final effect = LayerHandle<OffsetLayer>(OffsetLayer());
  // This pass's alpha already includes all below-owner opacity ancestors.
  // Replaying their common opacity inside the clips would apply alpha twice.
  final clips = RetainedGlassClip(includeOpacity: false);
  _FakeScopeAlphaLayer get layer => _handle.layer!;
  void dispose() {
    clips.dispose();
    effect.layer = null;
    _handle.layer = null;
  }
}

class _FakeScopeAlphaLayer extends ContainerLayer {
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
    // Fractional native opacity needs the backdrop present in its buffer.
    // Only the temporary fading pass incurs this experimental seed.
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
  }
}

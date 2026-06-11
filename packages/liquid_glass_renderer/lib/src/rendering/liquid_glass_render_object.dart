import 'dart:collection';
import 'dart:math';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_renderer/src/internal/snap_rect_to_pixels.dart';
import 'package:liquid_glass_renderer/src/logging.dart';
import 'package:meta/meta.dart';

/// A render object that can assemble [RenderLiquidGlassGeometry] shapes and
/// render them to the screen with the liquid glass effect.
@internal
abstract class LiquidGlassRenderObject extends RenderProxyBox {
  LiquidGlassRenderObject({
    required this._link,
    required this.renderShader,
    required LiquidGlassSettings this._settings,
    required this._devicePixelRatio,
    required this._backdropKey,
  }) {
    _updateShaderSettings();
  }

  static final logger = Logger(LgrLogNames.render);

  final FragmentShader renderShader;

  /// The size that the geometry texture should have.
  Size get desiredMatteSize;

  Matrix4 get matteTransform;

  late GeometryRenderLink _link;
  GeometryRenderLink get link => _link;
  set link(GeometryRenderLink value) {
    if (_link == value) return;
    markNeedsPaint();
    _link = value;
  }

  LiquidGlassSettings? _settings;
  LiquidGlassSettings get settings => _settings!;
  set settings(LiquidGlassSettings value) {
    if (_settings == value) return;
    _settings = value;
    _updateShaderSettings();
    markNeedsPaint();
  }

  BackdropKey? _backdropKey;
  BackdropKey? get backdropKey => _backdropKey;
  set backdropKey(BackdropKey? value) {
    if (_backdropKey == value) return;
    _backdropKey = value;
  }

  double _devicePixelRatio;
  double get devicePixelRatio => _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => _geometryImage != null;

  /// Pre-rendered geometry texture in screen space
  ui.Image? _geometryImage;

  /// The bounding box of the geometry matte in the coordinate space of the
  /// shader
  Rect _geometryMatteBounds = Rect.zero;

  /// The [matteTransform] that was used when [_geometryImage] was last baked.
  ///
  /// Used to detect translation-only changes, in which case the existing
  /// texture can be reused (only the screen-space offset uniform changes)
  /// instead of re-rasterizing.
  Matrix4? _lastBakedMatteTransform;

  /// The [matteTransform] observed on the *previous* paint.
  ///
  /// Drives the direct-render animation heuristic. Unlike
  /// [_lastBakedMatteTransform] (which is reset whenever the baked texture is
  /// cleared, e.g. on entering direct mode), this is updated on every frame so
  /// motion detection stays continuous across path switches. Anchoring the
  /// heuristic to the baked transform instead makes the renderer oscillate
  /// between the direct and texture paths mid-animation, which is visible as
  /// jitter (most noticeably at lower refresh rates).
  Matrix4? _previousMatteTransform;

  /// How many consecutive frames the geometry has been in *actual motion*
  /// (a full shape rebuild or a non-translation transform change).
  ///
  /// Used to detect a *sustained* animation before switching to the
  /// texture-less direct render path. A single one-off change re-bakes once
  /// (keeping static renders pixel-identical to the two-pass pipeline) rather
  /// than briefly flipping to direct mode.
  int _consecutiveMotionFrames = 0;

  /// The pre-rendered geometry texture in screen space.
  ///
  /// Exposed for subclasses that render additional passes (such as the separate
  /// specular layer) from the same geometry texture.
  @protected
  ui.Image? get geometryImage => _geometryImage;

  /// The bounding box of the geometry matte in screen space.
  ///
  /// Exposed for subclasses that need to map the geometry texture into their
  /// own coordinate space.
  @protected
  Rect get geometryMatteBounds => _geometryMatteBounds;

  @override
  @mustCallSuper
  void attach(PipelineOwner owner) {
    super.attach(owner);
  }

  @override
  @mustCallSuper
  void detach() {
    super.detach();
  }

  @override
  void layout(Constraints constraints, {bool parentUsesSize = false}) {
    needsGeometryUpdate = true;
    super.layout(constraints, parentUsesSize: parentUsesSize);
  }

  void _updateShaderSettings() {
    renderShader.setFloatUniforms(initialIndex: 6, (value) {
      value
        ..setColor(settings.effectiveGlassColor)
        ..setFloats([
          settings.refractiveIndex,
          settings.effectiveChromaticAberration,
          settings.effectiveThickness,
          settings.effectiveLightIntensity,
          settings.effectiveAmbientStrength,
          settings.effectiveSaturation,
        ])
        ..setOffset(
          Offset(
            cos(settings.lightAngle),
            sin(settings.lightAngle),
          ),
        )
        ..setColor(settings.effectiveHighlightColor)
        ..setColor(settings.effectiveEdgeColor)
        ..setFloats([
          settings.effectiveEdgeWidth,
          settings.edgeInset,
          settings.effectiveBleedStrength,
          settings.specularWrap,
        ]);
    });
  }

  ui.Rect _paintBounds = ui.Rect.zero;

  @override
  ui.Rect get paintBounds => _paintBounds;

  // MARK: Painting

  @override
  @nonVirtual
  void paint(PaintingContext context, Offset offset) {
    logger.finest(
      '$hashCode Painting liquid glass with '
      '${link._shapeGeometries.length} shapes.',
    );

    final shapesWithGeometry =
        <(RenderLiquidGlassGeometry, GeometryCache, Matrix4)>[];

    Rect? boundingBox;

    // Reset before gathering so the top loop's full rebuilds (if any) set it
    // fresh for this frame's animation detection.
    link._hadFullRebuild = false;

    for (final geometryRo in link.shapes) {
      final geometry = geometryRo.maybeRebuildGeometry();

      if (geometry == null) continue;

      final transform = geometryRo.getTransformTo(this);
      shapesWithGeometry.add((geometryRo, geometry, transform));

      final geoBounds = MatrixUtils.transformRect(
        transform,
        geometry.bounds,
      );
      boundingBox = boundingBox == null
          ? geoBounds
          : boundingBox.expandToInclude(geoBounds);
    }

    if (boundingBox == null) {
      _clearGeometryImage();

      super.paint(context, offset);
      return;
    }

    _paintBounds = boundingBox;

    if (settings.effectiveThickness <= 0) {
      _clearGeometryImage();
      paintShapeContents(
        context,
        offset,
        shapesWithGeometry,
        insideGlass: true,
      );
      paintShapeContents(
        context,
        offset,
        shapesWithGeometry,
        insideGlass: false,
      );
      super.paint(context, offset);
      return;
    }

    final currentMatteTransform = matteTransform;

    // Whether the composite texture must be (re)built this frame for any
    // reason (layout, transform, a per-shape matte (re)bake, or no texture).
    final compositeNeedsRebuild =
        needsGeometryUpdate || _geometryImage == null || link._dirty;

    final transformChanged =
        _lastBakedMatteTransform == null ||
        !MatrixUtils.matrixEquals(
          _lastBakedMatteTransform,
          currentMatteTransform,
        );

    final translationOnlyChange =
        _lastBakedMatteTransform != null &&
        transformChanged &&
        _differsByTranslationOnly(
          _lastBakedMatteTransform!,
          currentMatteTransform,
        );

    // "Actual motion" excludes the one-time deferred matte bake (which sets
    // link._dirty but does not change visible geometry) and pure translation
    // (handled by the cheaper reuse path). It is what drives the animation
    // heuristic for switching to the texture-less direct render path.
    //
    // Crucially this compares against the *previous frame's* transform, not the
    // last baked one: the baked transform is reset when the texture is cleared
    // (which happens every time direct mode engages), so anchoring motion
    // detection there would break continuity and make the renderer flip-flop
    // between direct and texture paths every few frames during a sustained
    // animation — visible as jitter.
    final motionTransformChanged =
        _previousMatteTransform != null &&
        !MatrixUtils.matrixEquals(
          _previousMatteTransform,
          currentMatteTransform,
        );
    final nonTranslationMotion =
        motionTransformChanged &&
        !_differsByTranslationOnly(
          _previousMatteTransform!,
          currentMatteTransform,
        );
    final actualMotionThisFrame =
        link._hadFullRebuild || nonTranslationMotion;

    if (actualMotionThisFrame) {
      _consecutiveMotionFrames++;
    } else {
      _consecutiveMotionFrames = 0;
    }
    _previousMatteTransform = currentMatteTransform.clone();

    // Fast path: if no shape geometry actually changed and the layer only
    // moved (translation), the displacement field in the existing texture is
    // identical. Reuse it and just shift the matte bounds so the final shader
    // samples it at the new screen position. This makes translating a
    // full-screen glass element (e.g. an animated sheet) allocation-free.
    final canReuseByTranslation =
        compositeNeedsRebuild &&
        _geometryImage != null &&
        !link._hadFullRebuild &&
        translationOnlyChange;

    // Direct mode: while geometry is actively changing in a way that would
    // otherwise force an expensive composite re-bake every frame, render the
    // glass inline from shape uniforms instead, allocating no texture at all.
    //
    // We only engage this once geometry has been in actual motion for at least
    // two consecutive frames (a sustained animation). A single one-off change
    // just re-bakes once via the texture path, so static renders stay
    // pixel-identical to the two-pass pipeline. It also requires the layer to
    // support direct rendering (single axis-aligned blend group) and is never
    // used in geometry-debug mode.
    final directUniforms =
        _consecutiveMotionFrames >= 2 &&
            !canReuseByTranslation &&
            !debugPaintLiquidGlassGeometry
        ? gatherDirectShapeUniforms()
        : null;

    if (directUniforms != null) {
      // Free the (now stale) baked texture so it does not linger during the
      // animation, and consume the change flags so that the first settled
      // frame triggers a single re-bake back onto the cheap texture path.
      _clearGeometryImage();
      link._dirty = false;
      needsGeometryUpdate = false;

      paintLiquidGlassDirect(
        context,
        offset,
        shapesWithGeometry,
        _paintBounds,
        directUniforms,
      );

      super.paint(context, offset);
      return;
    }

    // Phase 6: a sparse single blend group splits into disjoint components,
    // each rendered as its own tight, texture-less direct pass instead of one
    // big union-AABB composite texture.
    final components = debugPaintLiquidGlassGeometry
        ? null
        : gatherDirectComponents();
    if (components != null) {
      _clearGeometryImage();
      link
        ..updateAllGeometries()
        .._dirty = false;
      needsGeometryUpdate = false;

      paintLiquidGlassComponents(
        context,
        offset,
        shapesWithGeometry,
        _paintBounds,
        components,
      );

      super.paint(context, offset);
      return;
    }

    // Phase 3: for a single blend group whose transform to the screen is a
    // pure translation, sample its matte directly instead of compositing it
    // into a second screen-space texture. This skips the composite
    // `toImageSync` entirely (one texture instead of two) and keeps
    // translating the group allocation-free.
    final directGroup = _directGroupSamplerTarget(shapesWithGeometry);

    if (directGroup != null) {
      // No composite is produced; the group matte is sampled straight from the
      // final shader. We still keep the per-shape geometry caches coherent.
      if (compositeNeedsRebuild) {
        link
          ..updateAllGeometries()
          .._dirty = false;
        needsGeometryUpdate = false;
      }
      _clearGeometryImage();
      _lastBakedMatteTransform = currentMatteTransform;
    } else if (canReuseByTranslation) {
      needsGeometryUpdate = false;
      _geometryMatteBounds = _shiftMatteBounds(
        _geometryMatteBounds,
        _lastBakedMatteTransform!,
        currentMatteTransform,
      );
      _lastBakedMatteTransform = currentMatteTransform;
    } else if (compositeNeedsRebuild) {
      link.updateAllGeometries();
      _clearGeometryImage();
      link._dirty = false;

      needsGeometryUpdate = false;

      final (image, matteBounds) = _buildGeometryImage(
        shapesWithGeometry,
        boundingBox,
      );

      _geometryImage = image;
      _geometryMatteBounds = matteBounds;
      _lastBakedMatteTransform = currentMatteTransform;
    }

    if (debugPaintLiquidGlassGeometry) {
      _debugPaintGeometry(context, offset);
      paintShapeContents(
        context,
        offset,
        shapesWithGeometry,
        insideGlass: true,
      );
      paintShapeContents(
        context,
        offset,
        shapesWithGeometry,
        insideGlass: false,
      );
    } else {
      final sampler = directGroup != null
          ? _resolveDirectGroupSampler(directGroup)
          : (_geometryImage != null
                ? _GeometrySampler(
                    image: _geometryImage!,
                    outBoundsLogical: _geometryMatteBounds,
                    texSizePhysical:
                        _geometryMatteBounds.size * devicePixelRatio,
                    insetPhysical: Offset.zero,
                  )
                : null);

      if (sampler != null) {
        renderShader
          ..setFloatUniforms(initialIndex: 2, (value) {
            value
              ..setOffset(sampler.outBoundsLogical.topLeft * devicePixelRatio)
              ..setSize(sampler.outBoundsLogical.size * devicePixelRatio);
          })
          ..setFloatUniforms(initialIndex: 30, (value) {
            value
              ..setOffset(sampler.insetPhysical)
              ..setSize(sampler.texSizePhysical);
          })
          ..setImageSampler(1, sampler.image);
        paintLiquidGlass(
          context,
          offset,
          shapesWithGeometry,
          _paintBounds,
        );
      }
    }

    super.paint(context, offset);
  }

  /// Returns the single blend group that can be sampled directly (without a
  /// composite) this frame, or `null` if the single-group direct-sampling fast
  /// path does not apply.
  RenderLiquidGlassGeometry? _directGroupSamplerTarget(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)>
    shapesWithGeometry,
  ) {
    if (debugPaintLiquidGlassGeometry) return null;
    if (shapesWithGeometry.length != 1) return null;
    final (group, _, _) = shapesWithGeometry.first;
    // Only a pure translation maps the group matte onto an axis-aligned screen
    // rect with unchanged displacement magnitudes; any scale/rotation falls
    // back to the composite (and, while animating, to direct-uniform mode).
    if (!_isTranslationOnly(group.getTransformTo(null))) return null;
    return group;
  }

  /// Resolves the matte image, its (logical) screen-space output bounds and
  /// the nine-slice mapping for the single-group direct-sampling path.
  _GeometrySampler? _resolveDirectGroupSampler(
    RenderLiquidGlassGeometry group,
  ) {
    final rendered = group.ensureRenderedMatte();
    if (rendered == null) return null;

    final translation = group.getTransformTo(null).getTranslation();
    final matteBounds = rendered.matteBounds; // physical, group-local (full)

    // Expressed in logical units so the shared `* devicePixelRatio` uniform
    // multiply reproduces the exact physical output rect on screen. This is
    // the *full* shape region; with nine-slicing the actual texture is smaller
    // and the shader remaps coordinates into it.
    final outBoundsLogical = Rect.fromLTWH(
      matteBounds.left / devicePixelRatio + translation.x,
      matteBounds.top / devicePixelRatio + translation.y,
      matteBounds.width / devicePixelRatio,
      matteBounds.height / devicePixelRatio,
    );

    final nineSlice = rendered.nineSlice;
    return _GeometrySampler(
      image: rendered.matte,
      outBoundsLogical: outBoundsLogical,
      texSizePhysical:
          nineSlice?.textureSize ?? matteBounds.size * rendered.resolutionScale,
      insetPhysical: nineSlice == null
          ? Offset.zero
          : Offset(nineSlice.inset, nineSlice.inset),
    );
  }

  void _clearGeometryImage() {
    _geometryImage?.dispose();
    _geometryImage = null;
    _lastBakedMatteTransform = null;
  }

  /// Whether [m] is a pure translation (identity 2D linear part, no scale,
  /// rotation, skew or perspective).
  static bool _isTranslationOnly(Matrix4 m) {
    const eps = 1e-3;
    final s = m.storage;
    if ((s[0] - 1).abs() > eps || (s[5] - 1).abs() > eps) return false;
    if (s[1].abs() > eps || s[4].abs() > eps) return false;
    if (s[2].abs() > eps ||
        s[6].abs() > eps ||
        s[8].abs() > eps ||
        s[9].abs() > eps) {
      return false;
    }
    if ((s[10] - 1).abs() > eps) return false;
    if (s[3].abs() > eps || s[7].abs() > eps || s[11].abs() > eps) return false;
    return true;
  }

  /// Whether [a] and [b] are equal apart from their translation component, i.e.
  /// they have the same rotation, scale and skew.
  static bool _differsByTranslationOnly(Matrix4 a, Matrix4 b) {
    final sa = a.storage;
    final sb = b.storage;
    for (var i = 0; i < 16; i++) {
      // Skip the translation column (x = 12, y = 13, z = 14).
      if (i == 12 || i == 13 || i == 14) continue;
      if ((sa[i] - sb[i]).abs() > 1e-6) return false;
    }
    return true;
  }

  /// Shifts [bounds] by the translation delta between [from] and [to], keeping
  /// the size pixel-identical and snapping the origin to the physical pixel
  /// grid.
  ///
  /// Keeping the size constant is important: the underlying texture is not
  /// re-rasterized, so its pixel dimensions must keep matching `uGeometrySize`.
  Rect _shiftMatteBounds(Rect bounds, Matrix4 from, Matrix4 to) {
    final tFrom = from.getTranslation();
    final tTo = to.getTranslation();
    final shifted = bounds.shift(
      ui.Offset(tTo.x - tFrom.x, tTo.y - tFrom.y),
    );
    final snappedLeft =
        (shifted.left * devicePixelRatio).roundToDouble() / devicePixelRatio;
    final snappedTop =
        (shifted.top * devicePixelRatio).roundToDouble() / devicePixelRatio;
    return ui.Offset(snappedLeft, snappedTop) & bounds.size;
  }

  /// Subclasses implement the actual glass rendering
  /// (e.g., with backdrop filters)
  void paintLiquidGlass(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> shapes,
    Rect boundingBox,
  );

  /// Gathers screen-space shape uniforms for the inline "direct" render path,
  /// or `null` when direct rendering is not applicable for this render object.
  ///
  /// Returning `null` (the default) keeps the texture-based pipeline.
  @protected
  List<double>? gatherDirectShapeUniforms() => null;

  /// Renders the glass directly from [directUniforms] without a pre-computed
  /// geometry texture.
  ///
  /// Only invoked when [gatherDirectShapeUniforms] returned a non-null value,
  /// so the default implementation simply asserts.
  @protected
  void paintLiquidGlassDirect(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> shapes,
    Rect boundingBox,
    List<double> directUniforms,
  ) {
    assert(false, 'paintLiquidGlassDirect called without an implementation');
  }

  /// Splits the geometry into connected components for independent direct
  /// render passes, or `null` (the default) to keep the single-pass pipeline.
  @protected
  List<DirectComponent>? gatherDirectComponents() => null;

  /// Renders each connected [components] entry as its own direct pass.
  ///
  /// Only invoked when [gatherDirectComponents] returned a non-null value.
  @protected
  void paintLiquidGlassComponents(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> shapes,
    Rect boundingBox,
    List<DirectComponent> components,
  ) {
    assert(false, 'paintLiquidGlassComponents called without implementation');
  }

  @protected
  void paintShapeContents(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> shapes, {
    required bool insideGlass,
  }) {
    for (final (geometryRenderObject, _, _) in shapes) {
      geometryRenderObject.paintShapeContents(
        this,
        context,
        offset,
        insideGlass: insideGlass,
      );
    }
  }

  void _debugPaintGeometry(PaintingContext context, Offset offset) {
    if (_geometryImage case final geometryImage?) {
      final backToThis = Matrix4.inverted(matteTransform).storage;
      final bounds = MatrixUtils.transformRect(
        matteTransform,
        paintBounds,
      ).snapToPixels(devicePixelRatio);
      context.canvas
        ..save()
        ..transform(backToThis)
        ..translate(
          bounds.left,
          bounds.top,
        )
        ..scale(1 / devicePixelRatio)
        ..drawImage(
          geometryImage,
          offset * devicePixelRatio,
          Paint()..blendMode = BlendMode.src,
        )
        ..restore();
    }
  }

  @override
  @mustCallSuper
  void dispose() {
    _clearGeometryImage();
    super.dispose();
  }

  // MARK: Geometry

  @protected
  bool needsGeometryUpdate = true;

  (ui.Image, Rect) _buildGeometryImage(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
    Rect bounds,
  ) {
    final boundsInMatteSpace = MatrixUtils.transformRect(
      matteTransform,
      bounds,
    ).snapToPixels(devicePixelRatio);

    final size = boundsInMatteSpace.size * devicePixelRatio;

    final buffer = StringBuffer(
      '$hashCode Built geometry image with '
      '${geometries.length} shapes at size ${size.width}x${size.height}:\n',
    );

    final recorder = ui.PictureRecorder();

    final canvas = Canvas(recorder);

    for (final (_, geometry, transform) in geometries) {
      canvas
        ..save()
        ..scale(devicePixelRatio)
        ..translate(
          -boundsInMatteSpace.left,
          -boundsInMatteSpace.top,
        )
        ..transform(matteTransform.storage)
        ..transform(transform.storage)
        ..scale(1 / devicePixelRatio)
        ..translate(
          geometry.matteBounds.topLeft.dx,
          geometry.matteBounds.topLeft.dy,
        );

      switch (geometry) {
        case UnrenderedGeometryCache(matte: final picture):
          buffer.writeln(
            '\t- Unrendered @ ${geometry.bounds}',
          );
          canvas.drawPicture(picture);
        case RenderedGeometryCache(matte: final image):
          buffer.writeln(
            '\t- Rendered @ ${geometry.bounds}',
          );
          final nineSlice = geometry.nineSlice;
          if (nineSlice != null) {
            // Expand the reduced border matte back to the full region via
            // nine-patch; the surrounding canvas transform handles any
            // rotation/scale of the shape.
            final tex = nineSlice.textureSize;
            canvas.drawImageNine(
              image,
              Rect.fromLTRB(
                nineSlice.inset,
                nineSlice.inset,
                tex.width - nineSlice.inset,
                tex.height - nineSlice.inset,
              ),
              Rect.fromLTWH(
                0,
                0,
                geometry.matteBounds.width,
                geometry.matteBounds.height,
              ),
              Paint(),
            );
          } else if (geometry.resolutionScale != 1.0) {
            // Upscale the reduced-resolution matte back to its full bounds.
            canvas.drawImageRect(
              image,
              Rect.fromLTWH(
                0,
                0,
                image.width.toDouble(),
                image.height.toDouble(),
              ),
              Rect.fromLTWH(
                0,
                0,
                geometry.matteBounds.width,
                geometry.matteBounds.height,
              ),
              Paint()..filterQuality = FilterQuality.low,
            );
          } else {
            canvas.drawImage(image, Offset.zero, Paint());
          }
      }

      canvas.restore();
    }

    final picture = recorder.endRecording();
    final image = picture.toImageSync(
      size.width.ceil(),
      size.height.ceil(),
    );

    logger.fine(buffer.toString());
    picture.dispose();
    return (image, boundsInMatteSpace);
  }
}

/// Resolved inputs for one liquid-glass geometry sampling pass.
class _GeometrySampler {
  _GeometrySampler({
    required this.image,
    required this.outBoundsLogical,
    required this.texSizePhysical,
    required this.insetPhysical,
  });

  /// The geometry matte texture to sample.
  final ui.Image image;

  /// The output region in logical coordinates (becomes `uGeometryOffset` /
  /// `uGeometrySize` after multiplying by the device pixel ratio).
  final Rect outBoundsLogical;

  /// The actual texture size in physical pixels (`uNineSliceTexSize`). Equal to
  /// `outBoundsLogical.size * dpr` when not nine-sliced (identity mapping).
  final Size texSizePhysical;

  /// The fixed nine-slice border in physical pixels (`uNineSliceInset`).
  /// [Offset.zero] disables remapping.
  final Offset insetPhysical;
}

@internal
class GeometryRenderLink {
  final List<RenderLiquidGlassGeometry> _shapeGeometries = [];

  UnmodifiableListView<RenderLiquidGlassGeometry> get shapes =>
      UnmodifiableListView(_shapeGeometries);

  bool _dirty = false;

  /// Whether any shape went through a *full* geometry rebuild this frame, i.e.
  /// its shape data / blend / settings actually changed.
  ///
  /// This is distinct from [_dirty], which is also set by the one-time deferred
  /// `Picture` to `Image` bake of an otherwise unchanged matte. Only genuine
  /// changes count as "motion" for the direct-render animation heuristic.
  bool _hadFullRebuild = false;

  void updateAllGeometries() {
    for (final renderObject in _shapeGeometries) {
      renderObject.maybeRebuildGeometry();
    }
  }

  void registerGeometry(
    RenderLiquidGlassGeometry renderObject,
  ) {
    _dirty = true;
    _shapeGeometries.add(renderObject);
  }

  /// Marks the composite as needing a rebuild because a matte was baked, but
  /// without signalling actual geometry motion.
  void markRebuilt(RenderLiquidGlassGeometry renderObject) {
    _dirty = true;
  }

  /// Marks that [renderObject] performed a full geometry rebuild because its
  /// shape data actually changed.
  void markFullRebuild(RenderLiquidGlassGeometry renderObject) {
    _dirty = true;
    _hadFullRebuild = true;
  }

  void unregisterGeometry(RenderLiquidGlassGeometry renderObject) {
    _shapeGeometries.remove(renderObject);
  }

  void dispose() {
    _shapeGeometries.clear();
  }
}

@internal
class InheritedGeometryRenderLink extends InheritedWidget {
  const InheritedGeometryRenderLink({
    required this.link,
    required super.child,
    super.key,
  });

  final GeometryRenderLink link;

  static GeometryRenderLink? of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<InheritedGeometryRenderLink>()
        ?.link;
  }

  @override
  bool updateShouldNotify(covariant InheritedGeometryRenderLink oldWidget) {
    return oldWidget.link != link;
  }
}

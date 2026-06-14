import 'dart:ui';

import 'package:equatable/equatable.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/snap_rect_to_pixels.dart';
import 'package:liquid_glass_renderer/src/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_blend_group.dart';
import 'package:liquid_glass_renderer/src/logging.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';
import 'package:meta/meta.dart';

/// The state of liquid glass geometry, used to determine if it needs to be
/// updated.
enum LiquidGlassGeometryState {
  /// The geometry is up to date and does not need to be updated.
  updated,

  /// The geometry might need to be updated, but could potentially be reused.
  ///
  /// This happens mainly when all of the geometry itself is unchanged, but all
  /// of the geometry has been uniformly transformed.
  ///
  /// In this case, we can use the existing geometry matte and transform it to
  /// save GPU cycles.
  mightNeedUpdate,

  /// The geometry definitely needs to be updated.
  needsUpdate,
}

/// A base class for any render object that represents liquid glass geometry.
///
/// This will paint to the screen normally, but use a [GlassGroupLink] to gather
/// shape information and generate a geometry matte using the provided
/// [geometryShader].
@internal
abstract class RenderLiquidGlassGeometry extends RenderProxyBox {
  /// Creates a new [RenderLiquidGlassGeometry] with the given
  /// [geometryShader].
  RenderLiquidGlassGeometry({
    required GeometryRenderLink this._renderLink,
    required this.geometryShader,
    required LiquidGlassSettings settings,
    required double devicePixelRatio,
  }) : _settings = settings,
       _devicePixelRatio = devicePixelRatio {
    updateShaderWithSettings(settings, devicePixelRatio);
  }

  /// The logger for liquid glass geometry.
  final Logger logger = Logger(LgrLogNames.geometry);

  /// The shader that generates the geometry matte.
  final FragmentShader geometryShader;

  LiquidGlassSettings? _settings;

  /// The settings used for liquid glass rendering.
  ///
  /// If these settings change in a way that affects geometry, the geometry
  /// will be marked as needing an update.
  LiquidGlassSettings get settings => _settings!;
  set settings(LiquidGlassSettings value) {
    if (_settings == value) return;

    if (value.requiresGeometryRebuild(_settings)) {
      logger.finer('$hashCode rebuild ');
      markGeometryNeedsUpdate(force: true);
    }

    _settings = value;
    updateShaderWithSettings(value, _devicePixelRatio);
    markNeedsPaint();
  }

  double _devicePixelRatio;

  /// The device pixel ratio used for rendering.
  ///
  /// If this changes, the geometry will be marked as needing an update.
  double get devicePixelRatio => _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    markGeometryNeedsUpdate(force: true);
    updateShaderWithSettings(settings, value);
    markNeedsPaint();
  }

  GeometryRenderLink? _renderLink;
  GeometryRenderLink? get renderLink => _renderLink;
  set renderLink(GeometryRenderLink? value) {
    if (_renderLink == value) return;
    _renderLink?.unregisterGeometry(this);
    _renderLink = value;
    _renderLink?.registerGeometry(this);
  }

  /// The current state of the geometry.
  @visibleForTesting
  @protected
  LiquidGlassGeometryState geometryState = LiquidGlassGeometryState.needsUpdate;

  /// The current geometry matte image.
  @visibleForTesting
  @protected
  GeometryCache? geometry;

  /// Marks the geometry as needing an update.
  ///
  /// If [force] is true, the geometry will be marked as definitely needing an
  /// update. Otherwise, it will be marked as possibly needing an update,
  /// unless it is already marked as definitely needing an update.
  @protected
  void markGeometryNeedsUpdate({bool force = false}) {
    final newState = force
        ? LiquidGlassGeometryState.needsUpdate
        : LiquidGlassGeometryState.mightNeedUpdate;

    geometryState = switch ((geometryState, newState)) {
      (LiquidGlassGeometryState.needsUpdate, _) =>
        LiquidGlassGeometryState.needsUpdate,
      (_, LiquidGlassGeometryState.needsUpdate) =>
        LiquidGlassGeometryState.needsUpdate,
      _ => LiquidGlassGeometryState.mightNeedUpdate,
    };
  }

  @override
  @mustCallSuper
  void attach(PipelineOwner owner) {
    _renderLink?.registerGeometry(this);
    super.attach(owner);
  }

  @override
  @mustCallSuper
  void detach() {
    _renderLink?.unregisterGeometry(this);
    super.detach();
  }

  @override
  @mustCallSuper
  void dispose() {
    _renderLink?.unregisterGeometry(this);
    geometry?.dispose();
    geometry = null;
    super.dispose();
  }

  /// Updates the shader with the current settings and device pixel ratio.
  void updateShaderWithSettings(
    LiquidGlassSettings settings,
    double devicePixelRatio,
  );

  /// Uploads shape data to geometry shader in screen space coordinates
  void updateGeometryShaderShapes(
    List<ShapeGeometry> shapes,
  );

  /// Renders a reduced nine-slice matte `Picture` for a single [shape].
  ///
  /// The returned picture is `nineSlice.textureSize` physical pixels and
  /// contains the shape's corners and a minimal straight-edge band, to be
  /// expanded back to the full region via nine-patch mapping.
  Picture renderNineSlicePicture(ShapeGeometry shape, NineSlice nineSlice);

  /// Globally toggles the nine-slice border-matte optimization.
  static bool nineSliceEnabled = true;

  /// Globally toggles connected-component splitting of sparse blend groups
  /// into independent direct-render passes (no union-AABB composite texture).
  static bool componentSplittingEnabled = true;

  /// Global resolution scale (<= 1.0) for non-nine-sliced geometry mattes.
  ///
  /// Opt-in quality tradeoff: values below 1.0 (e.g. 0.5) render mattes at a
  /// lower resolution for ~`scale^2` less texture memory, at the cost of
  /// slightly softer edge anti-aliasing. Defaults to 1.0 (no change).
  static double geometryResolutionScale = 1;

  /// Paints the contents of all shapes to the given [context] at the given
  /// [offset].
  void paintShapeContents(
    RenderObject from,
    PaintingContext context,
    Offset offset,
  );

  /// Gathers all shapes and computes them in both layer and screen space
  /// Returns (layerBounds, shapes, anyShapeChangedInLayer)
  (
    Rect bounds,
    List<ShapeGeometry> geometries,
    bool needsUpdate,
  )
  gatherShapeData();

  /// Gathers shape data in screen-physical pixel space for the inline
  /// (texture-less) "direct" render path.
  ///
  /// Returns a flat float list laid out as
  /// `[numShapes, blend, type0, cx0, cy0, w0, h0, r0, type1, ...]`, with all
  /// positions/sizes already multiplied by [devicePixelRatio].
  ///
  /// Returns `null` if direct rendering is not applicable, e.g. because a shape
  /// is rotated/skewed/mirrored (the screen-space SDF only supports
  /// translation + positive scale) or there are no renderable shapes.
  List<double>? gatherDirectShapeData(double devicePixelRatio);

  /// Splits this geometry into proximity-connected components for independent
  /// direct render passes, or `null` when splitting is disabled, not
  /// beneficial, or not applicable (e.g. a single component, too many
  /// components, or a non-axis-aligned shape).
  List<DirectComponent>? gatherDirectComponents(double devicePixelRatio);

  Path getPath(
    List<ShapeGeometry> geometries,
  ) {
    final path = Path();
    for (final shape in geometries) {
      path.addPath(
        shape.renderObject.getPath(),
        Offset.zero,
        matrix4: shape.shapeToGeometry?.storage,
      );
    }
    return path;
  }

  /// Ensures the current [geometry] is rendered to a texture (converting an
  /// [UnrenderedGeometryCache] into a [RenderedGeometryCache] in place) and
  /// returns it, or `null` if there is no geometry.
  ///
  /// Used by the single-group direct-sampling path, which samples this matte
  /// straight from the final shader instead of compositing it into a separate
  /// screen-space texture.
  RenderedGeometryCache? ensureRenderedMatte() {
    final current = geometry;
    if (current == null) return null;
    final rendered = current.render();
    geometry = rendered;
    return rendered;
  }

  /// Should be called from within [paint] to maybe rebuild the [geometry].
  GeometryCache? maybeRebuildGeometry() {
    if (geometryState == LiquidGlassGeometryState.updated && geometry != null) {
      return geometry;
    }

    final (layerBounds, shapes, anyShapeChangedInLayer) = gatherShapeData();

    if (geometryState == LiquidGlassGeometryState.mightNeedUpdate &&
        !anyShapeChangedInLayer &&
        geometry != null) {
      logger.finer('$hashCode Skipping geometry rebuild.');

      // Only mark the link dirty if rendering actually produces a *new*
      // texture. An already-rendered cache's `render()` is a no-op, so forcing
      // a dirty here would make the layer rebuild its composite every frame
      // (e.g. while the whole layer is merely translating), defeating caching.
      final wasUnrendered = geometry is UnrenderedGeometryCache;

      // Only render once we are done building
      geometry = geometry!.render();
      geometryState = LiquidGlassGeometryState.updated;

      if (wasUnrendered) {
        renderLink?.markRebuilt(this);
      }

      return geometry;
    }

    logger.finer('$hashCode Rebuilding geometry');

    geometry?.dispose();
    geometry = null;
    geometryState = LiquidGlassGeometryState.updated;

    if (shapes.isEmpty) {
      return null;
    }

    final snappedBounds = layerBounds.snapToPixels(devicePixelRatio);
    final matteBounds = Rect.fromLTWH(
      snappedBounds.left * devicePixelRatio,
      snappedBounds.top * devicePixelRatio,
      snappedBounds.width * devicePixelRatio,
      snappedBounds.height * devicePixelRatio,
    ).snapToPixels(1);

    final nineSlice = _tryComputeNineSlice(shapes, matteBounds);

    final GeometryCache newGeo;
    if (nineSlice != null) {
      // Render the small border matte eagerly (it is tiny) so the composite
      // can expand it via drawImageNine and the direct path can sample it.
      newGeo = geometry = UnrenderedGeometryCache(
        matte: renderNineSlicePicture(shapes.first, nineSlice),
        bounds: snappedBounds,
        matteBounds: matteBounds,
        shapes: shapes,
        path: getPath(shapes),
        nineSlice: nineSlice,
      ).render();
    } else {
      newGeo = geometry = UnrenderedGeometryCache(
        matte: _buildGeometryPicture(snappedBounds, shapes),
        bounds: snappedBounds,
        matteBounds: matteBounds,
        shapes: shapes,
        path: getPath(shapes),
        resolutionScale: RenderLiquidGlassGeometry.geometryResolutionScale
            .clamp(0.1, 1.0),
      );
    }

    // We have updated the geometry with an actual shape-data change.
    _renderLink?.markFullRebuild(this);
    return newGeo;
  }

  Picture _buildGeometryPicture(
    Rect geometryBounds,
    List<ShapeGeometry> shapes,
  ) {
    final bounds = geometryBounds.snapToPixels(devicePixelRatio);

    final width = (bounds.width * devicePixelRatio).ceil();
    final height = (bounds.height * devicePixelRatio).ceil();

    geometryShader.setFloatUniforms((value) {
      value
        ..setFloat(width.toDouble())
        ..setFloat(height.toDouble());
    });

    updateGeometryShaderShapes(shapes);

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()..shader = geometryShader;

    final leftPixel = (geometryBounds.left * devicePixelRatio).roundToDouble();
    final topPixel = (geometryBounds.top * devicePixelRatio).roundToDouble();

    canvas
      // This translation might seem redundant, but we do it to ensure pixel
      // snapping
      ..translate(-leftPixel, -topPixel)
      ..drawRect(
        Rect.fromLTWH(
          leftPixel,
          topPixel,
          width.toDouble(),
          height.toDouble(),
        ),
        paint,
      );

    return recorder.endRecording();
  }

  /// Decides whether the matte described by [matteBounds] can be stored as a
  /// reduced nine-slice border matte, returning its descriptor or `null`.
  ///
  /// Only a single shape with straight edges (rounded rectangle / squircle, not
  /// an ellipse) that is large enough to actually save pixels qualifies. The
  /// inset is intentionally generous so the fixed border fully contains the
  /// corner curvature and the inward refraction falloff, keeping the expanded
  /// result identical to a full matte.
  NineSlice? _tryComputeNineSlice(
    List<ShapeGeometry> shapes,
    Rect matteBounds,
  ) {
    if (!RenderLiquidGlassGeometry.nineSliceEnabled) return null;
    if (shapes.length != 1) return null;

    final shape = shapes.first;
    if (shape.rawShapeType == RawShapeType.ellipse) return null;

    final thickness = settings.effectiveThickness;
    if (thickness <= 0) return null;

    // Generous border: corner curvature (squircles overshoot the radius) plus
    // the inward displacement falloff (~thickness) plus anti-alias padding.
    final insetLogical = shape.rawCornerRadius * 1.5 + thickness + 4;
    final inset = insetLogical * devicePixelRatio;

    const middle = 4.0;
    final minReduced = 2 * inset + middle;

    final reduceX = matteBounds.width > minReduced + 1;
    final reduceY = matteBounds.height > minReduced + 1;
    if (!reduceX && !reduceY) return null;

    return NineSlice(
      inset: inset,
      textureSize: Size(
        reduceX ? minReduced : matteBounds.width,
        reduceY ? minReduced : matteBounds.height,
      ),
    );
  }
}

/// Describes a nine-slice (nine-patch) matte: the actual texture is smaller
/// than the region it represents, with a fixed [inset] border and a
/// stretchable middle.
@immutable
@internal
class NineSlice {
  const NineSlice({
    required this.inset,
    required this.textureSize,
  });

  /// The fixed (unstretched) border, in physical pixels, shared by the texture
  /// and the output region.
  final double inset;

  /// The actual matte texture size in physical pixels.
  final Size textureSize;
}

/// One proximity-connected component of a blend group, rendered as an
/// independent direct (texture-less) pass.
@immutable
@internal
class DirectComponent {
  const DirectComponent({
    required this.uniforms,
    required this.clipBoundsLogical,
  });

  /// Direct-render shape uniforms laid out as `[numShapes, blend, ...shapes]`,
  /// with positions/sizes in physical pixels.
  final List<double> uniforms;

  /// The logical-space clip bounds for this component's pass.
  final Rect clipBoundsLogical;
}

@immutable
@internal
sealed class GeometryCache {
  const GeometryCache({
    required this.matteBounds,
    required this.bounds,
    required this.shapes,
    required this.path,
    this.nineSlice,
    this.resolutionScale = 1.0,
  });

  /// Factor (<= 1.0) the matte texture is rendered at relative to its full
  /// resolution. Below 1.0 trades anti-aliasing sharpness for less texture
  /// memory; the shader bilinearly upsamples. Ignored when [nineSlice] is set.
  final double resolutionScale;

  /// The bounds of the geometry in the coordinate space of its
  /// [RenderLiquidGlassGeometry] parent.
  final Rect bounds;

  /// The bounds of the matte image in physical pixels.
  ///
  /// This is the *full* region the matte represents on screen. When
  /// [nineSlice] is set, the actual texture is smaller (see
  /// [NineSlice.textureSize]) and is expanded to these bounds via nine-patch
  /// mapping.
  final Rect matteBounds;

  /// Nine-slice descriptor, or `null` for a full-size matte.
  final NineSlice? nineSlice;

  final List<ShapeGeometry> shapes;

  final Path path;

  /// Ensure that this geometry is rendered and potentially dispose this
  /// instance.
  ///
  /// Using this object isn't safe after calling this method.
  /// Make sure to only use the returned object after calling this.
  ///
  /// If this is a [UnrenderedGeometryCache], this will produce a
  /// [RenderedGeometryCache].
  ///
  /// If this is already rendered, it will return itself.
  RenderedGeometryCache render();

  Future<RenderedGeometryCache> renderAsync();

  void dispose();
}

/// Represents a current snapshot of the geometry used for liquid glass
/// rendering.
@immutable
@internal
class UnrenderedGeometryCache extends GeometryCache {
  const UnrenderedGeometryCache({
    required this.matte,
    required super.matteBounds,
    required super.bounds,
    required super.shapes,
    required super.path,
    super.nineSlice,
    super.resolutionScale,
  });

  /// The matte image representing the geometry.
  final Picture matte;

  int get _textureWidth => nineSlice != null
      ? nineSlice!.textureSize.width.ceil()
      : (matteBounds.width * resolutionScale).ceil();

  int get _textureHeight => nineSlice != null
      ? nineSlice!.textureSize.height.ceil()
      : (matteBounds.height * resolutionScale).ceil();

  /// Whether the full-resolution [matte] picture must be downscaled when
  /// rasterizing (resolution-scale path, distinct from the nine-slice path
  /// whose picture is already rendered at the reduced size).
  bool get _needsDownscaleRaster => nineSlice == null && resolutionScale != 1.0;

  Picture _scaledPicture() {
    final recorder = PictureRecorder();
    Canvas(recorder)
      ..scale(resolutionScale)
      ..drawPicture(matte);
    return recorder.endRecording();
  }

  @override
  Future<RenderedGeometryCache> renderAsync() async {
    final Image image;
    if (_needsDownscaleRaster) {
      final scaled = _scaledPicture();
      image = await scaled.toImage(_textureWidth, _textureHeight);
      scaled.dispose();
    } else {
      image = await matte.toImage(_textureWidth, _textureHeight);
    }
    return RenderedGeometryCache(
      matte: image,
      matteBounds: matteBounds,
      bounds: bounds,
      shapes: shapes,
      path: path,
      nineSlice: nineSlice,
      resolutionScale: resolutionScale,
    );
  }

  @override
  RenderedGeometryCache render() {
    final Image image;
    if (_needsDownscaleRaster) {
      final scaled = _scaledPicture();
      image = scaled.toImageSync(_textureWidth, _textureHeight);
      scaled.dispose();
    } else {
      image = matte.toImageSync(_textureWidth, _textureHeight);
    }
    dispose();
    return RenderedGeometryCache(
      matte: image,
      matteBounds: matteBounds,
      bounds: bounds,
      shapes: shapes,
      path: path,
      nineSlice: nineSlice,
      resolutionScale: resolutionScale,
    );
  }

  /// Disposes of the resources used by the geometry.
  @override
  void dispose() {
    matte.dispose();
  }
}

/// Represents a current snapshot of the geometry used for liquid glass
/// rendering.
@immutable
@internal
class RenderedGeometryCache extends GeometryCache {
  const RenderedGeometryCache({
    required this.matte,
    required super.matteBounds,
    required super.bounds,
    required super.shapes,
    required super.path,
    super.nineSlice,
    super.resolutionScale,
  });

  /// The matte image representing the geometry.
  final Image matte;

  @override
  RenderedGeometryCache render() => this;

  @override
  Future<RenderedGeometryCache> renderAsync() => Future.value(this);

  /// Disposes of the resources used by the geometry.
  @override
  void dispose() {
    matte.dispose();
  }
}

extension on LiquidGlassSettings {
  bool requiresGeometryRebuild(LiquidGlassSettings? other) {
    if (other == null) return false;

    return effectiveThickness != other.effectiveThickness ||
        refractiveIndex != other.refractiveIndex;
  }
}

@internal
enum RawShapeType {
  // none(0), unused in CPU code
  squircle(1),
  ellipse(2),
  roundedRectangle(3);

  const RawShapeType(this.shaderIndex);

  final double shaderIndex;

  static RawShapeType fromLiquidGlassShape(LiquidShape shape) {
    switch (shape) {
      case LiquidRoundedSuperellipse():
        return RawShapeType.squircle;
      case LiquidOval():
        return RawShapeType.ellipse;
      case LiquidRoundedRectangle():
        return RawShapeType.roundedRectangle;
    }
  }
}

/// The geometry of a single shape.
///
/// Can be part of multiple blended shapes in [RenderLiquidGlassGeometry], or on
/// its own.
@internal
class ShapeGeometry extends Equatable {
  ShapeGeometry({
    required this.renderObject,
    required this.shape,
    required this.shapeBounds,
    this.shapeToGeometry,
  }) : rawCornerRadius = rawCornerRadiusOf(shape),
       rawShapeType = RawShapeType.fromLiquidGlassShape(shape);

  /// The raw corner radius the geometry shader expects for [shape].
  static double rawCornerRadiusOf(LiquidShape shape) =>
      _getRadiusFromGlassShape(shape);

  static double _getRadiusFromGlassShape(LiquidShape shape) {
    switch (shape) {
      case LiquidRoundedSuperellipse():
        return shape.borderRadius;
      case LiquidRoundedRectangle():
        return shape.borderRadius;
      case LiquidOval():
        return 0;
    }
  }

  final RenderLiquidGlass renderObject;

  final LiquidShape shape;

  final RawShapeType rawShapeType;

  final double rawCornerRadius;

  /// Bounds in geometry-local coordinates (for painting)
  final Rect shapeBounds;

  final Matrix4? shapeToGeometry;

  @override
  List<Object?> get props => [renderObject, shape, shapeBounds];
}

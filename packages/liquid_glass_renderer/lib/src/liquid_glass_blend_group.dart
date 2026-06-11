import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_renderer/src/internal/transform_tracking_repaint_boundary_mixin.dart';
import 'package:liquid_glass_renderer/src/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_render_scope.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';
import 'package:meta/meta.dart';

/// A widget that groups multiple liquid glass shapes for blending.
///
/// Any [LiquidGlass.grouped] widgets inside this group will blend together.
///
/// This widget will expect a parent [LiquidGlassLayer] to render the liquid
/// glass effect on.
class LiquidGlassBlendGroup extends StatefulWidget {
  /// Creates a new [LiquidGlassBlendGroup].
  const LiquidGlassBlendGroup({
    required this.child,
    this.blend = 20.0,
    super.key,
  });

  /// The amount of blending between shapes in this group.
  ///
  /// Roughly corresponds to distance of logical pixels at which shapes start to
  /// blend.
  final double blend;

  /// The child widget containing liquid glass shapes.
  final Widget child;

  /// Maximum number of shapes supported per layer.
  static const int maxShapesPerLayer = 16;

  /// Retrieves the [GlassGroupLink] from the nearest ancestor
  /// [LiquidGlassBlendGroup].
  ///
  /// Can be used by child shapes to register themselves for blending.
  static GlassGroupLink of(BuildContext context) {
    final inherited = _InheritedLiquidGlassBlendGroup.of(context);
    assert(inherited != null, 'No LiquidGlassBlendGroup found in context');
    return inherited!.link;
  }

  /// Retrieves the [GlassGroupLink] from the nearest ancestor
  /// [LiquidGlassBlendGroup], or null if none is found.
  static GlassGroupLink? maybeOf(BuildContext context) {
    final inherited = _InheritedLiquidGlassBlendGroup.of(context);
    return inherited?.link;
  }

  @override
  State<LiquidGlassBlendGroup> createState() => _LiquidGlassBlendGroupState();
}

class _LiquidGlassBlendGroupState extends State<LiquidGlassBlendGroup> {
  late final GlassGroupLink _geometryLink = GlassGroupLink();

  @override
  void dispose() {
    _geometryLink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final useFake = LiquidGlassRenderScope.of(context).useFake;

    if (useFake) {
      return _InheritedLiquidGlassBlendGroup(
        link: _geometryLink,
        child: widget.child,
      );
    }

    return _InheritedLiquidGlassBlendGroup(
      link: _geometryLink,
      child: ShaderBuilder(
        (context, shader, child) => _RawLiquidGlassBlendGroup(
          blend: widget.blend,
          shader: shader,
          link: _geometryLink,
          renderLink: InheritedGeometryRenderLink.of(context)!,
          settings: LiquidGlassRenderScope.of(context).settings,
          child: child,
        ),
        assetKey: ShaderKeys.blendedGeometry,
        child: widget.child,
      ),
    );
  }
}

/// Per-shape screen-space data used to build direct render uniforms.
class _DirectShape {
  _DirectShape({
    required this.screenRect,
    required this.meanScale,
    required this.uniforms,
  });

  /// The shape's bounding rect in logical screen coordinates.
  final Rect screenRect;

  /// The mean of the per-axis screen scale (for blend/radius scaling).
  final double meanScale;

  /// The six geometry-shader floats (type, cx, cy, w, h, r) in physical px.
  final List<double> uniforms;
}

class _InheritedLiquidGlassBlendGroup extends InheritedWidget {
  const _InheritedLiquidGlassBlendGroup({
    required this.link,
    required super.child,
  });

  final GlassGroupLink link;

  static _InheritedLiquidGlassBlendGroup? of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_InheritedLiquidGlassBlendGroup>();
  }

  @override
  bool updateShouldNotify(covariant InheritedWidget oldWidget) {
    return oldWidget is! _InheritedLiquidGlassBlendGroup ||
        oldWidget.link != link;
  }
}

class _RawLiquidGlassBlendGroup extends SingleChildRenderObjectWidget {
  const _RawLiquidGlassBlendGroup({
    required this.blend,
    required this.shader,
    required this.renderLink,
    required this.link,
    required this.settings,
    super.child,
  });

  final double blend;
  final FragmentShader shader;
  final GeometryRenderLink renderLink;
  final GlassGroupLink link;
  final LiquidGlassSettings settings;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderLiquidGlassBlendGroup(
      renderLink: renderLink,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      geometryShader: shader,
      settings: settings,
      link: link,
      blend: blend,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLiquidGlassBlendGroup renderObject,
  ) {
    renderObject
      ..blend = blend
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context)
      ..settings = settings
      ..link = link;
  }
}

@visibleForTesting
@internal
class RenderLiquidGlassBlendGroup extends RenderLiquidGlassGeometry
    with TransformTrackingRenderObjectMixin {
  RenderLiquidGlassBlendGroup({
    required super.renderLink,
    required super.devicePixelRatio,
    required super.geometryShader,
    required super.settings,
    required this._link,
    required this._blend,
  }) {
    link.addListener(_onLinkUpdate);
  }

  GlassGroupLink _link;

  /// The link that provides shape information to this geometry.
  GlassGroupLink get link => _link;

  set link(GlassGroupLink value) {
    if (_link == value) return;
    _link.removeListener(_onLinkUpdate);
    _link = value;
    value.addListener(_onLinkUpdate);
    markNeedsPaint();
  }

  double _blend = 0;
  double get blend => _blend;
  set blend(double value) {
    if (_blend == value) return;
    _blend = value;
    updateShaderWithSettings(settings, devicePixelRatio);
    markGeometryNeedsUpdate(force: true);
    markNeedsPaint();
  }

  void _onLinkUpdate() {
    // One of the shapes might have changed.
    markGeometryNeedsUpdate();
    markNeedsPaint();
  }

  @override
  void onTransformChanged() {
    markGeometryNeedsUpdate();
    markNeedsPaint();
  }

  @override
  void updateShaderWithSettings(
    LiquidGlassSettings settings,
    double devicePixelRatio,
  ) {
    geometryShader.setFloatUniforms(initialIndex: 2, (value) {
      value.setFloats([
        settings.refractiveIndex,
        settings.effectiveChromaticAberration,
        settings.effectiveThickness,
        blend * devicePixelRatio,
      ]);
    });
  }

  @override
  void updateGeometryShaderShapes(
    List<ShapeGeometry> shapes,
  ) {
    if (shapes.length > LiquidGlassBlendGroup.maxShapesPerLayer) {
      throw UnsupportedError(
        'Only ${LiquidGlassBlendGroup.maxShapesPerLayer} shapes are supported '
        'at the moment!',
      );
    }

    geometryShader.setFloatUniforms(initialIndex: 6, (value) {
      value.setFloat(shapes.length.toDouble());
      for (final shape in shapes) {
        final center = shape.shapeBounds.center;
        final size = shape.shapeBounds.size;
        value
          ..setFloat(shape.rawShapeType.shaderIndex)
          ..setFloat((center.dx) * devicePixelRatio)
          ..setFloat((center.dy) * devicePixelRatio)
          ..setFloat(size.width * devicePixelRatio)
          ..setFloat(size.height * devicePixelRatio)
          ..setFloat(shape.rawCornerRadius * devicePixelRatio);
      }
    });
  }

  @override
  List<double>? gatherDirectShapeData(double devicePixelRatio) {
    final shapes = _buildDirectShapes(devicePixelRatio);
    if (shapes == null || shapes.isEmpty) return null;

    final referenceScale = shapes.first.meanScale;
    final data = <double>[];
    for (final shape in shapes) {
      data.addAll(shape.uniforms);
    }

    final blendPhysical = blend * devicePixelRatio * referenceScale;
    return [shapes.length.toDouble(), blendPhysical, ...data];
  }

  @override
  List<DirectComponent>? gatherDirectComponents(double devicePixelRatio) {
    if (!RenderLiquidGlassGeometry.componentSplittingEnabled) return null;

    // Multi-pass paints all children on top of the glass, so it cannot honor
    // shapes that render their child inside the glass.
    if (link.shapeEntries.any((e) => e.value.$2)) return null;

    final shapes = _buildDirectShapes(devicePixelRatio);
    if (shapes == null || shapes.length < 2) return null;

    // Union-find clustering: two shapes belong to the same component when their
    // bounds are within the blend distance (they can influence each other's
    // SDF). A small hysteresis margin avoids churn right at the threshold.
    final threshold = blend * 1.2;
    final parent = List<int>.generate(shapes.length, (i) => i);
    int find(int start) {
      var i = start;
      while (parent[i] != i) {
        parent[i] = parent[parent[i]];
        i = parent[i];
      }
      return i;
    }

    for (var i = 0; i < shapes.length; i++) {
      for (var j = i + 1; j < shapes.length; j++) {
        if (_rectDistance(shapes[i].screenRect, shapes[j].screenRect) <=
            threshold) {
          parent[find(i)] = find(j);
        }
      }
    }

    final groups = <int, List<_DirectShape>>{};
    for (var i = 0; i < shapes.length; i++) {
      (groups[find(i)] ??= []).add(shapes[i]);
    }

    if (groups.length < 2) return null;
    if (groups.length > _maxDirectComponents) return null;

    // Only worth multiple passes (each a render-pass break) when the shapes are
    // genuinely sparse: the combined component area is much smaller than the
    // union bounding box that a single pass would have to cover.
    Rect? union;
    var componentAreaSum = 0.0;
    final components = <DirectComponent>[];
    for (final group in groups.values) {
      Rect? bounds;
      final data = <double>[];
      for (final shape in group) {
        data.addAll(shape.uniforms);
        bounds = bounds == null
            ? shape.screenRect
            : bounds.expandToInclude(shape.screenRect);
        union = union == null
            ? shape.screenRect
            : union.expandToInclude(shape.screenRect);
      }
      final clip = bounds!.inflate(blend);
      componentAreaSum += clip.width * clip.height;
      final blendPhysical =
          blend * devicePixelRatio * group.first.meanScale;
      components.add(
        DirectComponent(
          uniforms: [group.length.toDouble(), blendPhysical, ...data],
          clipBoundsLogical: clip,
        ),
      );
    }

    final unionArea = union!.width * union.height;
    if (componentAreaSum > unionArea * 0.6) return null;

    return components;
  }

  /// Builds per-shape screen-space direct render data, or `null` if any shape
  /// is rotated/skewed/mirrored (unsupported by the axis-aligned screen SDF).
  List<_DirectShape>? _buildDirectShapes(double devicePixelRatio) {
    final entries = link.shapeEntries;
    if (entries.isEmpty ||
        entries.length > LiquidGlassBlendGroup.maxShapesPerLayer) {
      return null;
    }

    final result = <_DirectShape>[];
    for (final entry in entries) {
      final renderObject = entry.key;
      final (shape, _) = entry.value;
      if (!renderObject.attached || !renderObject.hasSize) continue;

      final transform = renderObject.getTransformTo(null);
      final scale = _decomposeAxisAlignedScale(transform);
      if (scale == null) return null;
      final (sx, sy) = scale;

      final screenRect = MatrixUtils.transformRect(
        transform,
        Offset.zero & renderObject.size,
      );
      final center = screenRect.center;
      final size = screenRect.size;
      final meanScale = 0.5 * (sx + sy);
      final rawRadius = ShapeGeometry.rawCornerRadiusOf(shape) * meanScale;

      result.add(
        _DirectShape(
          screenRect: screenRect,
          meanScale: meanScale,
          uniforms: [
            RawShapeType.fromLiquidGlassShape(shape).shaderIndex,
            center.dx * devicePixelRatio,
            center.dy * devicePixelRatio,
            size.width * devicePixelRatio,
            size.height * devicePixelRatio,
            rawRadius * devicePixelRatio,
          ],
        ),
      );
    }
    return result;
  }

  static const int _maxDirectComponents = 4;

  /// Minimum gap between two axis-aligned rectangles (0 if they overlap).
  static double _rectDistance(Rect a, Rect b) {
    final dx = a.left > b.right
        ? a.left - b.right
        : (b.left > a.right ? b.left - a.right : 0.0);
    final dy = a.top > b.bottom
        ? a.top - b.bottom
        : (b.top > a.bottom ? b.top - a.bottom : 0.0);
    if (dx == 0 && dy == 0) return 0;
    return dx > dy ? dx : dy;
  }

  /// Decomposes [transform] into its per-axis scale, returning `null` if the
  /// transform contains rotation, skew, perspective or a non-positive scale.
  static (double sx, double sy)? _decomposeAxisAlignedScale(Matrix4 transform) {
    const eps = 1e-3;
    final s = transform.storage;
    // Off-diagonal terms of the 2D linear part (skew / rotation).
    if (s[1].abs() > eps || s[4].abs() > eps) return null;
    // Any coupling with the z axis.
    if (s[2].abs() > eps || s[6].abs() > eps || s[8].abs() > eps ||
        s[9].abs() > eps) {
      return null;
    }
    // Perspective.
    if (s[3].abs() > eps || s[7].abs() > eps || s[11].abs() > eps) return null;
    final sx = s[0];
    final sy = s[5];
    if (sx <= eps || sy <= eps) return null;
    return (sx, sy);
  }

  @override
  Picture renderNineSlicePicture(ShapeGeometry shape, NineSlice nineSlice) {
    final texW = nineSlice.textureSize.width;
    final texH = nineSlice.textureSize.height;

    // A single shape filling the reduced texture's bounding box, keeping the
    // original corner radius (in physical pixels). Coordinates are already
    // physical, so they are uploaded without an additional dpr scale.
    geometryShader
      ..setFloatUniforms((value) {
        value
          ..setFloat(texW)
          ..setFloat(texH);
      })
      ..setFloatUniforms(initialIndex: 6, (value) {
        value
          ..setFloat(1)
          ..setFloat(shape.rawShapeType.shaderIndex)
          ..setFloat(texW / 2)
          ..setFloat(texH / 2)
          ..setFloat(texW)
          ..setFloat(texH)
          ..setFloat(shape.rawCornerRadius * devicePixelRatio);
      });

    final recorder = PictureRecorder();
    Canvas(recorder).drawRect(
      Rect.fromLTWH(0, 0, texW, texH),
      Paint()..shader = geometryShader,
    );
    return recorder.endRecording();
  }

  @override
  (Rect, List<ShapeGeometry>, bool) gatherShapeData() {
    final shapes = <ShapeGeometry>[];
    final cachedShapes = geometry?.shapes ?? [];

    var anyShapeChangedInLayer =
        cachedShapes.length != link.shapeEntries.length;

    Rect? layerBounds;

    for (final (
          index,
          MapEntry(
            key: renderObject,
            value: (shape, glassContainsChild),
          ),
        )
        in link.shapeEntries.indexed) {
      if (!renderObject.attached || !renderObject.hasSize) continue;

      try {
        final shapeData = _computeShapeInfo(
          renderObject,
          shape,
          glassContainsChild,
        );
        shapes.add(shapeData);

        layerBounds =
            layerBounds?.expandToInclude(shapeData.shapeBounds) ??
            shapeData.shapeBounds;

        final existingShape = cachedShapes.length > index
            ? cachedShapes[index]
            : null;

        if (existingShape == null) {
          anyShapeChangedInLayer = true;
        } else if (existingShape.shapeBounds != shapeData.shapeBounds ||
            existingShape.shape != shapeData.shape) {
          anyShapeChangedInLayer = true;
        }
      } catch (e) {
        debugPrint('Failed to compute shape info: $e');
      }
    }

    return (
      (layerBounds ?? Rect.zero).inflate(blend * .25),
      shapes,
      anyShapeChangedInLayer,
    );
  }

  @override
  void paintShapeContents(
    RenderObject from,
    PaintingContext context,
    Offset offset, {
    required bool insideGlass,
  }) {
    for (final shapeEntry in link.shapeEntries) {
      final renderObject = shapeEntry.key;
      if (!renderObject.attached ||
          renderObject.glassContainsChild != insideGlass) {
        continue;
      }

      renderObject.paintFromLayer(
        context,
        renderObject.getTransformTo(from),
        offset,
      );
    }
  }

  ShapeGeometry _computeShapeInfo(
    RenderLiquidGlass renderObject,
    LiquidShape shape,
    bool glassContainsChild,
  ) {
    if (!hasSize) {
      throw StateError(
        'Cannot compute shape info for $renderObject because '
        '$this LiquidGlassGeometry has no size yet.',
      );
    }

    if (!renderObject.hasSize) {
      throw StateError(
        'Cannot compute shape info for LiquidGlass $renderObject because it '
        'has no size yet.',
      );
    }

    // We remember the shapes transform to this blend group.
    final transformToGeometry = renderObject.getTransformTo(this);

    final blendGroupRect = MatrixUtils.transformRect(
      transformToGeometry,
      Offset.zero & renderObject.size,
    );

    return ShapeGeometry(
      renderObject: renderObject,
      shape: shape,
      glassContainsChild: glassContainsChild,
      shapeBounds: blendGroupRect,
      shapeToGeometry: transformToGeometry,
    );
  }
}

/// A link that connects liquid glass shapes to their parent
/// [LiquidGlassBlendGroup] for efficient communication of position, size, and
/// transform changes.
@internal
class GlassGroupLink with ChangeNotifier {
  /// Creates a new [GlassGroupLink].
  GlassGroupLink();

  /// Information about a shape registered with this link.
  final Map<RenderLiquidGlass, (LiquidShape shape, bool glassContainsChild)>
  _shapes = {};

  List<
    MapEntry<RenderLiquidGlass, (LiquidShape shape, bool glassContainsChild)>
  >
  get shapeEntries => _shapes.entries.toList();

  /// Check if any shapes are registered.
  bool get hasShapes => _shapes.isNotEmpty;

  /// Register a shape with this link.
  void registerShape(
    RenderLiquidGlass renderObject,
    LiquidShape shape, {
    required bool glassContainsChild,
  }) {
    _shapes[renderObject] = (shape, glassContainsChild);
    notifyListeners();
  }

  /// Unregister a shape from this link.
  void unregisterShape(RenderLiquidGlass renderObject) {
    _shapes.remove(renderObject);
    notifyListeners();
  }

  /// Update the shape properties for a registered render object.
  void updateShape(
    RenderLiquidGlass renderObject,
    LiquidShape shape, {
    required bool glassContainsChild,
  }) {
    _shapes[renderObject] = (shape, glassContainsChild);
    notifyListeners();
  }

  /// Notify that a shape's layout has changed.
  void notifyShapeLayoutChanged(RenderObject renderObject) {
    if (_shapes.containsKey(renderObject)) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _shapes.clear();
    super.dispose();
  }
}

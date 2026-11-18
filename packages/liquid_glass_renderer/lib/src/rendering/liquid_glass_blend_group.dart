import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/rendering/drawn_values.dart';
import 'package:liquid_glass_renderer/src/rendering/follower_transform.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_shape_helpers.dart';
import 'package:liquid_glass_renderer/src/rendering/render_liquid_glass_geometry.dart';

/// Gathers the shapes of a blend group into one geometry that blends them
/// together.
class RenderLiquidGlassBlendGroup extends RenderLiquidGlassGeometry {
  /// Creates a blend group whose shapes register on [link].
  RenderLiquidGlassBlendGroup({
    required super.renderLink,
    required super.devicePixelRatio,
    required this._link,
    required this._blend,
  }) {
    link
      ..addListener(_onLinkUpdate)
      ..onMembershipChanged = _onMembershipChanged
      ..onGlowChanged = _onGlowChanged;
  }

  GlassGroupLink _link;

  /// The link that provides shape information to this geometry.
  GlassGroupLink get link => _link;

  set link(GlassGroupLink value) {
    if (_link == value) return;
    _link
      ..removeListener(_onLinkUpdate)
      ..onMembershipChanged = null
      ..onGlowChanged = null;
    _link = value;
    value
      ..addListener(_onLinkUpdate)
      ..onMembershipChanged = _onMembershipChanged
      ..onGlowChanged = _onGlowChanged;
    markNeedsPaint();
  }

  double _blend;

  /// How far apart, roughly in logical pixels, the group's shapes start to
  /// blend.
  double get blend => _blend;
  set blend(double value) {
    if (_blend == value) return;
    _blend = value;
    markGeometryNeedsUpdate(force: true);
    markNeedsPaint();
  }

  @override
  double get geometryBlend => blend;

  @override
  void updatePaintOrder() {
    if (sortGlassPaintOrder(this, link.shapes, (shape) => shape)) {
      markGeometryNeedsUpdate(force: true);
    }
  }

  void _onLinkUpdate() {
    markGeometryNeedsUpdate();
    markNeedsPaint();
  }

  // A shape joining or leaving under a repaint boundary of its own repaints
  // only that boundary, and this group may sit under one too: the layer has to
  // paint this frame as it does for a glass that joins it directly.
  void _onMembershipChanged() => renderLink?.onMembershipChanged?.call();

  void _onGlowChanged(
    LiquidGlassShapeRenderObject shape, {
    required bool draws,
  }) => renderLink?.reportGlow(shape, draws: draws);

  List<Matrix4?> _lastShapeTransforms = const [];

  @override
  bool pollChildShapeTransforms({required bool record}) {
    final entries = link.shapes;
    if (_lastShapeTransforms.length != entries.length) {
      if (!record) return false;
      _lastShapeTransforms = List<Matrix4?>.filled(entries.length, null);
      for (var i = 0; i < entries.length; i++) {
        final shape = entries[i];
        if (shape.attached && shape.parent != this) {
          _lastShapeTransforms[i] = _paintedTransform(shape);
        }
      }
      return false;
    }

    var changed = false;
    for (var i = 0; i < entries.length; i++) {
      final shape = entries[i];
      if (!shape.attached || shape.parent == this) continue;
      final transform = _paintedTransform(shape);
      final last = _lastShapeTransforms[i];
      // `matrixEquals` reads null as the identity; a shape that stops or
      // starts being painted is a change either way.
      if ((transform == null) != (last == null) ||
          !MatrixUtils.matrixEquals(transform, last)) {
        if (!record) return true;
        _lastShapeTransforms[i] = transform;
        changed = true;
      }
    }
    if (changed) markGeometryNeedsUpdate();
    return changed;
  }

  @override
  Iterable<LiquidGlassShapeRenderObject> get gatheredShapes =>
      link.shapes.where(_gathers);

  bool _gathers(LiquidGlassShapeRenderObject renderObject) =>
      renderObject.attached &&
      renderObject.hasSize &&
      isGlassShapePainted(renderObject, this);

  /// The shape's transform to this group, or null while the shape is not
  /// painted (see [isGlassShapePainted]).
  Matrix4? _paintedTransform(RenderObject shape) =>
      isGlassShapePainted(shape, this) ? transformToNow(shape, this) : null;

  @override
  (Rect, List<ShapeGeometry>, bool) gatherShapeData(
    LiquidGlassAppearance defaultAppearance,
  ) {
    final shapes = <ShapeGeometry>[];
    final cachedShapes = geometry?.shapes ?? [];
    var anyShapeChangedInLayer = false;
    Rect? layerBounds;
    Rect? everyBounds;
    for (final renderObject in link.shapes) {
      if (!_gathers(renderObject)) continue;
      final index = shapes.length;
      final shapeData = _computeShapeInfo(renderObject, defaultAppearance);
      shapes.add(shapeData);
      everyBounds =
          everyBounds?.expandToInclude(shapeData.shapeBounds) ??
          shapeData.shapeBounds;
      if (shapeData.appearance.shows) {
        layerBounds =
            layerBounds?.expandToInclude(shapeData.shapeBounds) ??
            shapeData.shapeBounds;
      }
      final existingShape = cachedShapes.length > index
          ? cachedShapes[index]
          : null;
      if (existingShape == null ||
          existingShape.shapeBounds != shapeData.shapeBounds ||
          existingShape.shape != shapeData.shape ||
          !MatrixUtils.matrixEquals(
            existingShape.shapeToGeometry,
            shapeData.shapeToGeometry,
          )) {
        anyShapeChangedInLayer = true;
      }
    }
    if (cachedShapes.length != shapes.length) anyShapeChangedInLayer = true;
    return (
      (layerBounds ?? everyBounds ?? Rect.zero).inflate(blend * .25),
      shapes,
      anyShapeChangedInLayer,
    );
  }

  ShapeGeometry _computeShapeInfo(
    LiquidGlassShapeRenderObject renderObject,
    LiquidGlassAppearance defaultAppearance,
  ) {
    final transformToGeometry = transformToNow(renderObject, this);
    return ShapeGeometry(
      renderObject: renderObject,
      shape: renderObject.shape,
      appearance: renderObject.appearanceOn(defaultAppearance),
      shapeBounds: MatrixUtils.transformRect(
        transformToGeometry,
        Offset.zero & renderObject.paintSize,
      ),
      shadows: renderObject.castShadows,
      shapeToGeometry: transformToGeometry,
    );
  }
}

/// Connects the glass shapes of a blend group to the group, which gathers
/// them into its geometry.
class GlassGroupLink with ChangeNotifier {
  /// Called when a shape registers with or leaves the group.
  VoidCallback? onMembershipChanged;

  /// Called with a registered shape whose glow changed, and whether it
  /// draws.
  void Function(LiquidGlassShapeRenderObject shape, {required bool draws})?
  onGlowChanged;

  /// Tells the group that the glow of [renderObject] changed; [draws]
  /// whether it draws.
  void reportGlow(
    LiquidGlassShapeRenderObject renderObject, {
    required bool draws,
  }) => onGlowChanged?.call(renderObject, draws: draws);

  final Set<LiquidGlassShapeRenderObject> _shapes = {};

  List<LiquidGlassShapeRenderObject>? _shapesCache;

  /// The registered shapes, in paint order once the group sorted them.
  List<LiquidGlassShapeRenderObject> get shapes =>
      _shapesCache ??= _shapes.toList(growable: false);

  /// Registers [renderObject] as a member of the group.
  void registerShape(LiquidGlassShapeRenderObject renderObject) {
    if (!_shapes.add(renderObject)) return;
    _shapesCache = null;
    notifyListeners();
    onMembershipChanged?.call();
  }

  /// Removes [renderObject] from the group.
  void unregisterShape(LiquidGlassShapeRenderObject renderObject) {
    if (!_shapes.remove(renderObject)) return;
    _shapesCache = null;
    notifyListeners();
    onMembershipChanged?.call();
  }

  /// Tells the group that the registered [renderObject] changed: its
  /// shape, its layout, its look or its shadows.
  void notifyShapeChanged(LiquidGlassShapeRenderObject renderObject) {
    if (_shapes.contains(renderObject)) notifyListeners();
  }

  @override
  void dispose() {
    _shapes.clear();
    _shapesCache = null;
    super.dispose();
  }
}

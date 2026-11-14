import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/painting.dart';
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
      ..settings = settings
      ..addListener(_onLinkUpdate)
      ..onMembershipChanged = _onMembershipChanged;
  }

  @override
  set settings(LiquidGlassSettings value) {
    super.settings = value;
    link.settings = value;
  }

  GlassGroupLink _link;

  /// The link that provides shape information to this geometry.
  GlassGroupLink get link => _link;

  set link(GlassGroupLink value) {
    if (_link == value) return;
    _link
      ..removeListener(_onLinkUpdate)
      ..onMembershipChanged = null;
    _link = value;
    value
      ..settings = settings
      ..addListener(_onLinkUpdate)
      ..onMembershipChanged = _onMembershipChanged;
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
    if (sortGlassPaintOrder(this, link.shapeEntries, (entry) => entry.key)) {
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

  List<Matrix4?> _lastShapeTransforms = const [];

  @override
  bool pollChildShapeTransforms({required bool record}) {
    final entries = link.shapeEntries;
    if (_lastShapeTransforms.length != entries.length) {
      if (!record) return false;
      _lastShapeTransforms = List<Matrix4?>.filled(entries.length, null);
      for (var i = 0; i < entries.length; i++) {
        final shape = entries[i].key;
        if (shape.attached && shape.parent != this) {
          _lastShapeTransforms[i] = _paintedTransform(shape);
        }
      }
      return false;
    }

    var changed = false;
    for (var i = 0; i < entries.length; i++) {
      final shape = entries[i].key;
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
  Iterable<LiquidGlassShapeRenderObject> get gatheredShapes => [
    for (final MapEntry(key: renderObject) in link.shapeEntries)
      if (_gathers(renderObject)) renderObject,
  ];

  bool _gathers(LiquidGlassShapeRenderObject renderObject) =>
      renderObject.attached &&
      renderObject.hasSize &&
      isGlassShapePainted(renderObject, this);

  /// The shape's transform to this group, or null while the shape is not
  /// painted (see [isGlassShapePainted]).
  Matrix4? _paintedTransform(RenderObject shape) =>
      isGlassShapePainted(shape, this) ? transformToNow(shape, this) : null;

  @override
  (Rect, List<ShapeGeometry>, bool) gatherShapeData() {
    final shapes = <ShapeGeometry>[];
    final cachedShapes = geometry?.shapes ?? [];
    var anyShapeChangedInLayer = false;
    // A hidden shape draws nothing: in the bounds it stretches the matte, the
    // copy and the glass's pass from wherever it lies to the shapes that show.
    Rect? layerBounds;
    Rect? everyBounds;
    for (final MapEntry(key: renderObject, value: shape) in link.shapeEntries) {
      if (!_gathers(renderObject)) continue;
      final index = shapes.length;
      final shapeData = _computeShapeInfo(renderObject, shape);
      shapes.add(shapeData);
      everyBounds =
          everyBounds?.expandToInclude(shapeData.shapeBounds) ??
          shapeData.shapeBounds;
      if (shapeData.appearance.visibility > 0) {
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
    LiquidShape shape,
  ) {
    final transformToGeometry = transformToNow(renderObject, this);
    return ShapeGeometry(
      renderObject: renderObject,
      shape: shape,
      appearance: renderObject.appearance,
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

  final Map<LiquidGlassShapeRenderObject, LiquidShape> _shapes = {};

  LiquidGlassSettings _settings = const LiquidGlassSettings();

  /// The settings of the group, which every registered shape holds.
  ///
  /// The group writes them; each shape takes them in the same call, and a
  /// shape that registers later takes them as it registers.
  LiquidGlassSettings get settings => _settings;
  set settings(LiquidGlassSettings value) {
    if (_settings == value) return;
    _settings = value;
    for (final shape in _shapes.keys) {
      shape.settings = value;
    }
  }

  List<MapEntry<LiquidGlassShapeRenderObject, LiquidShape>>? _shapeEntriesCache;

  /// The registered shapes with their render objects.
  List<MapEntry<LiquidGlassShapeRenderObject, LiquidShape>> get shapeEntries =>
      _shapeEntriesCache ??= _shapes.entries.toList(growable: false);

  /// Registers [renderObject] as a member of the group, drawn as [shape].
  void registerShape(
    LiquidGlassShapeRenderObject renderObject,
    LiquidShape shape,
  ) {
    renderObject.settings = _settings;
    _shapes[renderObject] = shape;
    _shapeEntriesCache = null;
    notifyListeners();
    onMembershipChanged?.call();
  }

  /// Removes [renderObject] from the group.
  void unregisterShape(LiquidGlassShapeRenderObject renderObject) {
    _shapes.remove(renderObject);
    _shapeEntriesCache = null;
    notifyListeners();
    onMembershipChanged?.call();
  }

  /// Draws the registered [renderObject] as [shape].
  void updateShape(
    LiquidGlassShapeRenderObject renderObject,
    LiquidShape shape,
  ) {
    _shapes[renderObject] = shape;
    _shapeEntriesCache = null;
    notifyListeners();
  }

  /// Tells the group that the layout of the registered [renderObject]
  /// changed.
  void notifyShapeLayoutChanged(RenderObject renderObject) {
    if (_shapes.containsKey(renderObject)) notifyListeners();
  }

  @override
  void dispose() {
    _shapes.clear();
    _shapeEntriesCache = null;
    super.dispose();
  }
}

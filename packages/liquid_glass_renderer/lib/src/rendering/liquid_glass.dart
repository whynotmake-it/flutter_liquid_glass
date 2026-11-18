import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/rendering/appearance.dart';
import 'package:liquid_glass_renderer/src/rendering/geometry_render_link.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_blend_group.dart';
import 'package:liquid_glass_renderer/src/rendering/live_paint_size.dart';
import 'package:liquid_glass_renderer/src/rendering/render_liquid_glass_geometry.dart';

/// One glass shape: it registers its geometry with its layer, or with the blend
/// group it joins, and holds its child.
class RenderLiquidGlass extends RenderLiquidGlassGeometry
    with LiquidGlassShapeRenderObject, LivePaintSize {
  /// Creates the render object of one glass shape.
  RenderLiquidGlass({
    required this._shape,
    required this._layerShadows,
    required this._appearance,
    required this._visibility,
    required super.devicePixelRatio,
    this._blendGroupLink,
    super.renderLink,
  });

  LiquidGlassAppearance? _appearance;
  double _visibility;
  WornAppearance? _worn;
  Size? _wornAt;
  LiquidGlassAppearance? _wornOver;

  /// The appearance it was given, or null where it wears its layer's
  /// default.
  LiquidGlassAppearance? get appearance => _appearance;
  set appearance(LiquidGlassAppearance? value) {
    if (_appearance == value) return;
    _appearance = value;
    _lookChanged();
  }

  /// What the visibility around it multiplies its appearance's by.
  double get visibility => _visibility;
  set visibility(double value) {
    if (_visibility == value) return;
    _visibility = value;
    _lookChanged();
  }

  void _lookChanged() {
    _worn = null;
    // The owning layer draws its atlas again only when its shapes' looks
    // differ.
    markGeometryNeedsUpdate();
    _blendGroupLink?.notifyShapeChanged(this);
    markNeedsPaint();
  }

  @override
  WornAppearance appearanceOn(LiquidGlassAppearance defaultAppearance) {
    final size = hasSize ? paintSize : Size.zero;
    if (_worn case final worn?
        when size == _wornAt && identical(defaultAppearance, _wornOver)) {
      return worn;
    }
    _wornAt = size;
    _wornOver = defaultAppearance;
    return _worn = shownAppearance(
      _appearance,
      layerDefault: defaultAppearance,
      visibility: _visibility,
    ).wear(size);
  }

  LiquidShape _shape;

  @override
  LiquidShape get shape => _shape;
  set shape(LiquidShape value) {
    if (_shape == value) return;
    _shape = value;
    markNeedsPaint();
    if (_blendGroupLink case final link?) {
      link.notifyShapeChanged(this);
    } else {
      markGeometryNeedsUpdate(force: true);
    }
  }

  List<LiquidGlassShadow> _layerShadows;
  @override
  List<LiquidGlassShadow> get layerShadows => _layerShadows;
  set layerShadows(List<LiquidGlassShadow> value) {
    if (_layerShadows == value) return;
    _layerShadows = value;
    markGeometryNeedsUpdate();
    _blendGroupLink?.notifyShapeChanged(this);
    markNeedsPaint();
  }

  GlassGroupLink? _blendGroupLink;

  /// Registers this shape with either a blend group or the parent layer.
  ///
  /// A shape is never in both: grouped glass is packed by the blend group,
  /// standalone glass is its own geometry node on the layer.
  void bindLinks({
    GlassGroupLink? blendGroupLink,
    GeometryRenderLink? renderLink,
  }) {
    final moves =
        !identical(blendGroupLink, _blendGroupLink) ||
        blendGroupLink == null && !identical(renderLink, this.renderLink);
    if (moves) _reportGlow(draws: false);
    if (blendGroupLink != null) {
      this.renderLink = null;
      _setBlendGroupLink(blendGroupLink);
    } else {
      _setBlendGroupLink(null);
      this.renderLink = renderLink;
    }
    if (moves && glow != null) _reportGlow(draws: true);
  }

  void _setBlendGroupLink(GlassGroupLink? value) {
    if (_blendGroupLink == value) return;
    _unregisterFromBlendGroup();
    _blendGroupLink = value;
    _registerWithBlendGroup();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _registerWithBlendGroup();
    if (glow != null) _reportGlow(draws: true);
  }

  @override
  void detach() {
    _reportGlow(draws: false);
    _unregisterFromBlendGroup();
    super.detach();
  }

  void _registerWithBlendGroup() => _blendGroupLink?.registerShape(this);

  void _unregisterFromBlendGroup() => _blendGroupLink?.unregisterShape(this);

  @override
  void liveGlowChanged() {
    if (attached) _reportGlow(draws: glow != null);
  }

  void _reportGlow({required bool draws}) {
    if (_blendGroupLink case final link?) {
      link.reportGlow(this, draws: draws);
    } else {
      renderLink?.reportGlow(this, draws: draws);
    }
  }

  @override
  void performLayout() {
    super.performLayout();
    if (_blendGroupLink case final link?) {
      link.notifyShapeChanged(this);
    } else {
      markGeometryNeedsUpdate();
    }
  }

  @override
  void livePaintSizeChanged() {
    // A size change must not pass for the pure move a retained frame can
    // follow by translation.
    if (_blendGroupLink case final link?) {
      link.notifyShapeChanged(this);
    } else {
      markGeometryNeedsUpdate(force: true);
    }
    markNeedsPaint();
  }

  @override
  Iterable<LiquidGlassShapeRenderObject> get gatheredShapes =>
      hasSize ? [this] : const [];

  @override
  (Rect, List<ShapeGeometry>, bool) gatherShapeData(
    LiquidGlassAppearance defaultAppearance,
  ) {
    if (!hasSize) return (Rect.zero, const [], false);
    final shapeData = ShapeGeometry(
      renderObject: this,
      shape: shape,
      appearance: appearanceOn(defaultAppearance),
      shapeBounds: Offset.zero & paintSize,
      shadows: castShadows,
    );
    final cached = geometry?.shapes ?? const <ShapeGeometry>[];
    final changed =
        cached.length != 1 ||
        cached.first.shapeBounds != shapeData.shapeBounds ||
        cached.first.shape != shapeData.shape;
    return (shapeData.shapeBounds, [shapeData], changed);
  }
}

/// Moves and scales a live glass and its child to the frame's rect
/// at paint.
///
/// [applyPaintTransform] reports the move, so the layer, which polls
/// [getTransformTo] when it paints, draws the shape where the child is
/// drawn. Hit testing follows the layout box.
class RenderLiveGlassFrame extends RenderProxyBox {
  /// Creates a frame that follows [frame].
  RenderLiveGlassFrame({required this._frame});

  /// The frame this glass is moved and scaled to.
  ValueListenable<LiquidGlassShapeFrame> get frame => _frame;
  ValueListenable<LiquidGlassShapeFrame> _frame;
  set frame(ValueListenable<LiquidGlassShapeFrame> value) {
    if (identical(_frame, value)) return;
    if (attached) {
      _frame.removeListener(_onFrame);
      value.addListener(_onFrame);
    }
    _frame = value;
    _onFrame();
  }

  LiquidGlassShapeFrame? _placed;

  void _onFrame() {
    final frame = _frame.value;
    final placed = _placed;
    if (placed != null &&
        frame.rect == placed.rect &&
        frame.scaleX == placed.scaleX &&
        frame.scaleY == placed.scaleY) {
      return;
    }
    _placed = frame;
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  /// The move and scale of the child, or null when it draws where it was
  /// laid out.
  Matrix4? get _transform => _placed?.bodyIn(size).toBox;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _frame.addListener(_onFrame);
    _onFrame();
  }

  @override
  void detach() {
    _frame.removeListener(_onFrame);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final transform = _transform;
    if (child == null || transform == null) {
      layer = null;
      super.paint(context, offset);
      return;
    }
    layer = context.pushTransform(
      needsCompositing,
      offset,
      transform,
      super.paint,
      oldLayer: layer is TransformLayer ? layer! as TransformLayer : null,
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    super.applyPaintTransform(child, transform);
    if (_transform case final move?) transform.multiply(move);
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/painting.dart';
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
    required super.devicePixelRatio,
    this._blendGroupLink,
    super.renderLink,
  }) : super(
         settings: _blendGroupLink?.settings ?? const LiquidGlassSettings(),
       );

  LiquidGlassAppearance _appearance;
  LiquidGlassAppearance? _worn;
  Size? _wornAt;

  /// The appearance the shape draws with: the one it was given, as glass
  /// of its paint size wears it (see [LiquidGlassAppearance.at]).
  @override
  LiquidGlassAppearance get appearance {
    if (!hasSize) return _appearance;
    final size = paintSize;
    if (_worn case final worn? when size == _wornAt) return worn;
    _wornAt = size;
    return _worn = _appearance.at(size);
  }

  set appearance(LiquidGlassAppearance value) {
    if (_appearance == value) return;
    _appearance = value;
    _worn = null;
    // The owning layer draws its atlas again only when its shapes' looks
    // differ.
    markGeometryNeedsUpdate();
    _blendGroupLink?.notifyShapeLayoutChanged(this);
    markNeedsPaint();
  }

  LiquidShape _shape;

  /// The shape of the glass.
  LiquidShape get shape => _shape;
  set shape(LiquidShape value) {
    if (_shape == value) return;
    _shape = value;
    markNeedsPaint();
    if (_blendGroupLink case final link?) {
      link.updateShape(this, _shape);
    } else {
      markGeometryNeedsUpdate(force: true);
    }
  }

  List<BoxShadow> _layerShadows;
  @override
  List<BoxShadow> get layerShadows => _layerShadows;
  set layerShadows(List<BoxShadow> value) {
    if (_layerShadows == value) return;
    _layerShadows = value;
    markGeometryNeedsUpdate();
    _blendGroupLink?.notifyShapeLayoutChanged(this);
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
    if (blendGroupLink != null) {
      this.renderLink = null;
      _setBlendGroupLink(blendGroupLink);
    } else {
      _setBlendGroupLink(null);
      this.renderLink = renderLink;
    }
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
  }

  @override
  void detach() {
    _unregisterFromBlendGroup();
    super.detach();
  }

  void _registerWithBlendGroup() =>
      _blendGroupLink?.registerShape(this, _shape);

  void _unregisterFromBlendGroup() => _blendGroupLink?.unregisterShape(this);

  @override
  void performLayout() {
    super.performLayout();
    if (_blendGroupLink case final link?) {
      link.notifyShapeLayoutChanged(this);
    } else {
      // A child opacity layer can trigger layout without changing our size.
      // gatherShapeData compares the shape bounds before reusing the matte.
      markGeometryNeedsUpdate();
    }
  }

  @override
  void livePaintSizeChanged() {
    // A size change must not pass for the pure move a retained frame can
    // follow by translation.
    if (_blendGroupLink case final link?) {
      link.notifyShapeLayoutChanged(this);
    } else {
      markGeometryNeedsUpdate(force: true);
    }
    markNeedsPaint();
  }

  @override
  Iterable<LiquidGlassShapeRenderObject> get gatheredShapes =>
      hasSize ? [this] : const [];

  @override
  (Rect, List<ShapeGeometry>, bool) gatherShapeData() {
    if (!hasSize) return (Rect.zero, const [], false);
    final shapeData = ShapeGeometry(
      renderObject: this,
      shape: shape,
      appearance: appearance,
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

  Offset _origin = Offset.zero;
  Size? _rectSize;
  double _scaleX = 1;
  double _scaleY = 1;

  void _onFrame() {
    final frame = _frame.value;
    final origin = frame.rect?.topLeft ?? Offset.zero;
    final rectSize = frame.rect?.size;
    if (origin == _origin &&
        rectSize == _rectSize &&
        frame.scaleX == _scaleX &&
        frame.scaleY == _scaleY) {
      return;
    }
    _origin = origin;
    _rectSize = rectSize;
    _scaleX = frame.scaleX;
    _scaleY = frame.scaleY;
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  /// The move and scale of the child, or null when it draws where it was
  /// laid out.
  Matrix4? get _transform {
    if (_origin == Offset.zero && _scaleX == 1 && _scaleY == 1) return null;
    final center = (_rectSize ?? size).center(_origin);
    return Matrix4.translationValues(center.dx, center.dy, 0)
      ..scaleByDouble(_scaleX, _scaleY, 1, 1)
      ..translateByDouble(
        _origin.dx - center.dx,
        _origin.dy - center.dy,
        0,
        1,
      );
  }

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

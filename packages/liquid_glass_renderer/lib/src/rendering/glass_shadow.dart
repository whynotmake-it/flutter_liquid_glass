import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_appearance.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_shadow.dart';
import 'package:liquid_glass_renderer/src/painting/view_pixels.dart';

/// Paints a `GlassShadow`.
class RenderGlassShadow extends RenderProxyBox {
  /// Creates the render object of a `GlassShadow`.
  RenderGlassShadow({
    required this._shape,
    required this._shadows,
    required double visibility,
    required this._devicePixelRatio,
  }) : _visibility = drawnVisibility(visibility);

  /// The shape whose shadows it paints.
  LiquidShape get shape => _shape;
  LiquidShape _shape;
  set shape(LiquidShape value) {
    if (_shape == value) return;
    _shape = value;
    markNeedsPaint();
  }

  /// The shadows it paints around [shape].
  List<LiquidGlassShadow> get shadows => _shadows;
  List<LiquidGlassShadow> _shadows;
  set shadows(List<LiquidGlassShadow> value) {
    if (_shadows == value) return;
    _shadows = value;
    _castAt = null;
    markNeedsPaint();
  }

  Size? _castAt;
  List<BoxShadow> _cast = const [];

  List<BoxShadow> get _castShadows {
    if (size != _castAt) {
      _castAt = size;
      _cast = castGlassShadows(shadows, size);
    }
    return _cast;
  }

  /// The pixel ratio its shadow layer's bounds are kept on stable buckets for.
  double get devicePixelRatio => _devicePixelRatio;
  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  /// How far the shape has materialized, which fades the shadows.
  double get visibility => _visibility;
  double _visibility;
  set visibility(double value) {
    if (_visibility == value) return;
    _visibility = drawnVisibility(value);
    markNeedsPaint();
  }

  @override
  Rect get paintBounds {
    final bounds = super.paintBounds;
    if (visibility <= 0 || shadows.isEmpty) return bounds;
    return bounds.expandToInclude(
      glassShadowBounds(
        Offset.zero & size,
        _castShadows,
        visibility,
      ),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    paintLoneGlassShadows(
      context.canvas,
      LiquidGlassSilhouette.shape(shape, offset & size),
      _castShadows,
      visibility: visibility,
      layerBounds: ViewPixels(devicePixelRatio).bucket,
    );
    super.paint(context, offset);
  }
}

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_layer.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_settings.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_shape.dart';

class LiquidGlass extends StatelessWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    required this.shape,
    this.glassContainsChild = true,
    this.blur = 0,
    LiquidGlassSettings settings = const LiquidGlassSettings(),
  }) : _settings = settings;

  const LiquidGlass.inLayer({
    super.key,
    required this.child,
    required this.shape,
    this.glassContainsChild = true,
    this.blur = 0,
  }) : _settings = null;

  final Widget child;

  final LiquidGlassShape shape;

  final bool glassContainsChild;

  final double blur;

  final LiquidGlassSettings? _settings;

  @override
  Widget build(BuildContext context) {
    switch (_settings) {
      case null:
        return _RawLiquidGlass(
          shape: shape,
          blur: blur,
          glassContainsChild: glassContainsChild,
          child: child,
        );
      case LiquidGlassSettings settings:
        return LiquidGlassLayer(
          settings: settings,
          child: _RawLiquidGlass(
              child: child,
              shape: shape,
              blur: blur,
              glassContainsChild: glassContainsChild),
        );
    }
  }
}

class _RawLiquidGlass extends SingleChildRenderObjectWidget {
  const _RawLiquidGlass({
    required this.child,
    required this.shape,
    required this.blur,
    required this.glassContainsChild,
  });

  final Widget child;

  final LiquidGlassShape shape;

  final double blur;

  final bool glassContainsChild;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderLiquidGlass(
      shape: shape,
      blur: blur,
      glassContainsChild: glassContainsChild,
    );
  }

  @override
  void updateRenderObject(
      BuildContext context, RenderLiquidGlass renderObject) {
    renderObject.shape = shape;
    renderObject.blur = blur;
    renderObject.glassContainsChild = glassContainsChild;
  }
}

class RenderLiquidGlass extends RenderProxyBox {
  RenderLiquidGlass({
    required LiquidGlassShape shape,
    required double blur,
    required bool glassContainsChild,
  })  : _shape = shape,
        _blur = blur,
        _glassContainsChild = glassContainsChild;

  late LiquidGlassShape _shape;
  LiquidGlassShape get shape => _shape;
  set shape(LiquidGlassShape value) {
    if (_shape == value) return;
    _shape = value;
    markNeedsPaint();
    _notifyLayerIfNeeded();
  }

  double _blur = 0;
  set blur(double value) {
    if (_blur == value) return;
    _blur = value;
    markNeedsPaint();
    _notifyLayerIfNeeded();
  }

  bool _glassContainsChild = true;
  bool get glassContainsChild => _glassContainsChild;
  set glassContainsChild(bool value) {
    if (_glassContainsChild == value) return;
    _glassContainsChild = value;
    markNeedsPaint();
    _notifyLayerIfNeeded();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    // Register with parent layer after attaching
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _registerWithParentLayer();
    });
  }

  @override
  void detach() {
    _unregisterFromParentLayer();
    super.detach();
  }

  void _registerWithParentLayer() {
    // Walk up the render tree to find the nearest RenderLiquidGlassLayer
    RenderObject? ancestor = parent;
    while (ancestor != null) {
      if (ancestor is RenderLiquidGlassLayer) {
        ancestor.registerShape(this);
        break;
      }
      ancestor = ancestor.parent;
    }
  }

  void _unregisterFromParentLayer() {
    final layer = RenderLiquidGlassLayer.layerRegistry[this];
    layer?.unregisterShape(this);
  }

  void _notifyLayerIfNeeded() {
    final layer = RenderLiquidGlassLayer.layerRegistry[this];
    layer?.markNeedsPaint();
  }

  @override
  void performLayout() {
    super.performLayout();
    // Notify parent layer when our layout changes
    _notifyLayerIfNeeded();
  }

  @override
  void paint(PaintingContext context, Offset offset) {}

  void paintFromLayer(PaintingContext context, Offset offset) {
    super.paint(context, offset);
  }

  void paintBlur(PaintingContext context, Offset offset) {
    if (_blur <= 0) return;

    context.pushClipPath(
      true,
      offset,
      offset & size,
      ShapeBorderClipper(shape: shape).getClip(size),
      (context, offset) {
        context.pushLayer(
          BackdropFilterLayer(
            filter: ImageFilter.blur(sigmaX: _blur, sigmaY: _blur),
          ),
          (context, offset) {},
          offset,
        );
      },
    );
  }

  @override
  void markNeedsPaint() {
    super.markNeedsPaint();
    // Also notify the parent layer
    _notifyLayerIfNeeded();
  }
}

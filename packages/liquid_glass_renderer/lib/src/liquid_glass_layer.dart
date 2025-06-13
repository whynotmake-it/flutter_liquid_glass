import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_settings.dart';
import 'package:liquid_glass_renderer/src/raw_shapes.dart';
import 'package:flutter_shaders/flutter_shaders.dart';

class LiquidGlassLayer extends StatelessWidget {
  const LiquidGlassLayer({
    super.key,
    required this.child,
    this.settings = const LiquidGlassSettings(),
  });

  final Widget child;

  final LiquidGlassSettings settings;

  @override
  Widget build(BuildContext context) {
    return ShaderBuilder(
      assetKey:
          'packages/liquid_glass_renderer/lib/assets/shaders/displacement.frag',
      (context, shader, child) => _RawShapes(
        shader: shader,
        settings: settings,
        debugRenderRefractionMap: false,
        child: child!,
      ),
      child: child,
    );
  }
}

class _RawShapes extends SingleChildRenderObjectWidget {
  const _RawShapes({
    required this.shader,
    required this.settings,
    required this.debugRenderRefractionMap,
    required Widget super.child,
  });

  final FragmentShader shader;
  final LiquidGlassSettings settings;
  final bool debugRenderRefractionMap;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderLiquidGlassLayer(
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      shader: shader,
      settings: settings,
      debugRenderRefractionMap: debugRenderRefractionMap,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLiquidGlassLayer renderObject,
  ) {
    renderObject
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context)
      ..settings = settings
      ..debugRenderRefractionMap = debugRenderRefractionMap;
  }
}

class RenderLiquidGlassLayer extends RenderProxyBox {
  RenderLiquidGlassLayer({
    required double devicePixelRatio,
    required FragmentShader shader,
    required LiquidGlassSettings settings,
    bool debugRenderRefractionMap = false,
  })  : _devicePixelRatio = devicePixelRatio,
        _shader = shader,
        _settings = settings,
        _debugRenderRefractionMap = debugRenderRefractionMap;

  // Registry to allow shapes to find their parent layer
  static final Expando<RenderLiquidGlassLayer> layerRegistry = Expando();

  final Set<RenderLiquidGlass> registeredShapes = {};

  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  final FragmentShader _shader;

  LiquidGlassSettings _settings;
  set settings(LiquidGlassSettings value) {
    if (_settings == value) return;
    _settings = value;
    markNeedsPaint();
  }

  bool _debugRenderRefractionMap;
  set debugRenderRefractionMap(bool value) {
    if (_debugRenderRefractionMap == value) return;
    _debugRenderRefractionMap = value;
    markNeedsPaint();
  }

  void registerShape(RenderLiquidGlass shape) {
    if (registeredShapes.length >= 2) {
      throw UnsupportedError('Only two shapes are supported at the moment!');
    }
    registeredShapes.add(shape);
    layerRegistry[shape] = this;
    markNeedsPaint();
  }

  void unregisterShape(RenderLiquidGlass shape) {
    registeredShapes.remove(shape);
    layerRegistry[shape] = null;
    markNeedsPaint();
  }

  List<(RenderLiquidGlass, RawShape)> collectShapes() {
    final result = <(RenderLiquidGlass, RawShape)>[];

    for (final shapeRender in registeredShapes) {
      if (shapeRender.attached && shapeRender.hasSize) {
        try {
          // Get transform relative to global coordinates
          final transform = shapeRender.getTransformTo(null);

          final rect = MatrixUtils.transformRect(
            transform,
            Offset.zero & shapeRender.size,
          );

          result.add(
            (
              shapeRender,
              RawShape.fromLiquidGlassShape(
                shapeRender.shape,
                center: rect.center,
                size: rect.size,
              ),
            ),
          );
        } catch (e) {
          // Skip shapes that can't be transformed
          debugPrint('Failed to collect shape: $e');
        }
      }
    }

    return result;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final shapes = collectShapes();

    if (_settings.thickness <= 0) {
      _paintShapeContents(context, offset, shapes, glassContainsChild: true);
      _paintShapeContents(context, offset, shapes, glassContainsChild: false);
      return;
    }

    final shape1 = shapes.firstOrNull?.$2 ?? RawShape.none;
    final shape2 = shapes.lastOrNull?.$2 ?? RawShape.none;

    _shader
      ..setFloat(2, _settings.chromaticAberration)
      ..setFloat(3, _settings.glassColor.r)
      ..setFloat(4, _settings.glassColor.g)
      ..setFloat(5, _settings.glassColor.b)
      ..setFloat(6, _settings.glassColor.a)
      ..setFloat(7, _settings.lightAngle)
      ..setFloat(8, _settings.lightIntensity)
      ..setFloat(9, _settings.ambientStrength)
      ..setFloat(10, _settings.outlineIntensity)
      ..setFloat(11, _settings.thickness)
      ..setFloat(12, 1.51) // refractive index

      // Shape uniforms
      ..setFloat(13, shape1.center.dx * _devicePixelRatio)
      ..setFloat(14, shape1.center.dy * _devicePixelRatio)
      ..setFloat(15, shape1.size.width * _devicePixelRatio)
      ..setFloat(16, shape1.size.height * _devicePixelRatio)
      ..setFloat(17, shape1.cornerRadius * _devicePixelRatio)
      ..setFloat(18, shape2.center.dx * _devicePixelRatio)
      ..setFloat(19, shape2.center.dy * _devicePixelRatio)
      ..setFloat(20, shape2.size.width * _devicePixelRatio)
      ..setFloat(21, shape2.size.height * _devicePixelRatio)
      ..setFloat(22, shape2.cornerRadius * _devicePixelRatio)
      ..setFloat(23, _settings.blend * _devicePixelRatio);

    _paintShapeBlurs(context, offset, shapes);

    _paintShapeContents(context, offset, shapes, glassContainsChild: true);

    context.pushLayer(
      BackdropFilterLayer(
        filter: ImageFilter.shader(_shader),
      ),
      (context, offset) {
        super.paint(context, offset);
        _paintShapeContents(
          context,
          offset,
          shapes,
          glassContainsChild: false,
        );
      },
      offset,
    );
  }

  void _paintShapeContents(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlass, RawShape)> shapes, {
    required bool glassContainsChild,
  }) {
    final layerGlobalOffset = localToGlobal(Offset.zero);
    for (final (render, _) in shapes) {
      if (render.glassContainsChild == glassContainsChild) {
        final shapeGlobalOffset = render.localToGlobal(Offset.zero);
        final relativeOffset = shapeGlobalOffset - layerGlobalOffset;
        render.paintFromLayer(context, offset + relativeOffset);
      }
    }
  }

  void _paintShapeBlurs(PaintingContext context, Offset offset,
      List<(RenderLiquidGlass, RawShape)> shapes) {
    final layerGlobalOffset = localToGlobal(Offset.zero);
    for (final (render, _) in shapes) {
      final shapeGlobalOffset = render.localToGlobal(Offset.zero);
      final relativeOffset = shapeGlobalOffset - layerGlobalOffset;
      render.paintBlur(context, offset + relativeOffset);
    }
  }
}

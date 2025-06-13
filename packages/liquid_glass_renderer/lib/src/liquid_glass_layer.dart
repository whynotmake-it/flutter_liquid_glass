// ignore_for_file: avoid_setters_without_getters

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:liquid_glass_renderer/src/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_settings.dart';
import 'package:liquid_glass_renderer/src/raw_shapes.dart';
import 'package:meta/meta.dart';

/// Represents a layer of multiple [LiquidGlass] shapes that can flow together
/// and have shared [LiquidGlassSettings].
///
/// If you create a [LiquidGlassLayer] with one or more [LiquidGlass.inLayer]
/// widgets, the liquid glass effect will be rendered where this layer is.
/// Make sure not to stack any other widgets between the [LiquidGlassLayer] and
/// the [LiquidGlass] widgets, otherwise the liquid glass effect will be behind
/// them.
///
/// > [!WARNING]
/// > A maximum of two shapes are supported per layer at the moment.
/// >
/// > This will likely increase to at least four in the future.
///
/// ## Example
///
/// ```dart
/// Widget build(BuildContext context) {
///   return LiquidGlassLayer(
///     child: Column(
///       children: [
///         LiquidGlass.inLayer(
///           shape: LiquidGlassSquircle(
///             borderRadius: Radius.circular(10),
///           ),
///           child: SizedBox.square(
///             dimension: 100,
///           ),
///         ),
///         const SizedBox(height: 100),
///         LiquidGlass.inLayer(
///           shape: LiquidGlassSquircle(
///             borderRadius: Radius.circular(50),
///           ),
///           child: SizedBox.square(
///             dimension: 100,
///           ),
///         ),
///       ],
///     ),
///   );
/// }
class LiquidGlassLayer extends StatelessWidget {
  /// Creates a new [LiquidGlassLayer] with the given [child] and [settings].
  const LiquidGlassLayer({
    required this.child,
    this.settings = const LiquidGlassSettings(),
    super.key,
  });

  /// The subtree in which you should include at least one [LiquidGlass] widget.
  ///
  /// The [LiquidGlassLayer] will automatically register all [LiquidGlass]
  /// widgets in the subtree as shapes and render them.
  final Widget child;

  /// The settings for the liquid glass effect for all shapes in this layer.
  final LiquidGlassSettings settings;

  @override
  Widget build(BuildContext context) {
    return ShaderBuilder(
      assetKey:
          'packages/liquid_glass_renderer/lib/assets/shaders/liquid_glass.frag',
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

@internal
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
    if (registeredShapes.length >= 3) {
      throw UnsupportedError('Only three shapes are supported at the moment!');
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
    final shape2 = shapes.length > 1 ? shapes.elementAt(1).$2 : RawShape.none;
    final shape3 = shapes.length > 2 ? shapes.elementAt(2).$2 : RawShape.none;

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
      ..setFloat(13, shape1.type.index.toDouble())
      ..setFloat(14, shape1.center.dx * _devicePixelRatio)
      ..setFloat(15, shape1.center.dy * _devicePixelRatio)
      ..setFloat(16, shape1.size.width * _devicePixelRatio)
      ..setFloat(17, shape1.size.height * _devicePixelRatio)
      ..setFloat(18, shape1.cornerRadius * _devicePixelRatio)
      ..setFloat(19, shape2.type.index.toDouble())
      ..setFloat(20, shape2.center.dx * _devicePixelRatio)
      ..setFloat(21, shape2.center.dy * _devicePixelRatio)
      ..setFloat(22, shape2.size.width * _devicePixelRatio)
      ..setFloat(23, shape2.size.height * _devicePixelRatio)
      ..setFloat(24, shape2.cornerRadius * _devicePixelRatio)
      ..setFloat(25, shape3.type.index.toDouble())
      ..setFloat(26, shape3.center.dx * _devicePixelRatio)
      ..setFloat(27, shape3.center.dy * _devicePixelRatio)
      ..setFloat(28, shape3.size.width * _devicePixelRatio)
      ..setFloat(29, shape3.size.height * _devicePixelRatio)
      ..setFloat(30, shape3.cornerRadius * _devicePixelRatio)
      ..setFloat(31, _settings.blend * _devicePixelRatio);

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

  void _paintShapeBlurs(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlass, RawShape)> shapes,
  ) {
    final layerGlobalOffset = localToGlobal(Offset.zero);
    for (final (render, _) in shapes) {
      final shapeGlobalOffset = render.localToGlobal(Offset.zero);
      final relativeOffset = shapeGlobalOffset - layerGlobalOffset;
      render.paintBlur(context, offset + relativeOffset);
    }
  }
}

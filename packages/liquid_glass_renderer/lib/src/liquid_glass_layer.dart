// ignore_for_file: avoid_setters_without_getters

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:liquid_glass_renderer/src/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_settings.dart';
import 'package:liquid_glass_renderer/src/raw_shapes.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';
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
class LiquidGlassLayer extends StatefulWidget {
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
  State<LiquidGlassLayer> createState() => _LiquidGlassLayerState();
}

class _LiquidGlassLayerState extends State<LiquidGlassLayer>
    with SingleTickerProviderStateMixin {
  @override
  Widget build(BuildContext context) {
    if (!ImageFilter.isShaderFilterSupported) {
      assert(
        ImageFilter.isShaderFilterSupported,
        'liquid_glass_renderer is only supported when using Impeller at the '
        'moment. Please enable Impeller, or check '
        'ImageFilter.isShaderFilterSupported before you use liquid glass '
        'widgets.',
      );
      return widget.child;
    }

    return ShaderBuilder(
      assetKey: liquidGlassShader,
      (context, shader, child) => _RawShapes(
        shader: shader,
        settings: widget.settings,
        debugRenderRefractionMap: false,
        vsync: this,
        child: child!,
      ),
      child: widget.child,
    );
  }
}

class _RawShapes extends SingleChildRenderObjectWidget {
  const _RawShapes({
    required this.shader,
    required this.settings,
    required this.debugRenderRefractionMap,
    required this.vsync,
    required Widget super.child,
  });

  final FragmentShader shader;
  final LiquidGlassSettings settings;
  final bool debugRenderRefractionMap;

  final TickerProvider vsync;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderLiquidGlassLayer(
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      shader: shader,
      settings: settings,
      debugRenderRefractionMap: debugRenderRefractionMap,
      ticker: vsync,
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
      ..ticker = vsync
      ..debugRenderRefractionMap = debugRenderRefractionMap;
  }
}

@internal
class RenderLiquidGlassLayer extends RenderProxyBox {
  RenderLiquidGlassLayer({
    required double devicePixelRatio,
    required FragmentShader shader,
    required LiquidGlassSettings settings,
    required TickerProvider ticker,
    bool debugRenderRefractionMap = false,
  })  : _devicePixelRatio = devicePixelRatio,
        _shader = shader,
        _settings = settings,
        _tickerProvider = ticker,
        _debugRenderRefractionMap = debugRenderRefractionMap {
    _ticker = _tickerProvider.createTicker((_) {
      markNeedsPaint();
    });
  }

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

  TickerProvider _tickerProvider;
  set ticker(TickerProvider value) {
    if (_tickerProvider == value) return;
    _tickerProvider = value;
    markNeedsPaint();
  }

  /// Ticker to animate the liquid glass effect.
  ///
  // TODO(timcreatedit): this is maybe not the best for performance, but I can't
  // come up with a better solution right now.
  Ticker? _ticker;

  void registerShape(RenderLiquidGlass shape) {
    if (registeredShapes.length >= 3) {
      throw UnsupportedError('Only three shapes are supported at the moment!');
    }
    registeredShapes.add(shape);
    layerRegistry[shape] = this;
    markNeedsPaint();

    if (registeredShapes.length == 1) {
      _ticker?.start();
    }
  }

  void unregisterShape(RenderLiquidGlass shape) {
    registeredShapes.remove(shape);
    layerRegistry[shape] = null;
    markNeedsPaint();
    if (registeredShapes.isEmpty) {
      _ticker?.stop();
    }
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
      super.paint(context, offset);
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
      ..setFloat(10, _settings.thickness)
      ..setFloat(11, _settings.refractiveIndex) // refractive index

      // Shape uniforms
      ..setFloat(12, shape1.type.index.toDouble())
      ..setFloat(13, shape1.center.dx * _devicePixelRatio)
      ..setFloat(14, shape1.center.dy * _devicePixelRatio)
      ..setFloat(15, shape1.size.width * _devicePixelRatio)
      ..setFloat(16, shape1.size.height * _devicePixelRatio)
      ..setFloat(17, shape1.cornerRadius * _devicePixelRatio)
      ..setFloat(18, shape2.type.index.toDouble())
      ..setFloat(19, shape2.center.dx * _devicePixelRatio)
      ..setFloat(20, shape2.center.dy * _devicePixelRatio)
      ..setFloat(21, shape2.size.width * _devicePixelRatio)
      ..setFloat(22, shape2.size.height * _devicePixelRatio)
      ..setFloat(23, shape2.cornerRadius * _devicePixelRatio)
      ..setFloat(24, shape3.type.index.toDouble())
      ..setFloat(25, shape3.center.dx * _devicePixelRatio)
      ..setFloat(26, shape3.center.dy * _devicePixelRatio)
      ..setFloat(27, shape3.size.width * _devicePixelRatio)
      ..setFloat(28, shape3.size.height * _devicePixelRatio)
      ..setFloat(29, shape3.cornerRadius * _devicePixelRatio)
      ..setFloat(30, _settings.blend * _devicePixelRatio);

    _paintShapeBlurs(context, offset, shapes);

    _paintShapeContents(context, offset, shapes, glassContainsChild: true);

    context.pushLayer(
      BackdropFilterLayer(
        filter: ImageFilter.shader(_shader),
      ),
      (context, offset) {
        _paintShapeContents(
          context,
          offset,
          shapes,
          glassContainsChild: false,
        );
      },
      offset,
    );
    super.paint(context, offset);
  }

  @override
  void dispose() {
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
    super.dispose();
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
      render.paintBlur(context, offset + relativeOffset, _settings.blur);
    }
  }
}

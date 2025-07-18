// ignore_for_file: avoid_setters_without_getters

import 'dart:math';
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
/// > A maximum of 64 shapes are supported per layer at the moment.
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

/// Maximum number of shapes supported per layer due to Flutter's uniform limit
const int _maxShapesPerLayer = 64;

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
    if (registeredShapes.length >= _maxShapesPerLayer) {
      throw UnsupportedError(
        'Only $_maxShapesPerLayer shapes are supported at the moment!',
      );
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
          // Get transform relative to global coordinates, since the shader
          // always covers the whole screen (BackdropFilter)
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

    final shapeCount = min(_maxShapesPerLayer, shapes.length);

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
      ..setFloat(11, _settings.refractiveIndex)
      ..setFloat(12, _settings.blend * _devicePixelRatio)
      ..setFloat(13, shapeCount.toDouble()); // Number of active shapes

    for (var i = 0; i < shapeCount; i++) {
      final shape = i < shapes.length ? shapes[i].$2 : RawShape.none;
      final baseIndex =
          14 + (i * 6); // Updated base index after adding uNumShapes

      _shader
        ..setFloat(baseIndex, shape.type.index.toDouble())
        ..setFloat(baseIndex + 1, shape.center.dx * _devicePixelRatio)
        ..setFloat(baseIndex + 2, shape.center.dy * _devicePixelRatio)
        ..setFloat(baseIndex + 3, shape.size.width * _devicePixelRatio)
        ..setFloat(baseIndex + 4, shape.size.height * _devicePixelRatio)
        ..setFloat(baseIndex + 5, shape.cornerRadius * _devicePixelRatio);
    }

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
    for (final (ro, _) in shapes) {
      if (ro.glassContainsChild == glassContainsChild) {
        // Get the transform from the shape to this layer
        final transform = ro.getTransformTo(this);

        // Apply the full transform to the painting context
        context.pushTransform(
          true,
          offset,
          transform,
          ro.paintFromLayer,
        );
      }
    }
  }

  void _paintShapeBlurs(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlass, RawShape)> shapes,
  ) {
    for (final (render, _) in shapes) {
      // Get the transform from the shape to this layer
      final transform = render.getTransformTo(this);

      // Apply the full transform to the painting context for blur
      context.pushTransform(
        true,
        offset,
        transform,
        (context, offset) {
          render.paintBlur(context, offset, _settings.blur);
        },
      );
    }
  }
}

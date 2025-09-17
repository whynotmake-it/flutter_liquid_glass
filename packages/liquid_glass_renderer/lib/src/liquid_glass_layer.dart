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
/// > A maximum of 16 shapes are supported per layer due to Impeller's 
/// > uniform buffer limits.
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
    this.restrictThickness = true,
    super.key,
  });

  /// The subtree in which you should include at least one [LiquidGlass] widget.
  ///
  /// The [LiquidGlassLayer] will automatically register all [LiquidGlass]
  /// widgets in the subtree as shapes and render them.
  final Widget child;

  /// The settings for the liquid glass effect for all shapes in this layer.
  final LiquidGlassSettings settings;

  /// {@template liquid_glass_renderer.restrict_thickness}
  /// If set to true, the thickness of all shapes in this layer will be
  /// restricted to the dimensions of the smallest shape.
  ///
  /// This will prevent artifacts on shapes that are thicker than wide/tall
  /// {@endtemplate}
  final bool restrictThickness;

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
        restrictThickness: widget.restrictThickness,
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
    required this.restrictThickness,
    required Widget super.child,
  });

  final FragmentShader shader;
  final LiquidGlassSettings settings;
  final bool debugRenderRefractionMap;
  final bool restrictThickness;
  final TickerProvider vsync;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderLiquidGlassLayer(
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      shader: shader,
      settings: settings,
      debugRenderRefractionMap: debugRenderRefractionMap,
      ticker: vsync,
      restrictThickness: restrictThickness,
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
      ..debugRenderRefractionMap = debugRenderRefractionMap
      ..restrictThickness = restrictThickness;
  }
}

/// Maximum number of shapes supported per layer due to Impeller's uniform 
/// buffer limit
const int _maxShapesPerLayer = 16;

@internal
class RenderLiquidGlassLayer extends RenderProxyBox {
  RenderLiquidGlassLayer({
    required double devicePixelRatio,
    required FragmentShader shader,
    required LiquidGlassSettings settings,
    required TickerProvider ticker,
    required bool restrictThickness,
    bool debugRenderRefractionMap = false,
  })  : _devicePixelRatio = devicePixelRatio,
        _shader = shader,
        _settings = settings,
        _tickerProvider = ticker,
        _debugRenderRefractionMap = debugRenderRefractionMap,
        _restrictThickness = restrictThickness {
    _ticker = _tickerProvider.createTicker((_) {
      markNeedsPaint();
    });
  }

  bool _restrictThickness;
  set restrictThickness(bool value) {
    if (_restrictThickness == value) return;
    _restrictThickness = value;
    markNeedsPaint();
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

    var thickness = _settings.thickness;

    if (_restrictThickness) {
      final smallestShape = shapes.reduce(
        (a, b) => a.$2.size.shortestSide < b.$2.size.shortestSide ? a : b,
      );
      thickness = min(thickness, smallestShape.$2.size.shortestSide);
    }

    // Optimized uniform binding - grouped into vectors (50% fewer API calls)
    _shader
      // uSize (vec2) - location 0: automatically set by Flutter
      // uGlassColor (vec4) - location 1: starts at float index 2
      ..setFloat(2, _settings.glassColor.r)
      ..setFloat(3, _settings.glassColor.g)
      ..setFloat(4, _settings.glassColor.b)
      ..setFloat(5, _settings.glassColor.a)
      // uOpticalProps (vec4) - location 2: starts at float index 6
      ..setFloat(6, _settings.refractiveIndex)
      ..setFloat(7, _settings.chromaticAberration)
      ..setFloat(8, thickness)
      ..setFloat(9, _settings.blend * _devicePixelRatio)
      // uLightConfig (vec4) - location 3: starts at float index 10
      ..setFloat(10, _settings.lightAngle)
      ..setFloat(11, _settings.lightIntensity)
      ..setFloat(12, _settings.ambientStrength)
      ..setFloat(13, _settings.saturation)
      // uColorAdjust (vec2) - location 4: starts at float index 14
      ..setFloat(14, _settings.lightness)
      ..setFloat(15, shapeCount.toDouble());

    for (var i = 0; i < shapeCount; i++) {
      final shape = i < shapes.length ? shapes[i].$2 : RawShape.none;
      final baseIndex = 16 + (i * 6); // Shape array at location 5

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

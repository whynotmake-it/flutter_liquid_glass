// ignore_for_file: avoid_setters_without_getters

import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:liquid_glass_renderer/src/glass_link.dart';
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

    return RepaintBoundary(
      child: ShaderBuilder(
        assetKey: liquidGlassShader,
        (context, shader, child) => _RawShapes(
          shader: shader,
          settings: widget.settings,
          debugRenderRefractionMap: false,
          restrictThickness: widget.restrictThickness,
          child: child!,
        ),
        child: widget.child,
      ),
    );
  }
}

class _RawShapes extends SingleChildRenderObjectWidget {
  const _RawShapes({
    required this.shader,
    required this.settings,
    required this.debugRenderRefractionMap,
    required this.restrictThickness,
    required Widget super.child,
  });

  final FragmentShader shader;
  final LiquidGlassSettings settings;
  final bool debugRenderRefractionMap;
  final bool restrictThickness;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderLiquidGlassLayer(
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      shader: shader,
      settings: settings,
      debugRenderRefractionMap: debugRenderRefractionMap,
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
    required bool restrictThickness,
    bool debugRenderRefractionMap = false,
  })  : _devicePixelRatio = devicePixelRatio,
        _shader = shader,
        _settings = settings,
        _debugRenderRefractionMap = debugRenderRefractionMap,
        _restrictThickness = restrictThickness,
        _glassLink = GlassLink() {
    // Listen to glass link changes instead of using a ticker
    _glassLink.addListener(_onGlassLinkChanged);
  }

  @override
  bool get alwaysNeedsCompositing => true;

  bool _restrictThickness;
  set restrictThickness(bool value) {
    if (_restrictThickness == value) return;
    _restrictThickness = value;
    markNeedsPaint();
  }

  final GlassLink _glassLink;

  /// The GlassLink that shapes can use to report their state.
  GlassLink get glassLink => _glassLink;

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

  void _onGlassLinkChanged() {
    markNeedsPaint();
  }

  List<(RenderLiquidGlass, RawShape)> collectShapes() {
    final result = <(RenderLiquidGlass, RawShape)>[];
    final computedShapes = _glassLink.computedShapes;

    // Check shape count limit
    if (computedShapes.length > _maxShapesPerLayer) {
      throw UnsupportedError(
        'Only $_maxShapesPerLayer shapes are supported at the moment!',
      );
    }

    for (final shapeInfo in computedShapes) {
      final renderObject = shapeInfo.renderObject;

      if (renderObject is RenderLiquidGlass) {
        final scale = _getScaleFromTransform(shapeInfo.transform);
        result.add(
          (
            renderObject,
            RawShape.fromLiquidGlassShape(
              shapeInfo.shape,
              center: shapeInfo.globalBounds.center,
              size: shapeInfo.globalBounds.size,
              scale: scale,
            ),
          ),
        );
      }
    }

    return result;
  }

  /// Extracts the geometric mean of X and Y scale factors from a transform.
  ///
  /// This is used to scale corner radii when shapes are transformed by Flutter
  /// widgets like [FittedBox] or [Transform]. The position and size are already
  /// correctly transformed via [MatrixUtils.transformRect], but corner radii
  /// need explicit scaling.
  ///
  /// **Design Tradeoff**: Instead of passing full Matrix3 transforms to the
  /// shader, we extract scale on the CPU once per frame
  /// per shape and only send 6 floats per shape to the shader.
  ///
  /// **Performance**: Optimized with fast path for axis-aligned transforms
  /// (FittedBox, Transform.scale) using direct matrix access. Handles rotated
  /// and skewed transforms with minimal overhead.
  ///
  /// **Limitation**: For non-uniform scaling with rotation, the geometric mean
  /// may not perfectly match visual appearance in all cases, but provides good
  /// results for common UI transforms while keeping shader cost at zero.
  double _getScaleFromTransform(Matrix4 transform) {
    final m = transform.storage;
    final scaleX = m[0];
    final scaleY = m[5];

    if (m[1] == 0 && m[4] == 0) {
      return sqrt(scaleX.abs() * scaleY.abs());
    }

    final a = m[0];
    final b = m[1];
    final c = m[4];
    final d = m[5];
    final scaleXSq = a * a + b * b;
    final scaleYSq = c * c + d * d;
    return sqrt(sqrt(scaleXSq * scaleYSq));
  }

  final _shaderHandle = LayerHandle<BackdropFilterLayer>();
  final _blurLayerHandle = LayerHandle<BackdropFilterLayer>();
  final _clipLayerHandle = LayerHandle<ClipPathLayer>();

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

    _shader.setFloatUniforms(initialIndex: 2, (value) {
      value
        ..setColor(_settings.glassColor)
        ..setFloats([
          _settings.refractiveIndex,
          _settings.chromaticAberration,
          thickness,
          _settings.blend * _devicePixelRatio,
          _settings.lightAngle,
          _settings.lightIntensity,
          _settings.ambientStrength,
          _settings.saturation,
          shapeCount.toDouble(),
        ])
        ..setOffset(
          Offset(
            cos(_settings.lightAngle),
            sin(_settings.lightAngle),
          ),
        )
        ..setFloats(Matrix4.identity().storage); // Identity matrix

      for (var i = 0; i < shapeCount; i++) {
        final shape = i < shapes.length ? shapes[i].$2 : RawShape.none;
        value
          ..setFloat(shape.type.index.toDouble())
          ..setFloat(shape.center.dx * _devicePixelRatio)
          ..setFloat(shape.center.dy * _devicePixelRatio)
          ..setFloat(shape.size.width * _devicePixelRatio)
          ..setFloat(shape.size.height * _devicePixelRatio)
          ..setFloat(shape.cornerRadius * _devicePixelRatio);
      }
    });

    final shaderLayer = (_shaderHandle.layer ??= BackdropFilterLayer())
      ..filter = ImageFilter.shader(_shader);

    final blurLayer = (_blurLayerHandle.layer ??= BackdropFilterLayer())
      ..filter = ImageFilter.blur(
        sigmaX: _settings.blur,
        sigmaY: _settings.blur,
      );

    final clipPath = Path();
    for (final shape in shapes) {
      final globalTransform = shape.$1.getTransformTo(this);

      clipPath.addPath(
        shape.$1.getPath(),
        offset,
        matrix4: globalTransform.storage,
      );
    }

    final clipLayer = (_clipLayerHandle.layer ??= ClipPathLayer())
      ..clipPath = clipPath
      ..clipBehavior = Clip.hardEdge;

    context
      // First we push the clipped blur layer
      ..pushLayer(
        clipLayer,
        (context, offset) {
          context.pushLayer(
            blurLayer,
            (context, offset) {
              // If glass contains child we paint it above blur but below shader
              _paintShapeContents(
                context,
                offset,
                shapes,
                glassContainsChild: true,
              );
            },
            offset,
          );
        },
        offset,
      )
      // Then we push the shader layer on top
      ..pushLayer(
        shaderLayer,
        (context, offset) => _paintShapeContents(
          context,
          offset,
          shapes,
          glassContainsChild: false,
        ),
        offset,
      );

    super.paint(context, offset);
  }

  @override
  void dispose() {
    _glassLink
      ..removeListener(_onGlassLinkChanged)
      ..dispose();
    _blurLayerHandle.layer = null;
    _shaderHandle.layer = null;
    _clipLayerHandle.layer = null;
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
        final transform = ro.getTransformTo(this);

        context.pushTransform(
          true,
          offset,
          transform,
          ro.paintFromLayer,
        );
      }
    }
  }
}

// ignore_for_file: avoid_setters_without_getters

import 'dart:ui' as ui;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:liquid_glass_renderer/src/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_settings.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';
import 'package:meta/meta.dart';

/// An experimental widget that turns its child into liquid glass.
///
/// If you apply this to a widget that has a simple shape, you will absolutely
/// want to use [LiquidGlass] instead.
/// It will be higher visual quality and faster.
///
/// This widget is useful if you want to apply the liquid glass effect to a
/// widget that has a complex shape, or if you want to apply the liquid glass
/// effect to a widget that is not a [LiquidGlass] widget.
///
/// The blur is ugly at the moment, since we have to do it from within the
/// shader:
///
/// Until one of those is fixed, blur will stay ugly here:
/// - https://github.com/flutter/flutter/issues/170820
/// - https://github.com/flutter/flutter/issues/170792
@experimental
class Glassify extends StatefulWidget {
  /// Creates a new [Glassify] with the given [child] and [settings].
  const Glassify({
    required this.child,
    this.settings = const LiquidGlassSettings(),
    super.key,
  });

  /// The subtree in which you should include at least one [LiquidGlass] widget.
  ///
  /// The [Glassify] will automatically register all [LiquidGlass]
  /// widgets in the subtree as shapes and render them.
  final Widget child;

  /// The settings for the liquid glass effect for all shapes in this layer.
  final LiquidGlassSettings settings;

  @override
  State<Glassify> createState() => _GlassifyState();
}

class _GlassifyState extends State<Glassify>
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
      assetKey: arbitraryShader,
      (context, shader, child) => _RawGlassify(
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

class _RawGlassify extends SingleChildRenderObjectWidget {
  const _RawGlassify({
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
    return RenderGlassify(
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
    RenderGlassify renderObject,
  ) {
    renderObject
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context)
      ..settings = settings
      ..ticker = vsync
      ..debugRenderRefractionMap = debugRenderRefractionMap;
  }
}

@internal
class RenderGlassify extends RenderProxyBox {
  RenderGlassify({
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

  @override
  // ignore: library_private_types_in_public_api
  _GlassifyShaderLayer? get layer => super.layer as _GlassifyShaderLayer?;

  @override
  void paint(PaintingContext context, Offset offset) {
    // Calculate global position for the shader
    var globalOffset = offset;
    try {
      final transform = getTransformTo(null);
      final globalRect = MatrixUtils.transformRect(
        transform,
        Offset.zero & size,
      );
      globalOffset = globalRect.topLeft;
    } catch (e) {
      // Fallback to the provided offset if transform calculation fails
      debugPrint('Failed to calculate global transform for Glassify: $e');
    }

    layer ??= _GlassifyShaderLayer(
      offset: offset,
      globalOffset: globalOffset,
      shader: _shader,
      settings: _settings,
      devicePixelRatio: _devicePixelRatio,
      layerSize: size,
    );
    layer!
      ..offset = offset
      ..globalOffset = globalOffset
      ..shader = _shader
      ..settings = _settings
      ..devicePixelRatio = _devicePixelRatio
      ..layerSize = size;
    context.pushLayer(
      layer!,
      (context, offset) {
        super.paint(context, offset);
      },
      offset,
    );
  }

  @override
  void markNeedsLayout() {
    super.markNeedsLayout();
    // Clear the layer to force rebuilding when layout changes
    // This ensures that transform changes are properly handled
    if (layer != null) {
      layer = null;
      markNeedsPaint();
    }
  }

  @override
  void dispose() {
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
    super.dispose();
  }
}

/// Custom composited layer that handles the liquid glass shader effect
/// with a captured child image
class _GlassifyShaderLayer extends OffsetLayer {
  _GlassifyShaderLayer({
    required FragmentShader shader,
    required LiquidGlassSettings settings,
    required double devicePixelRatio,
    required Size layerSize,
    required super.offset,
    required Offset globalOffset,
  })  : _shader = shader,
        _settings = settings,
        _devicePixelRatio = devicePixelRatio,
        _layerSize = layerSize,
        _globalOffset = globalOffset;

  FragmentShader _shader;
  FragmentShader get shader => _shader;
  set shader(FragmentShader value) {
    if (_shader == value) return;
    _shader = value;
    markNeedsAddToScene();
  }

  LiquidGlassSettings _settings;
  LiquidGlassSettings get settings => _settings;
  set settings(LiquidGlassSettings value) {
    if (_settings == value) return;
    _settings = value;
    markNeedsAddToScene();
  }

  double _devicePixelRatio;
  double get devicePixelRatio => _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    markNeedsAddToScene();
  }

  Size _layerSize;
  Size get layerSize => _layerSize;
  set layerSize(Size value) {
    if (_layerSize == value) return;
    _layerSize = value;
    markNeedsAddToScene();
  }

  Offset _globalOffset;
  Offset get globalOffset => _globalOffset;
  set globalOffset(Offset value) {
    if (_globalOffset == value) return;
    _globalOffset = value;
    markNeedsAddToScene();
  }

  ui.Image? childImage;
  ui.Image? childBlurredImage;

  ui.BackdropFilterEngineLayer? _backdropFilterLayer;

  ImageFilterEngineLayer? _imageFilterLayer;

  @override
  void addToScene(ui.SceneBuilder builder) {
    engineLayer;

    final offsetLayer = builder.pushOffset(
      offset.dx,
      offset.dy,
      oldLayer: engineLayer as ui.OffsetEngineLayer?,
    );
    engineLayer = offsetLayer;
    {
      // First, let the child layers render normally
      _captureChildLayer();
      _captureChildBlurredLayer();

      // Then apply the shader effect as a backdrop filter
      _setupShaderUniforms();
      _backdropFilterLayer = builder.pushBackdropFilter(
        ImageFilter.shader(shader),
        oldLayer: _backdropFilterLayer,
      );

      builder.pop();
    }
    builder.pop();
  }

  void _captureChildLayer() {
    childImage?.dispose();
    childImage = _buildMaskImage();
  }

  void _captureChildBlurredLayer() {
    childBlurredImage?.dispose();

    final matteBlur = settings.thickness / 6;
    childBlurredImage = _buildMaskImage(matteBlur);
  }

  ui.Image _buildMaskImage([double? blur]) {
    final builder = ui.SceneBuilder();
    final transform =
        Matrix4.diagonal3Values(devicePixelRatio, devicePixelRatio, 1);
    final bounds = offset & layerSize;

    builder.pushTransform(transform.storage);
    _addMaskToScene(builder, blur);
    builder.pop();

    return builder.build().toImageSync(
          (devicePixelRatio * bounds.width).floor(),
          (devicePixelRatio * bounds.height).floor(),
        );
  }

  void _addMaskToScene(ui.SceneBuilder builder, [double? blur]) {
    final mask = firstChild;

    builder.pushOffset(-offset.dx, -offset.dy);

    if (blur != null) {
      _imageFilterLayer = builder.pushImageFilter(
        ImageFilter.compose(
          outer: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          inner: ImageFilter.erode(radiusX: blur, radiusY: blur),
        ),
        oldLayer: _imageFilterLayer,
      );
    }

    mask?.addToScene(builder);

    if (blur != null) {
      builder.pop();
    }

    builder.pop();
  }

  void _setupShaderUniforms() {
    // Since BackdropFilter operates in global coordinate space,
    // we need to pass the global offset to the shader
    shader
      ..setImageSampler(1, childImage!) // uForegroundTexture
      ..setImageSampler(2, childBlurredImage!) // uForegroundBlurredTexture
      ..setFloat(2, layerSize.width * devicePixelRatio)
      ..setFloat(3, layerSize.height * devicePixelRatio)
      ..setFloat(4, settings.chromaticAberration)
      ..setFloat(5, settings.glassColor.r)
      ..setFloat(6, settings.glassColor.g)
      ..setFloat(7, settings.glassColor.b)
      ..setFloat(8, settings.glassColor.a)
      ..setFloat(9, settings.lightAngle)
      ..setFloat(10, settings.lightIntensity)
      ..setFloat(11, settings.ambientStrength)
      ..setFloat(12, settings.thickness)
      ..setFloat(13, settings.refractiveIndex)
      ..setFloat(14, globalOffset.dx * devicePixelRatio)
      ..setFloat(15, globalOffset.dy * devicePixelRatio)
      ..setFloat(16, settings.blur);
  }

  @override
  void dispose() {
    childImage?.dispose();
    childBlurredImage?.dispose();
    _imageFilterLayer?.dispose();
    _backdropFilterLayer?.dispose();
    super.dispose();
  }
}

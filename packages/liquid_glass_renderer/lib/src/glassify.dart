// ignore_for_file: avoid_setters_without_getters

import 'dart:ui' as ui;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:liquid_glass_renderer/src/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_settings.dart';
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
@experimental
class Glassify extends StatefulWidget {
  /// Creates a new [Glassify] with the given [child] and [settings].
  const Glassify({
    required this.child,
    this.settings = const LiquidGlassSettings(),
    this.blur = 10,
    super.key,
  });

  /// The subtree in which you should include at least one [LiquidGlass] widget.
  ///
  /// The [Glassify] will automatically register all [LiquidGlass]
  /// widgets in the subtree as shapes and render them.
  final Widget child;

  /// The settings for the liquid glass effect for all shapes in this layer.
  final LiquidGlassSettings settings;

  /// How much blur the shape should apply.
  ///
  /// The blur is ugly at the moment, since we have to do it from within the
  /// shader:
  ///
  /// Until one of those is fixed, blur will stay ugly here:
  /// - https://github.com/flutter/flutter/issues/170820
  /// - https://github.com/flutter/flutter/issues/170792
  ///
  /// Defaults to 10 pixels.
  final double blur;

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
      assetKey:
          'packages/liquid_glass_renderer/lib/assets/shaders/liquid_glass_arbitrary.frag',
      (context, shader, child) => _RawGlassWidget(
        shader: shader,
        settings: widget.settings,
        debugRenderRefractionMap: false,
        vsync: this,
        blur: widget.blur,
        child: child!,
      ),
      child: widget.child,
    );
  }
}

class _RawGlassWidget extends SingleChildRenderObjectWidget {
  const _RawGlassWidget({
    required this.shader,
    required this.settings,
    required this.debugRenderRefractionMap,
    required this.vsync,
    required this.blur,
    required Widget super.child,
  });

  final FragmentShader shader;
  final LiquidGlassSettings settings;
  final bool debugRenderRefractionMap;
  final double blur;

  final TickerProvider vsync;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderLiquidGlassLayer(
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      shader: shader,
      settings: settings,
      debugRenderRefractionMap: debugRenderRefractionMap,
      ticker: vsync,
      blur: this.blur,
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
      ..blur = blur;
  }
}

@internal
class RenderLiquidGlassLayer extends RenderProxyBox {
  RenderLiquidGlassLayer({
    required double devicePixelRatio,
    required FragmentShader shader,
    required LiquidGlassSettings settings,
    required TickerProvider ticker,
    required double blur,
    bool debugRenderRefractionMap = false,
  })  : _devicePixelRatio = devicePixelRatio,
        _shader = shader,
        _settings = settings,
        _tickerProvider = ticker,
        _blur = blur,
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

  double _blur;
  set blur(double value) {
    if (_blur == value) return;
    _blur = value;
    markNeedsPaint();
  }

  /// Ticker to animate the liquid glass effect.
  ///
  // TODO(timcreatedit): this is maybe not the best for performance, but I can't
  // come up with a better solution right now.
  Ticker? _ticker;

  late final layerHandle = LayerHandle<_LiquidGlassShaderLayer>()
    ..layer = _LiquidGlassShaderLayer(
      offset: Offset.zero,
      shader: _shader,
      settings: _settings,
      devicePixelRatio: _devicePixelRatio,
      layerSize: size,
      matteBlur: _blur,
    );

  @override
  void paint(PaintingContext context, Offset offset) {
    layerHandle.layer!
      ..offset = offset
      ..shader = _shader
      ..settings = _settings
      ..devicePixelRatio = _devicePixelRatio
      ..layerSize = size
      ..blur = _blur;

    context.pushLayer(
      layerHandle.layer!,
      (context, offset) {
        super.paint(context, offset);
      },
      offset,
    );
  }

  @override
  void dispose() {
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
    layerHandle.layer?.dispose();
    layerHandle.layer = null;
    super.dispose();
  }
}

/// Custom composited layer that handles the liquid glass shader effect
/// with a captured child image
class _LiquidGlassShaderLayer extends ContainerLayer {
  _LiquidGlassShaderLayer({
    required Offset offset,
    required FragmentShader shader,
    required LiquidGlassSettings settings,
    required double devicePixelRatio,
    required Size layerSize,
    required double matteBlur,
  })  : _offset = offset,
        _shader = shader,
        _settings = settings,
        _devicePixelRatio = devicePixelRatio,
        _layerSize = layerSize,
        _blur = matteBlur;

  Offset _offset;
  Offset get offset => _offset;
  set offset(Offset value) {
    if (_offset == value) return;
    _offset = value;
    markNeedsAddToScene();
  }

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

  double _blur;
  double get blur => _blur;
  set blur(double value) {
    if (_blur == value) return;
    _blur = value;
    markNeedsAddToScene();
  }

  ui.Image? childImage;
  ui.Image? childBlurredImage;

  @override
  void addToScene(ui.SceneBuilder builder) {
    // First, let the child layers render normally
    _captureChildLayer();
    _captureChildBlurredLayer();

    // Then apply the shader effect as a backdrop filter
    _setupShaderUniforms();
    builder
      ..pushBackdropFilter(
        ImageFilter.shader(shader),
      )
      ..pop(); // Close the backdrop filter
  }

  void _captureChildLayer() {
    childImage?.dispose();
    // Create a scene builder for the child
    final childSceneBuilder = ui.SceneBuilder()
      ..pushOffset(-offset.dx, -offset.dy);
    firstChild!.addToScene(childSceneBuilder);
    final childScene = childSceneBuilder.build();

    childImage = childScene.toImageSync(
      layerSize.width.round(),
      layerSize.height.round(),
    );

    // Trigger a repaint to use the captured image
    markNeedsAddToScene();
    childScene.dispose();
  }

  void _captureChildBlurredLayer() {
    childBlurredImage?.dispose();
    final blurSceneBuilder = ui.SceneBuilder();

    // paint child image
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImage(childImage!, Offset.zero, Paint());

    final picture = recorder.endRecording();

    final matteBlur = settings.thickness / 6;

    blurSceneBuilder
      ..pushImageFilter(
        ImageFilter.compose(
          outer: ImageFilter.blur(sigmaX: matteBlur, sigmaY: matteBlur),
          inner: ImageFilter.erode(radiusX: matteBlur, radiusY: matteBlur),
        ),
      )
      ..addPicture(Offset.zero, picture);

    final blurScene = blurSceneBuilder.build();

    childBlurredImage = blurScene.toImageSync(
      layerSize.width.round(),
      layerSize.height.round(),
    );

    blurScene.dispose();
  }

  void _setupShaderUniforms() {
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
      ..setFloat(12, settings.thickness * 2)
      ..setFloat(13, settings.refractiveIndex)
      ..setFloat(14, offset.dx * devicePixelRatio)
      ..setFloat(15, offset.dy * devicePixelRatio)
      ..setFloat(16, blur);
  }

  @override
  void dispose() {
    childImage?.dispose();
    childBlurredImage?.dispose();
    super.dispose();
  }
}

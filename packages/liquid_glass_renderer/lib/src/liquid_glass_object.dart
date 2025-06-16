// ignore_for_file: avoid_setters_without_getters

import 'dart:ui';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:liquid_glass_renderer/src/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_settings.dart';
import 'package:liquid_glass_renderer/src/raw_shapes.dart';
import 'package:meta/meta.dart';

class LiquidGlassWidget extends StatefulWidget {
  /// Creates a new [LiquidGlassWidget] with the given [child] and [settings].
  const LiquidGlassWidget({
    required this.child,
    this.settings = const LiquidGlassSettings(thickness: 100),
    super.key,
  });

  /// The subtree in which you should include at least one [LiquidGlass] widget.
  ///
  /// The [LiquidGlassWidget] will automatically register all [LiquidGlass]
  /// widgets in the subtree as shapes and render them.
  final Widget child;

  /// The settings for the liquid glass effect for all shapes in this layer.
  final LiquidGlassSettings settings;

  @override
  State<LiquidGlassWidget> createState() => _LiquidGlassWidgetState();
}

class _LiquidGlassWidgetState extends State<LiquidGlassWidget>
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
  void paint(PaintingContext context, Offset offset) {
    context.pushLayer(
      _LiquidGlassShaderLayer(
        offset: offset,
        shader: _shader,
        settings: _settings,
        devicePixelRatio: _devicePixelRatio,
        layerSize: size,
      ),
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
    super.dispose();
  }
}

/// Custom composited layer that handles the liquid glass shader effect
/// with a captured child image
class _LiquidGlassShaderLayer extends ContainerLayer {
  _LiquidGlassShaderLayer({
    required this.offset,
    required this.shader,
    required this.settings,
    required this.devicePixelRatio,
    required this.layerSize,
  });

  final Offset offset;
  final FragmentShader shader;
  final LiquidGlassSettings settings;
  final double devicePixelRatio;
  final Size layerSize;

  late ui.Image _childImage;
  late ui.Image _childBlurredImage;

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
    // Create a scene builder for the child
    final childSceneBuilder = ui.SceneBuilder();
    childSceneBuilder.pushOffset(-offset.dx, -offset.dy);
    firstChild!.addToScene(childSceneBuilder);
    final childScene = childSceneBuilder.build();

    _childImage = childScene.toImageSync(
      layerSize.width.round(),
      layerSize.height.round(),
    );

    // Trigger a repaint to use the captured image
    markNeedsAddToScene();
    childScene.dispose();
  }

  void _captureChildBlurredLayer() {
    final blurSceneBuilder = ui.SceneBuilder();

    // paint child image
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImage(_childImage!, Offset.zero, Paint());

    final picture = recorder.endRecording();

    // Calculate blur strength based on thickness and device pixel ratio
    // The blur should create a gradient that spans roughly half the thickness
    // to properly approximate the SDF used in the shader
    final blur = 10.0;

    blurSceneBuilder
      ..pushImageFilter(ImageFilter.blur(sigmaX: blur, sigmaY: blur))
      ..addPicture(Offset.zero, picture);

    final blurScene = blurSceneBuilder.build();

    _childBlurredImage = blurScene.toImageSync(
      layerSize.width.round(),
      layerSize.height.round(),
    );

    blurScene.dispose();
  }

  void _setupShaderUniforms() {
    shader
      ..setImageSampler(1, _childImage) // uForegroundTexture
      ..setImageSampler(2, _childBlurredImage) // uForegroundBlurredTexture
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
      ..setFloat(12, settings.thickness * 4)
      ..setFloat(13, settings.refractiveIndex)
      ..setFloat(14, offset.dx * devicePixelRatio)
      ..setFloat(15, offset.dy * devicePixelRatio);
  }

  @override
  void dispose() {
    _childImage?.dispose();
    super.dispose();
  }
}

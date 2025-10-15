import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/glass_link.dart';
import 'package:liquid_glass_renderer/src/internal/multi_shader_builder.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_scope.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_shader_render_object.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';
import 'package:meta/meta.dart';

/// An experimental way to use the liquid glass effect as a filter over [child],
/// using the given [settings].
///
/// **WARNING:** This might be completely broken, don't use for now.
///
/// Unlike [LiquidGlassLayer], this will filter it's [child], instead of its
/// background.
/// This means that conceptually, [child] will be painted first without any
/// instances of [LiquidGlass.inLayer] inside of it, and then the liquid glass
/// elements will be painted on top.
@experimental
class LiquidGlassFilter extends StatefulWidget {
  /// Creates a new [LiquidGlassFilter] with the given [child] and [settings].
  const LiquidGlassFilter({
    required this.child,
    this.settings = const LiquidGlassSettings(),
    super.key,
  });

  /// The settings to use for all [LiquidGlass] shapes inside this filter.
  ///
  /// Defaults to a default instance of [LiquidGlassSettings].
  final LiquidGlassSettings settings;

  /// The child that will be filtered with the liquid glass effect.
  final Widget child;

  @override
  State<LiquidGlassFilter> createState() => _LiquidGlassFilterState();
}

class _LiquidGlassFilterState extends State<LiquidGlassFilter> {
  late final _glassLink = GlassLink();

  @override
  void dispose() {
    _glassLink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LiquidGlassScope(
      settings: widget.settings,
      link: _glassLink,
      child: MultiShaderBuilder(
        assetKeys: [
          liquidGlassGeometryShader,
          liquidGlassRenderShader,
          liquidGlassLightingShader,
        ],
        (context, shaders, child) {
          return _RawLiquidGlassFilter(
            geometryShader: shaders[0],
            renderShader: shaders[1],
            lightingShader: shaders[2],
            settings: widget.settings,
            glassLink: _glassLink,
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

class _RawLiquidGlassFilter extends SingleChildRenderObjectWidget {
  const _RawLiquidGlassFilter({
    required this.geometryShader,
    required this.renderShader,
    required this.lightingShader,
    required this.settings,
    required this.glassLink,
    required super.child,
  });

  final FragmentShader geometryShader;

  final FragmentShader renderShader;

  final FragmentShader lightingShader;

  final LiquidGlassSettings settings;

  final GlassLink glassLink;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderLiquidGlassFilter(
      geometryShader: geometryShader,
      renderShader: renderShader,
      lightingShader: lightingShader,
      settings: settings,
      glassLink: glassLink,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderLiquidGlassFilter renderObject,
  ) {
    renderObject
      ..settings = settings
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context)
      ..glassLink = glassLink;
  }
}

class _RenderLiquidGlassFilter extends LiquidGlassShaderRenderObject {
  _RenderLiquidGlassFilter({
    required super.geometryShader,
    required super.renderShader,
    required super.lightingShader,
    required super.devicePixelRatio,
    required super.settings,
    required super.glassLink,
  });

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  _ShaderLayer? get layer => super.layer as _ShaderLayer?;

  @override
  void paintLiquidGlass(
    PaintingContext context,
    Offset offset,
    List<ShapeInLayerInfo> shapes,
    Rect boundingBox,
  ) {
    final layer = (this.layer ??= _ShaderLayer())
      ..shapes = shapes
      ..shader = renderShader
      ..devicePixelRatio = devicePixelRatio
      ..bounds = offset & size
      ..offset = offset
      ..shapeBounds = boundingBox
      ..blur = settings.blur;

    paintShapeContents(
      context,
      offset,
      shapes,
      glassContainsChild: true,
    );
    context.pushLayer(
      layer,
      (context, offset) {
        // The child is the whole app in this case
        context.paintChild(child!, offset);
      },
      offset,
    );

    paintShapeContents(
      context,
      offset,
      shapes,
      glassContainsChild: false,
    );
  }
}

/// Custom composited layer that handles the liquid glass shader effect
/// with a captured child image
class _ShaderLayer extends OffsetLayer {
  _ShaderLayer();

  double _blur = 0;
  double get blur => _blur;
  set blur(double value) {
    if (_blur == value) return;
    _blur = value;
    markNeedsAddToScene();
  }

  List<ShapeInLayerInfo> _shapes = [];
  List<ShapeInLayerInfo> get shapes => _shapes;
  set shapes(List<ShapeInLayerInfo> value) {
    if (_shapes == value) return;
    _shapes = value;
    markNeedsAddToScene();
  }

  FragmentShader? _shader;
  FragmentShader get shader => _shader!;
  set shader(FragmentShader value) {
    if (_shader == value) return;
    _shader = value;
    markNeedsAddToScene();
  }

  Rect? _bounds;
  Rect get bounds => _bounds!;
  set bounds(Rect value) {
    if (_bounds == value) return;
    _bounds = value;
    markNeedsAddToScene();
  }

  Rect? _shapeBounds;
  Rect get shapeBounds => _shapeBounds!;
  set shapeBounds(Rect value) {
    if (_shapeBounds == value) return;
    _shapeBounds = value;
    markNeedsAddToScene();
  }

  double? _devicePixelRatio;
  double get devicePixelRatio => _devicePixelRatio!;
  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    markNeedsAddToScene();
  }

  Path? _clipPath;
  Path get clipPath => _clipPath!;
  set clipPath(Path value) {
    if (_clipPath == value) return;
    _clipPath = value;
    markNeedsAddToScene();
  }

  ui.Image? childImage;

  @override
  void addToScene(ui.SceneBuilder builder) {
    _captureChildLayer();

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    engineLayer = builder.pushOffset(offset.dx, offset.dy);
    {
      addChildrenToScene(builder);
      if (childImage != null) {
        shader
          ..setImageSampler(0, childImage!)
          ..setFloat(0, bounds.width * devicePixelRatio)
          ..setFloat(1, bounds.height * devicePixelRatio);
        canvas
          ..scale(1 / devicePixelRatio)
          ..drawRect(
            (shapeBounds.topLeft * devicePixelRatio) &
                (shapeBounds.size * devicePixelRatio),
            ui.Paint()..shader = shader,
          );
      }

      final picture = recorder.endRecording();
      builder.addPicture(offset, picture);
    }
    builder.pop();
  }

  void _captureChildLayer() {
    childImage?.dispose();
    childImage = _buildBlurredImage();
  }

  ui.Image _buildBlurredImage() {
    final builder = ui.SceneBuilder();

    final transform = Matrix4.diagonal3Values(
      devicePixelRatio,
      devicePixelRatio,
      1,
    );
    builder.pushTransform(transform.storage);
    if (blur > 0) {
      // We only need to capture the area that will be blurred
      builder.pushImageFilter(
        ui.ImageFilter.blur(
          sigmaX: blur,
          sigmaY: blur,
          tileMode: ui.TileMode.mirror,
        ),
      );
    }

    addChildrenToScene(builder);

    if (blur > 0) {
      builder.pop();
    }

    builder.pop();

    return builder.build().toImageSync(
          (devicePixelRatio * bounds.width).ceil(),
          (devicePixelRatio * bounds.height).ceil(),
        );
  }

  @override
  void dispose() {
    childImage?.dispose();
    super.dispose();
  }
}

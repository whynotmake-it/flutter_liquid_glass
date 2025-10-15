// ignore_for_file: avoid_setters_without_getters

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/glass_link.dart';
import 'package:liquid_glass_renderer/src/internal/multi_shader_builder.dart';
import 'package:liquid_glass_renderer/src/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_scope.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_settings.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_shader_render_object.dart';
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
  late final _glassLink = GlassLink();

  @override
  void dispose() {
    _glassLink.dispose();
    super.dispose();
  }

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

    return LiquidGlassScope(
      settings: widget.settings,
      link: _glassLink,
      child: MultiShaderBuilder(
        assetKeys: [
          liquidGlassRenderShader,
          liquidGlassGeometryShader,
          liquidGlassLightingShader,
        ],
        (context, shaders, child) => _RawShapes(
          renderShader: shaders[0],
          geometryShader: shaders[1],
          lightingShader: shaders[2],
          settings: widget.settings,
          restrictThickness: widget.restrictThickness,
          glassLink: _glassLink,
          child: child!,
        ),
        child: widget.child,
      ),
    );
  }
}

class _RawShapes extends SingleChildRenderObjectWidget {
  const _RawShapes({
    required this.renderShader,
    required this.geometryShader,
    required this.lightingShader,
    required this.settings,
    required this.restrictThickness,
    required Widget super.child,
    required this.glassLink,
  });

  final FragmentShader geometryShader;
  final FragmentShader renderShader;
  final FragmentShader lightingShader;
  final LiquidGlassSettings settings;
  final bool restrictThickness;
  final GlassLink glassLink;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderLiquidGlassLayer(
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      renderShader: renderShader,
      geometryShader: geometryShader,
      lightingShader: lightingShader,
      settings: settings,
      glassLink: glassLink,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLiquidGlassLayer renderObject,
  ) {
    renderObject
      ..glassLink = glassLink
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context)
      ..settings = settings;
  }
}

@internal
class RenderLiquidGlassLayer extends LiquidGlassShaderRenderObject {
  RenderLiquidGlassLayer({
    required super.geometryShader,
    required super.renderShader,
    required super.lightingShader,
    required super.devicePixelRatio,
    required super.settings,
    required super.glassLink,
  });

  @override
  bool get alwaysNeedsCompositing => true;

  final _shaderHandle = LayerHandle<BackdropFilterLayer>();
  final _blurLayerHandle = LayerHandle<BackdropFilterLayer>();
  final _clipLayerHandle = LayerHandle<ClipPathLayer>();

  @override
  void paintLiquidGlass(
    PaintingContext context,
    Offset offset,
    List<ShapeInLayerInfo> shapes,
    Rect boundingBox,
  ) {
    final shaderLayer = (_shaderHandle.layer ??= BackdropFilterLayer())
      ..filter = ImageFilter.shader(renderShader);

    final blurLayer = (_blurLayerHandle.layer ??= BackdropFilterLayer())
      ..filter = ImageFilter.blur(
        tileMode: TileMode.mirror,
        sigmaX: settings.blur,
        sigmaY: settings.blur,
      );

    final clipPath = Path();
    for (final shape in shapes) {
      final globalTransform = shape.renderObject.getTransformTo(this);

      clipPath.addPath(
        shape.renderObject.getPath(),
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
              paintShapeContents(
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
      ..pushLayer(
        shaderLayer,
        (context, offset) => paintShapeContents(
          context,
          offset,
          shapes,
          glassContainsChild: false,
        ),
        offset,
      );
  }

  @override
  void dispose() {
    _blurLayerHandle.layer = null;
    _shaderHandle.layer = null;
    _clipLayerHandle.layer = null;
    super.dispose();
  }
}

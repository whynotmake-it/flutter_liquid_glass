// ignore_for_file: avoid_setters_without_getters

import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/multi_shader_builder.dart';
import 'package:liquid_glass_renderer/src/internal/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_renderer/src/internal/transform_tracking_repaint_boundary_mixin.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_render_scope.dart';
import 'package:liquid_glass_renderer/src/logging.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';
import 'package:meta/meta.dart';

/// Represents a layer of multiple [LiquidGlass] shapes or
/// [LiquidGlassBlendGroup]s that have shared [LiquidGlassSettings] and will be
/// rendered together.
///
/// If you create a [LiquidGlassLayer] with one or more [LiquidGlass] or
/// [LiquidGlassBlendGroup] widgets, the liquid glass effect will be rendered
/// where this layer is.
///
/// Make sure not to stack any other widgets between the [LiquidGlassLayer] and
/// the [LiquidGlass] widgets, otherwise the liquid glass effect will be behind
/// them.
///
/// ## Example
///
/// ```dart
/// Widget build(BuildContext context) {
///   return LiquidGlassLayer(
///     child: Column(
///       children: [
///         LiquidGlass(
///           shape: LiquidRoundedSuperellipse(
///             borderRadius: 10,
///           ),
///           child: const SizedBox.square(
///             dimension: 100,
///           ),
///         ),
///         const SizedBox(height: 100),
///         LiquidGlassBlendGroup(
///          blend: 20,
///          child: Row(
///             children: [
///               LiquidGlass.grouped(
///                 shape: const LiquidOval(),
///                 child: const SizedBox.square(
///                   dimension: 100,
///                 ),
///               ),
///               LiquidGlass.grouped(
///                 shape: const LiquidRoundedSuperellipse(
///                   borderRadius: 20,
///                 ),
///                 child: const SizedBox.square(
///                   dimension: 100,
///                 ),
///               ),
///             ],
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
    this.fake = false,
    this.useBackdropGroup = false,
    super.key,
  });

  /// The subtree in which you should include at least one [LiquidGlass] widget.
  ///
  /// The [LiquidGlassLayer] will automatically register all [LiquidGlass]
  /// widgets in the subtree as shapes and render them.
  final Widget child;

  /// The settings for the liquid glass effect for all shapes in this layer.
  final LiquidGlassSettings settings;

  /// Whether to replace all liquid glass effects in this layer with
  /// [FakeGlass] effects.
  final bool fake;

  /// Whether to look up the tree for a [BackdropGroup] to use for this layer's
  /// blur.
  ///
  /// If you have multiple [LiquidGlassLayer]s in a subtree that use the same
  /// background blur, setting this to true can improve performance by sharing
  /// the same backdrop.
  ///
  /// If [fake] is true, this will be ignored, as this widget will already use
  /// a shared backdrop for the fake glass effect.
  ///
  /// Defaults to false.
  final bool useBackdropGroup;

  /// Whether there is a [LiquidGlassLayer] in the widget tree above the given
  /// [context].
  static bool existsIn(BuildContext context, {bool watch = true}) {
    return LiquidGlassRenderScope.maybeOf(context, watch: watch) != null;
  }

  @override
  State<LiquidGlassLayer> createState() => _LiquidGlassLayerState();
}

class _LiquidGlassLayerState extends State<LiquidGlassLayer>
    with SingleTickerProviderStateMixin {
  late final GeometryRenderLink _link = GeometryRenderLink();

  late final logger = Logger(LgrLogNames.layer);

  /// Extra direct-render shader instances for connected-component multi-pass
  /// rendering (Phase 6). Each pass needs its own instance because
  /// `ImageFilter.shader` reads the shader's uniforms at composite time.
  List<FragmentShader>? _componentShaders;

  @override
  void initState() {
    super.initState();
    _loadComponentShaders();
  }

  Future<void> _loadComponentShaders() async {
    try {
      final program = await FragmentProgram.fromAsset(
        ShaderKeys.liquidGlassDirectRender,
      );
      if (!mounted) return;
      setState(() {
        _componentShaders = List.generate(
          _maxComponentPasses,
          (_) => program.fragmentShader(),
        );
      });
    } on Object catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack),
      );
    }
  }

  static const int _maxComponentPasses = 4;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.fake || !ImageFilter.isShaderFilterSupported) {
      if (!ImageFilter.isShaderFilterSupported) {
        logger.warning(
          'LiquidGlassLayer is only supported when using Impeller at the '
          'moment. Falling back to FakeGlass for LiquidGlassLayer. '
          'To prevent this warning, enable Impeller, or set '
          'LiquidGlassLayer.fake to true before you use liquid glass widgets '
          'on Skia.',
        );
      }

      return LiquidGlassRenderScope(
        settings: widget.settings,
        useFake: true,
        child: InheritedGeometryRenderLink(
          link: _link,
          child: BackdropGroup(child: widget.child),
        ),
      );
    }

    return RepaintBoundary(
      child: LiquidGlassRenderScope(
        settings: widget.settings,
        child: InheritedGeometryRenderLink(
          link: _link,
          child: MultiShaderBuilder(
            assetKeys: [
              ShaderKeys.liquidGlassRender,
              ShaderKeys.liquidGlassDirectRender,
            ],
            (context, shaders, child) => _RawShapes(
              renderShader: shaders[0],
              directRenderShader: shaders[1],
              componentShaders: _componentShaders,
              backdropKey: widget.useBackdropGroup
                  ? BackdropGroup.of(context)?.backdropKey
                  : null,
              settings: widget.settings,
              link: _link,
              child: child!,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _RawShapes extends SingleChildRenderObjectWidget {
  const _RawShapes({
    required this.renderShader,
    required this.directRenderShader,
    required this.componentShaders,
    required this.backdropKey,
    required this.settings,
    required Widget super.child,
    required this.link,
  });

  final FragmentShader renderShader;
  final FragmentShader directRenderShader;
  final List<FragmentShader>? componentShaders;
  final BackdropKey? backdropKey;
  final LiquidGlassSettings settings;
  final GeometryRenderLink link;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderLiquidGlassLayer(
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      renderShader: renderShader,
      directRenderShader: directRenderShader,
      componentShaders: componentShaders,
      backdropKey: backdropKey,
      settings: settings,
      link: link,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLiquidGlassLayer renderObject,
  ) {
    renderObject
      ..link = link
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context)
      ..directRenderShader = directRenderShader
      ..componentShaders = componentShaders
      ..settings = settings
      ..backdropKey = backdropKey;
  }
}

@internal
class RenderLiquidGlassLayer extends LiquidGlassRenderObject
    with TransformTrackingRenderObjectMixin {
  RenderLiquidGlassLayer({
    required super.renderShader,
    required this._directRenderShader,
    required this._componentShaders,
    required super.backdropKey,
    required super.devicePixelRatio,
    required super.settings,
    required super.link,
  });

  FragmentShader _directRenderShader;
  FragmentShader get directRenderShader => _directRenderShader;
  set directRenderShader(FragmentShader value) {
    if (_directRenderShader == value) return;
    _directRenderShader = value;
    markNeedsPaint();
  }

  List<FragmentShader>? _componentShaders;
  List<FragmentShader>? get componentShaders => _componentShaders;
  set componentShaders(List<FragmentShader>? value) {
    if (_componentShaders == value) return;
    _componentShaders = value;
    markNeedsPaint();
  }

  final _shaderHandle = LayerHandle<BackdropFilterLayer>();
  final _clipRectLayerHandle = LayerHandle<ClipRectLayer>();

  /// Per-component layer handles for multi-pass (Phase 6) rendering.
  final _componentBackdropHandles = <LayerHandle<BackdropFilterLayer>>[];
  final _componentClipHandles = <LayerHandle<ClipRectLayer>>[];

  @override
  Size get desiredMatteSize => switch (owner?.rootNode) {
    final RenderView rv => rv.size,
    final RenderBox rb => rb.size,
    _ => Size.zero,
  };

  @override
  Matrix4 get matteTransform => getTransformTo(null);

  @override
  void onTransformChanged() {
    needsGeometryUpdate = true;
    markNeedsPaint();
  }

  @override
  void paintLiquidGlass(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> shapes,
    Rect boundingBox,
  ) {
    if (!attached) return;
    _pushGlassLayers(
      context,
      offset,
      shapes,
      boundingBox,
      ImageFilter.shader(renderShader),
    );
  }

  @override
  List<double>? gatherDirectShapeUniforms() {
    // Direct rendering is only supported for a single (axis-aligned) blend
    // group; otherwise we cannot collapse the geometry into a single inline
    // SDF evaluation and fall back to the texture pipeline.
    final geometries = link.shapes;
    if (geometries.length != 1) return null;
    return geometries.first.gatherDirectShapeData(devicePixelRatio);
  }

  @override
  List<DirectComponent>? gatherDirectComponents() {
    final shaders = _componentShaders;
    if (shaders == null) return null;
    final geometries = link.shapes;
    if (geometries.length != 1) return null;
    final components = geometries.first.gatherDirectComponents(
      devicePixelRatio,
    );
    if (components == null || components.length > shaders.length) return null;
    return components;
  }

  @override
  void paintLiquidGlassComponents(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> shapes,
    Rect boundingBox,
    List<DirectComponent> components,
  ) {
    if (!attached) return;
    final shaders = _componentShaders!;

    _resizeComponentHandles(components.length);

    final blurFilter = settings.effectiveBlur > 0
        ? ImageFilter.blur(
            tileMode: TileMode.mirror,
            sigmaX: settings.effectiveBlur,
            sigmaY: settings.effectiveBlur,
          )
        : null;

    // One independent, clipped backdrop pass per component. Each uses its own
    // shader instance so the uniforms survive until composite time.
    for (var i = 0; i < components.length; i++) {
      final component = components[i];
      final shader = shaders[i];
      _updateDirectShaderSettingsOn(shader);

      final numShapes = component.uniforms[0];
      final blend = component.uniforms[1];
      final shapeData = component.uniforms.sublist(2);
      shader.setFloatUniforms(initialIndex: 26, (value) {
        value
          ..setFloat(numShapes)
          ..setFloat(blend)
          ..setFloats(shapeData);
      });

      final glassFilter = ImageFilter.shader(shader);
      final composedFilter = switch (blurFilter) {
        final blur? => ImageFilter.compose(inner: blur, outer: glassFilter),
        null => glassFilter,
      };

      final shaderLayer =
          (_componentBackdropHandles[i].layer ??= BackdropFilterLayer())
            ..filter = composedFilter
            ..backdropKey = backdropKey;

      _componentClipHandles[i].layer = context.pushClipRect(
        needsCompositing,
        offset,
        component.clipBoundsLogical,
        (context, offset) {
          context.pushLayer(shaderLayer, (context, offset) {}, offset);
        },
        oldLayer: _componentClipHandles[i].layer,
      );
    }

    // Children always paint on top of all glass passes.
    paintShapeContents(context, offset, shapes);
  }

  void _resizeComponentHandles(int count) {
    while (_componentBackdropHandles.length < count) {
      _componentBackdropHandles.add(LayerHandle<BackdropFilterLayer>());
      _componentClipHandles.add(LayerHandle<ClipRectLayer>());
    }
    // Release any passes no longer needed this frame.
    for (var i = count; i < _componentBackdropHandles.length; i++) {
      _componentBackdropHandles[i].layer = null;
      _componentClipHandles[i].layer = null;
    }
  }

  @override
  void paintLiquidGlassDirect(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> shapes,
    Rect boundingBox,
    List<double> directUniforms,
  ) {
    if (!attached) return;

    _updateDirectShaderSettingsOn(_directRenderShader);

    final numShapes = directUniforms[0];
    final blend = directUniforms[1];
    final shapeData = directUniforms.sublist(2);

    _directRenderShader.setFloatUniforms(initialIndex: 26, (value) {
      value
        ..setFloat(numShapes)
        ..setFloat(blend)
        ..setFloats(shapeData);
    });

    _pushGlassLayers(
      context,
      offset,
      shapes,
      boundingBox,
      ImageFilter.shader(_directRenderShader),
    );
  }

  /// Uploads the current [LiquidGlassSettings] to a direct render shader.
  ///
  /// Layout mirrors `liquid_glass_direct_render.frag`: `uSize` (indices 0-1) is
  /// populated automatically by `ImageFilter.shader`, so the settings start at
  /// index 2 and the shape data follows at index 26.
  void _updateDirectShaderSettingsOn(FragmentShader shader) {
    shader.setFloatUniforms(initialIndex: 2, (value) {
      value
        ..setColor(settings.effectiveGlassColor)
        ..setFloats([
          settings.refractiveIndex,
          settings.effectiveChromaticAberration,
          settings.effectiveThickness,
          settings.effectiveLightIntensity,
          settings.effectiveAmbientStrength,
          settings.effectiveSaturation,
        ])
        ..setOffset(
          Offset(
            cos(settings.lightAngle),
            sin(settings.lightAngle),
          ),
        )
        ..setColor(settings.effectiveHighlightColor)
        ..setColor(settings.effectiveEdgeColor)
        ..setFloats([
          settings.effectiveEdgeWidth,
          settings.edgeInset,
          settings.effectiveBleedStrength,
          settings.specularWrap,
        ]);
    });
  }

  void _pushGlassLayers(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> shapes,
    Rect boundingBox,
    ImageFilter glassFilter,
  ) {
    final blurFilter = settings.effectiveBlur > 0
        ? ImageFilter.blur(
            tileMode: TileMode.mirror,
            sigmaX: settings.effectiveBlur,
            sigmaY: settings.effectiveBlur,
          )
        : null;

    final composedFilter = switch (blurFilter) {
      final blur? => ImageFilter.compose(
        inner: blur,
        outer: glassFilter,
      ),
      null => glassFilter,
    };

    final shaderLayer = (_shaderHandle.layer ??= BackdropFilterLayer())
      ..filter = composedFilter
      // Share the backdrop capture across layers that opt into a backdrop
      // group (LiquidGlassLayer.useBackdropGroup) to avoid redundant snapshots.
      ..backdropKey = backdropKey;

    _clipRectLayerHandle.layer = context.pushClipRect(
      needsCompositing,
      offset,
      boundingBox,
      (context, offset) {
        context.pushLayer(
          shaderLayer,
          (context, offset) {
            paintShapeContents(context, offset, shapes);
          },
          offset,
        );
      },
      oldLayer: _clipRectLayerHandle.layer,
    );
  }

  @override
  void dispose() {
    _shaderHandle.layer = null;
    _clipRectLayerHandle.layer = null;
    for (final handle in _componentBackdropHandles) {
      handle.layer = null;
    }
    for (final handle in _componentClipHandles) {
      handle.layer = null;
    }
    super.dispose();
  }
}

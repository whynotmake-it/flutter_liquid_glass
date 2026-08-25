// ignore_for_file: avoid_setters_without_getters

import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/multi_shader_builder.dart';
import 'package:liquid_glass_renderer/src/internal/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_renderer/src/internal/snap_rect_to_pixels.dart';
import 'package:liquid_glass_renderer/src/internal/transform_tracking_repaint_boundary_mixin.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_render_scope.dart';
import 'package:liquid_glass_renderer/src/logging.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';

// The Apple-match harness can ablate the legacy Canvas contour while fitting
// the shader's material contour. This is deliberately compile-time and
// private: production callers do not get a second public outline switch.
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
    this.backdropKey,
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

  /// Whether to share the nearest ancestor [BackdropGroup]'s capture for
  /// backdrop effects.
  ///
  /// If you have multiple [LiquidGlassLayer]s in a subtree that use the same
  /// background blur, setting this to true can improve performance by sharing
  /// the same backdrop.
  ///
  /// This applies consistently to real and fake glass and is independent from
  /// [LiquidGlassBlendGroup], which only controls geometry blending.
  /// [backdropKey] takes precedence when both are provided.
  ///
  /// Defaults to false.
  final bool useBackdropGroup;

  /// An explicit backdrop capture key for blur and refraction sharing.
  ///
  /// Multiple non-overlapping glass effects can reuse the same key to avoid
  /// repeated backdrop captures. Effects that overlap should use different
  /// keys because Flutter treats a shared key as a single backdrop filter.
  final BackdropKey? backdropKey;

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

  FlutterGpuGeometryRenderer? _gpuGeometryRenderer;
  bool _triedGpuGeometryRenderer = false;
  bool _gpuInitializationScheduled = false;
  bool _loggedFallback = false;

  void _logDebugFallback(String message) {
    if (!kDebugMode || _loggedFallback) return;
    _loggedFallback = true;
    debugPrint('liquid_glass_renderer: $message');
  }

  void _scheduleGpuGeometryRendererInitialization() {
    if (_triedGpuGeometryRenderer || _gpuInitializationScheduled) return;
    _gpuInitializationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _gpuInitializationScheduled = false;
      if (!mounted || widget.fake || _triedGpuGeometryRenderer) return;

      _triedGpuGeometryRenderer = true;
      try {
        final renderer = await FlutterGpuGeometryRenderer.fromAsset(
          ShaderKeys.gpuGeometryShaderBundle,
        );
        if (!mounted) {
          renderer.dispose();
          return;
        }
        _gpuGeometryRenderer = renderer;
      } on Object catch (error) {
        if (!mounted) return;
        _logDebugFallback(
          'Flutter GPU is unavailable; LiquidGlassLayer is using FakeGlass. '
          'Enable Impeller and Flutter GPU for the full glass effect. $error',
        );
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _gpuGeometryRenderer?.dispose();
    _link.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backdropKey =
        widget.backdropKey ??
        (widget.useBackdropGroup
            ? BackdropGroup.of(context)?.backdropKey
            : null);
    final shaderFiltersSupported = ImageFilter.isShaderFilterSupported;
    if (!widget.fake && shaderFiltersSupported) {
      // Android's Impeller context is not available until its first surface
      // frame has been established. Creating flutter_gpu resources directly
      // from build can therefore block the UI isolate before the first frame.
      _scheduleGpuGeometryRendererInitialization();
    }
    final gpuRenderer = _gpuGeometryRenderer;
    final useFake =
        widget.fake || !shaderFiltersSupported || gpuRenderer == null;
    if (useFake) {
      if (!widget.fake && !shaderFiltersSupported && kDebugMode) {
        _logDebugFallback(
          'Impeller shader filters are unavailable; LiquidGlassLayer is using '
          'FakeGlass. Enable Impeller and Flutter GPU for the full effect.',
        );
      }

      return LiquidGlassRenderScope(
        settings: widget.settings,
        useFake: true,
        backdropKey: backdropKey,
        child: InheritedGeometryRenderLink(
          link: _link,
          child: widget.child,
        ),
      );
    }

    return RepaintBoundary(
      child: LiquidGlassRenderScope(
        settings: widget.settings,
        backdropKey: backdropKey,
        child: InheritedGeometryRenderLink(
          link: _link,
          child: MultiShaderBuilder(
            assetKeys: [
              ShaderKeys.liquidGlassRender,
            ],
            (context, shaders, child) {
              return _RawShapes(
                renderShader: shaders[0],
                backdropKey: backdropKey,
                settings: widget.settings,
                link: _link,
                gpuGeometryRenderer: gpuRenderer,
                child: child!,
              );
            },
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
    required this.backdropKey,
    required this.settings,
    required Widget super.child,
    required this.link,
    this.gpuGeometryRenderer,
  });

  final FragmentShader renderShader;
  final BackdropKey? backdropKey;
  final LiquidGlassSettings settings;
  final GeometryRenderLink link;
  final FlutterGpuGeometryRenderer? gpuGeometryRenderer;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderLiquidGlassLayer(
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      renderShader: renderShader,
      backdropKey: backdropKey,
      settings: settings,
      link: link,
      gpuGeometryRenderer: gpuGeometryRenderer,
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
      ..settings = settings
      ..backdropKey = backdropKey
      ..gpuGeometryRenderer = gpuGeometryRenderer;
  }
}

@internal
class RenderLiquidGlassLayer extends LiquidGlassRenderObject
    with TransformTrackingRenderObjectMixin {
  RenderLiquidGlassLayer({
    required super.renderShader,
    required super.backdropKey,
    required super.devicePixelRatio,
    required super.settings,
    required super.link,
    super.gpuGeometryRenderer,
  });

  final _shaderHandle = LayerHandle<BackdropFilterLayer>();
  final _clipPathLayerHandle = LayerHandle<ClipPathLayer>();
  final _clipRectLayerHandle = LayerHandle<ClipRectLayer>();

  @visibleForTesting
  BackdropFilterLayer? get debugBackdropFilterLayer => _shaderHandle.layer;

  @override
  // Geometry is encoded in this layer's local coordinate space. Ancestor
  // transforms are applied once by Flutter when the completed layer is
  // composited. Baking getTransformTo(null) into the matte would apply scale
  // and rotation here and then a second time during compositing.
  Matrix4 get matteTransform => Matrix4.identity();

  @override
  Matrix4 get shaderCoordinateTransform => getTransformTo(null);

  @override
  void onTransformChanged() {
    // Geometry and FlutterFragCoord share this layer's clip space, so ancestor
    // motion is compositor-only. Do not cross the repaint boundary or rebuild
    // the native image filter after the first paint.
    if (hasReusableGeometry) {
      syncCoordinateMapping();
    } else {
      markNeedsPaint();
    }
  }

  void onCompositing() {
    if (!attached) return;
    var dirty = false;
    for (final geometry in link.shapes) {
      if (geometry.pollRelativeTransforms(this)) {
        dirty = true;
      }
    }
    if (dirty) {
      markNeedsPaint();
    }
  }

  ImageFilter? _cachedFilter;
  Object? _cachedFilterSnapshot;

  @override
  void paintLiquidGlass(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> shapes,
    Rect boundingBox,
  ) {
    if (!attached) return;
    final filterBounds = boundingBox.expandToPixelBuckets(devicePixelRatio);

    // The engine snapshots this shader's uniforms into the native image
    // filter at creation, so the composed filter can only be reused while
    // every snapshotted input is unchanged. Repaints with identical shader
    // inputs (for example a static layer invalidated by foreground content)
    // skip all Dart and native filter allocation.
    final snapshot = shaderInputSnapshot;
    var shaderFilter = _cachedFilter;
    if (shaderFilter == null || _cachedFilterSnapshot != snapshot) {
      final blurFilter = settings.effectiveFrost > 0
          ? ImageFilter.blur(
              tileMode: TileMode.mirror,
              sigmaX: settings.effectiveFrost,
              sigmaY: settings.effectiveFrost,
            )
          : null;
      shaderFilter = switch (blurFilter) {
        final blur? => ImageFilter.compose(
          inner: blur,
          outer: ImageFilter.shader(renderShader),
        ),
        null => ImageFilter.shader(renderShader),
      };
      _cachedFilter = shaderFilter;
      _cachedFilterSnapshot = snapshot;
    }

    final shaderLayer = (_shaderHandle.layer ??= BackdropFilterLayer())
      ..filter = shaderFilter
      ..backdropKey = backdropKey;

    Path clipPath;
    if (shapes.length == 1 && shapes.first.$3.isIdentity()) {
      clipPath = shapes.first.$2.path;
    } else {
      clipPath = Path();
      for (final geometry in shapes) {
        if (!geometry.$1.attached) continue;

        clipPath.addPath(
          geometry.$2.path,
          Offset.zero,
          matrix4: geometry.$3.storage,
        );
      }
    }
    _clipPathLayerHandle.layer = context
        // First we push the clipped blur layer
        .pushClipPath(
          needsCompositing,
          offset,
          boundingBox,
          clipPath,
          (context, offset) {
            // If glass contains child we paint it above blur but below shader
            paintShapeContents(
              context,
              offset,
              shapes,
              insideGlass: true,
            );
          },
          oldLayer: _clipPathLayerHandle.layer,
        );

    _clipRectLayerHandle.layer = context.pushClipRect(
      needsCompositing,
      offset,
      filterBounds,
      (context, offset) {
        context.pushLayer(
          shaderLayer,
          (context, offset) {
            paintShapeContents(
              context,
              offset,
              shapes,
              insideGlass: false,
            );
          },
          offset,
        );
      },
      oldLayer: _clipRectLayerHandle.layer,
    );
  }

  @override
  void releaseCompositorFilter() {
    _shaderHandle.layer = null;
    _clipPathLayerHandle.layer = null;
    _clipRectLayerHandle.layer = null;
    _cachedFilter = null;
    _cachedFilterSnapshot = null;
  }

  @override
  void dispose() {
    _shaderHandle.layer = null;
    _clipPathLayerHandle.layer = null;
    _clipRectLayerHandle.layer = null;
    _cachedFilter = null;
    _cachedFilterSnapshot = null;
    super.dispose();
  }
}

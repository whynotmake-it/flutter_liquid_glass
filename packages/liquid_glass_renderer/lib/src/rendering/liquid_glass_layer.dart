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
import 'package:liquid_glass_renderer/src/rendering/consolidated_fake_glass_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';

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
    this.defaultAppearance,
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

  /// Appearance inherited by shapes that do not provide an override.
  ///
  /// When omitted, the fitted iOS 27 toolbar appearance follows the ambient
  /// platform brightness.
  final LiquidGlassAppearance? defaultAppearance;

  /// Whether to replace all liquid glass effects in this layer with
  /// [FakeGlass] effects.
  final bool fake;

  /// Whether to share a [BackdropGroup] capture for backdrop effects.
  ///
  /// The nearest ancestor group is used when one exists. Otherwise this layer
  /// creates a local group so its FakeGlass shapes can share backdrop capture
  /// work. Multiple [LiquidGlassLayer]s need a common ancestor group or an
  /// explicit shared [backdropKey] to share across layer boundaries.
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
  static final Map<Element, Set<_LiquidGlassLayerState>> _debugSiblings = {};
  static final Set<(int, int)> _debugWarnedPairs = {};
  static final List<String> _fakeSurfaceShaderAssets = [
    ShaderKeys.fakeGlassSurface,
  ];

  late final GeometryRenderLink _link = GeometryRenderLink();

  late final logger = Logger(LgrLogNames.layer);

  FlutterGpuGeometryRenderer? _gpuGeometryRenderer;
  List<FragmentProgram>? _independentOpacityPrograms;
  final List<FlutterGpuGeometryRenderer> _retiredGpuGeometryRenderers = [];
  bool _triedGpuGeometryRenderer = false;
  bool _gpuInitializationScheduled = false;
  bool _loggedFallback = false;
  Element? _debugParent;

  void _registerDebugSiblingCheck() {
    if (!kDebugMode) return;
    Element? parent;
    context.visitAncestorElements((element) {
      parent = element;
      return false;
    });
    if (identical(parent, _debugParent)) return;
    if (_debugParent case final oldParent?) {
      _debugSiblings[oldParent]?.remove(this);
    }
    _debugParent = parent;
    if (parent == null) return;
    final siblingParent = parent!;
    (_debugSiblings[siblingParent] ??= {}).add(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _warnForCompatibleDebugSiblings(siblingParent);
    });
  }

  void _warnForCompatibleDebugSiblings(Element parent) {
    final siblings = _debugSiblings[parent];
    final box = context.findRenderObject();
    if (siblings == null || box is! RenderBox || !box.hasSize) return;
    final bounds = box.localToGlobal(Offset.zero) & box.size;
    for (final sibling in siblings) {
      if (identical(sibling, this) || !sibling.mounted) continue;
      if (widget.settings != sibling.widget.settings ||
          widget.defaultAppearance != sibling.widget.defaultAppearance ||
          widget.fake != sibling.widget.fake ||
          widget.useBackdropGroup != sibling.widget.useBackdropGroup ||
          widget.backdropKey != sibling.widget.backdropKey) {
        continue;
      }
      final siblingBox = sibling.context.findRenderObject();
      if (siblingBox is! RenderBox || !siblingBox.hasSize) continue;
      final siblingBounds =
          siblingBox.localToGlobal(Offset.zero) & siblingBox.size;
      if (bounds.overlaps(siblingBounds)) continue;
      final ids = [identityHashCode(this), identityHashCode(sibling)]..sort();
      if (!_debugWarnedPairs.add((ids[0], ids[1]))) continue;
      debugPrint(
        'liquid_glass_renderer: compatible non-overlapping sibling '
        'LiquidGlassLayers could share one layer and backdrop capture.',
      );
    }
  }

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
        if (const bool.fromEnvironment(
          'INDEPENDENT_GLASS_OPACITY',
          defaultValue: true,
        )) {
          _independentOpacityPrograms = await Future.wait([
            FragmentProgram.fromAsset(ShaderKeys.liquidGlassRender),
            FragmentProgram.fromAsset(ShaderKeys.liquidGlassMaterialRender),
            FragmentProgram.fromAsset(ShaderKeys.liquidGlassTintRender),
          ]);
          if (!mounted || widget.fake) return;
        }
        final renderer = await FlutterGpuGeometryRenderer.fromAsset(
          ShaderKeys.gpuGeometryShaderBundle,
        );
        if (!mounted || widget.fake) {
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
  void didUpdateWidget(covariant LiquidGlassLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.fake && widget.fake) {
      final renderer = _gpuGeometryRenderer;
      _gpuGeometryRenderer = null;
      _triedGpuGeometryRenderer = false;
      if (renderer != null) {
        // The old real render subtree is removed during this rebuild. Retire
        // its textures after that frame so it cannot contaminate subsequent
        // fake-only measurements, without invalidating a sampler still used by
        // the outgoing subtree.
        _retiredGpuGeometryRenderers.add(renderer);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_retiredGpuGeometryRenderers.remove(renderer)) return;
          renderer.dispose();
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _registerDebugSiblingCheck();
  }

  @override
  void dispose() {
    if (_debugParent case final parent?) {
      final siblings = _debugSiblings[parent];
      siblings?.remove(this);
      if (siblings?.isEmpty ?? false) _debugSiblings.remove(parent);
    }
    _gpuGeometryRenderer?.dispose();
    for (final renderer in _retiredGpuGeometryRenderers) {
      renderer.dispose();
    }
    _retiredGpuGeometryRenderers.clear();
    _link.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.backdropKey == null &&
        widget.useBackdropGroup &&
        BackdropGroup.of(context) == null) {
      return BackdropGroup(
        child: Builder(builder: _buildLayer),
      );
    }
    return _buildLayer(context);
  }

  Widget _buildLayer(BuildContext context) {
    final defaultAppearance =
        widget.defaultAppearance ??
        LiquidGlassAppearance.ios27Toolbar(
          brightness: MediaQuery.platformBrightnessOf(context),
        );
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

      return _buildFakeLayer(
        backdropKey: backdropKey,
        defaultAppearance: defaultAppearance,
        settings: widget.settings,
        child: widget.child,
      );
    }

    return RepaintBoundary(
      child: LiquidGlassRenderScope(
        settings: widget.settings,
        defaultAppearance: defaultAppearance,
        backdropKey: backdropKey,
        child: InheritedGeometryRenderLink(
          link: _link,
          child: MultiShaderBuilder(
            assetKeys: [
              ShaderKeys.liquidGlassRender,
              ShaderKeys.liquidGlassMaterialRender,
              ShaderKeys.liquidGlassTintRender,
            ],
            (context, shaders, child) {
              return _RawShapes(
                defaultRenderShader: shaders[0],
                materialRenderShader: shaders[1],
                tintRenderShader: shaders[2],
                backdropKey: backdropKey,
                settings: widget.settings,
                defaultAppearance: defaultAppearance,
                link: _link,
                gpuGeometryRenderer: gpuRenderer,
                independentOpacityPrograms: _independentOpacityPrograms,
                child: child!,
              );
            },
            child: widget.child,
          ),
        ),
      ),
    );
  }

  Widget _buildFakeLayer({
    required BackdropKey? backdropKey,
    required LiquidGlassAppearance defaultAppearance,
    required LiquidGlassSettings settings,
    required Widget child,
  }) {
    // Match the full renderer's retained subtree boundary. FakeGlass paints
    // several contour-following canvas bands; without this boundary an
    // ancestor/compositor transform can make every band record again even
    // though neither the shape nor material changed.
    Widget buildFakeSurfaceLayer(FragmentShader? surfaceShader) {
      return RepaintBoundary(
        child: LiquidGlassRenderScope(
          settings: settings,
          defaultAppearance: defaultAppearance,
          consolidatesFakeBackdrop: true,
          consolidatesFakeSurface: true,
          backdropKey: backdropKey,
          child: InheritedGeometryRenderLink(
            link: _link,
            child: ConsolidatedFakeGlassLayer(
              link: _link,
              settings: settings,
              defaultAppearance: defaultAppearance,
              backdropKey: backdropKey,
              surfaceShader: surfaceShader,
              child: child,
            ),
          ),
        ),
      );
    }

    return MultiShaderBuilder(
      assetKeys: _fakeSurfaceShaderAssets,
      (_, shaders, _) => buildFakeSurfaceLayer(shaders.single),
      child: buildFakeSurfaceLayer(null),
    );
  }
}

class _RawShapes extends SingleChildRenderObjectWidget {
  const _RawShapes({
    required this.defaultRenderShader,
    required this.materialRenderShader,
    required this.tintRenderShader,
    required this.backdropKey,
    required this.settings,
    required this.defaultAppearance,
    required Widget super.child,
    required this.link,
    this.gpuGeometryRenderer,
    this.independentOpacityPrograms,
  });

  final FragmentShader defaultRenderShader;
  final FragmentShader materialRenderShader;
  final FragmentShader tintRenderShader;
  final BackdropKey? backdropKey;
  final LiquidGlassSettings settings;
  final LiquidGlassAppearance defaultAppearance;
  final GeometryRenderLink link;
  final FlutterGpuGeometryRenderer? gpuGeometryRenderer;
  final List<FragmentProgram>? independentOpacityPrograms;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderLiquidGlassLayer(
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      defaultRenderShader: defaultRenderShader,
      materialRenderShader: materialRenderShader,
      tintRenderShader: tintRenderShader,
      backdropKey: backdropKey,
      settings: settings,
      defaultAppearance: defaultAppearance,
      link: link,
      gpuGeometryRenderer: gpuGeometryRenderer,
      independentOpacityPrograms: independentOpacityPrograms,
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
      ..defaultAppearance = defaultAppearance
      ..backdropKey = backdropKey
      ..gpuGeometryRenderer = gpuGeometryRenderer;
  }
}

@internal
class RenderLiquidGlassLayer extends LiquidGlassRenderObject
    with TransformTrackingRenderObjectMixin
    implements LiquidGlassLayerRenderObject {
  RenderLiquidGlassLayer({
    required super.defaultRenderShader,
    required super.materialRenderShader,
    required super.tintRenderShader,
    required super.backdropKey,
    required super.devicePixelRatio,
    required super.settings,
    required super.defaultAppearance,
    required super.link,
    super.gpuGeometryRenderer,
    super.independentOpacityPrograms,
  });

  final _shaderHandle = LayerHandle<BackdropFilterLayer>();
  final _clipRectLayerHandle = LayerHandle<ClipRectLayer>();

  @visibleForTesting
  BackdropFilterLayer? get debugBackdropFilterLayer => _shaderHandle.layer;

  /// The most recent layer-local clip used by the native glass filter.
  ///
  /// This intentionally excludes exterior-shadow support, which is painted in
  /// a separate canvas layer before the clipped filter pass.
  @visibleForTesting
  Rect? debugFilterBounds;
  Rect? _filterMaterialBounds;
  Offset _filterPaintOffset = Offset.zero;

  @override
  // Geometry is encoded in this layer's local coordinate space. Ancestor
  // transforms are applied once by Flutter when the completed layer is
  // composited. Baking getTransformTo(null) into the matte would apply scale
  // and rotation here and then a second time during compositing.
  Matrix4 get matteTransform => Matrix4.identity();

  @override
  Matrix4 get shaderCoordinateTransform {
    final transform = getTransformTo(null);
    final translation = compositorTranslation;
    if (translation != Offset.zero) {
      transform.multiply(
        Matrix4.translationValues(translation.dx, translation.dy, 0),
      );
    }
    return transform;
  }

  @override
  void onTransformChanged() {
    // Synchronize the frame's mapping after retained translation is resolved.
    if (!hasReusableGeometry && !hasReusableIdleContents) markNeedsPaint();
  }

  @override
  void onCompositing() {
    if (!attached) return;
    syncCompositionOpacity();
    syncAncestorClips();
    final motion = pollCompositorTranslation();
    if (motion.translation case final translation?) {
      setCompositorTranslation(translation);
      final bounds = _filterMaterialBounds;
      if (bounds != null && _clipRectLayerHandle.layer != null) {
        final clip = bounds
            .shift(translation)
            .expandToPixelBuckets(devicePixelRatio)
            .shift(-translation);
        _clipRectLayerHandle.layer!.clipRect = clip.shift(_filterPaintOffset);
      }
      if (!drawableEmpty && hasReusableGeometry && syncCoordinateMapping()) {
        _shaderHandle.layer?.filter = _updateShaderFilter();
      }
      syncIndependentOpacity();
      return;
    }
    if (motion.needsRepaint &&
        (_shaderHandle.layer != null || drawableEmpty) &&
        _clipRectLayerHandle.layer != null &&
        refreshRetainedGeometry((shapes, bounds, offset) {
          _syncMaterialFilter(bounds, offset);
        })) {
      return;
    }
    syncIndependentOpacity();
    if (motion.needsRepaint) markNeedsPaint();
  }

  @override
  void onTrackingLayerDetached() {
    if (!attached) return;
    if (layer case final tracker?) {
      scheduleHiddenPassCleanup(tracker);
    }
  }

  ImageFilter? _cachedFilter;
  Object? _cachedFilterSnapshot;

  ImageFilter _updateShaderFilter() {
    final snapshot = shaderInputSnapshot;
    if (_cachedFilter != null && _cachedFilterSnapshot == snapshot) {
      return _cachedFilter!;
    }
    final shader = ImageFilter.shader(renderShader);
    final frostSigma = settings.effectiveFrost;
    final filter = frostSigma > 0
        ? ImageFilter.compose(
            inner: ImageFilter.blur(
              tileMode: TileMode.mirror,
              sigmaX: frostSigma,
              sigmaY: frostSigma,
            ),
            outer: shader,
          )
        : shader;
    _cachedFilter = filter;
    _cachedFilterSnapshot = snapshot;
    return filter;
  }

  @visibleForTesting
  bool get debugMaterialFilterAttached => _shaderHandle.layer?.parent != null;

  // Both painting and retained geometry updates need the same native filter
  // bounds. This only updates existing handles; it never paints children.
  Rect _syncMaterialFilter(Rect materialBounds, Offset offset) {
    final filterBounds = materialBounds.expandToPixelBuckets(devicePixelRatio);
    _filterMaterialBounds = materialBounds;
    _filterPaintOffset = offset;
    debugFilterBounds = filterBounds;
    _clipRectLayerHandle.layer?.clipRect = filterBounds.shift(offset);
    if (drawableEmpty) {
      _shaderHandle.layer?.remove();
      _shaderHandle.layer = null;
      _cachedFilter = null;
      _cachedFilterSnapshot = null;
    } else {
      final shader = (_shaderHandle.layer ??= BackdropFilterLayer())
        ..filter = _updateShaderFilter()
        ..backdropKey = backdropKey;
      if (_clipRectLayerHandle.layer case final clip?) {
        if (!identical(shader.parent, clip)) {
          shader.remove();
          clip.append(shader);
        }
      }
    }
    return filterBounds;
  }

  @override
  bool paintLiquidGlass(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> shapes,
    Rect boundingBox,
    PaintingContextCallback paintForeground,
  ) {
    if (!attached) return false;
    const nestBackdropContents = bool.fromEnvironment('NEST_GLASS_CONTENTS');
    // The engine snapshots this shader's uniforms into the native image
    // filter at creation, so the composed filter can only be reused while
    // every snapshotted input is unchanged. Repaints with identical shader
    // inputs (for example a static layer invalidated by foreground content)
    // skip all Dart and native filter allocation.
    final filterBounds = _syncMaterialFilter(boundingBox, offset);
    final shaderLayer = _shaderHandle.layer;

    _clipRectLayerHandle.layer = context.pushClipRect(
      needsCompositing,
      offset,
      filterBounds,
      (context, offset) {
        if (drawableEmpty) return;
        context.pushLayer(
          shaderLayer!,
          nestBackdropContents ? paintForeground : (context, offset) {},
          offset,
        );
      },
      oldLayer: _clipRectLayerHandle.layer,
    );
    return nestBackdropContents && !drawableEmpty;
  }

  @override
  void releaseCompositorFilter() {
    _shaderHandle.layer = null;
    _clipRectLayerHandle.layer = null;
    _cachedFilter = null;
    _cachedFilterSnapshot = null;
  }

  @override
  void dispose() {
    _shaderHandle.layer = null;
    _clipRectLayerHandle.layer = null;
    _cachedFilter = null;
    _cachedFilterSnapshot = null;
    super.dispose();
  }
}

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
            ],
            (context, shaders, child) {
              return _RawShapes(
                defaultRenderShader: shaders[0],
                materialRenderShader: shaders[1],
                backdropKey: backdropKey,
                settings: widget.settings,
                defaultAppearance: defaultAppearance,
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
    required this.backdropKey,
    required this.settings,
    required this.defaultAppearance,
    required Widget super.child,
    required this.link,
    this.gpuGeometryRenderer,
  });

  final FragmentShader defaultRenderShader;
  final FragmentShader materialRenderShader;
  final BackdropKey? backdropKey;
  final LiquidGlassSettings settings;
  final LiquidGlassAppearance defaultAppearance;
  final GeometryRenderLink link;
  final FlutterGpuGeometryRenderer? gpuGeometryRenderer;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderLiquidGlassLayer(
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      defaultRenderShader: defaultRenderShader,
      materialRenderShader: materialRenderShader,
      backdropKey: backdropKey,
      settings: settings,
      defaultAppearance: defaultAppearance,
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
      ..defaultAppearance = defaultAppearance
      ..backdropKey = backdropKey
      ..gpuGeometryRenderer = gpuGeometryRenderer;
  }
}

@internal
class RenderLiquidGlassLayer extends LiquidGlassRenderObject
    with TransformTrackingRenderObjectMixin {
  RenderLiquidGlassLayer({
    required super.defaultRenderShader,
    required super.materialRenderShader,
    required super.backdropKey,
    required super.devicePixelRatio,
    required super.settings,
    required super.defaultAppearance,
    required super.link,
    super.gpuGeometryRenderer,
  });

  final _shaderHandle = LayerHandle<BackdropFilterLayer>();
  final _clipPathLayerHandle = LayerHandle<ClipPathLayer>();
  final _clipRectLayerHandle = LayerHandle<ClipRectLayer>();

  @visibleForTesting
  BackdropFilterLayer? get debugBackdropFilterLayer => _shaderHandle.layer;

  @visibleForTesting
  ClipPathLayer? get debugInsideContentsClipLayer => _clipPathLayerHandle.layer;

  /// The most recent layer-local clip used by the native glass filter.
  ///
  /// This intentionally excludes exterior-shadow support, which is painted in
  /// a separate canvas layer before the clipped filter pass.
  @visibleForTesting
  Rect? debugFilterBounds;

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

  @override
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
  Path? _cachedClipPath;
  final List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)>
  _cachedClipInputs = [];

  @visibleForTesting
  Path? get debugClipPath => _cachedClipPath;

  bool _clipInputsMatch(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> current,
  ) {
    if (current.length != _cachedClipInputs.length) return false;
    for (var index = 0; index < current.length; index++) {
      final value = current[index];
      final cached = _cachedClipInputs[index];
      if (!identical(value.$1, cached.$1) ||
          !identical(value.$2, cached.$2) ||
          !_sameTransform(value.$3, cached.$3)) {
        return false;
      }
    }
    return true;
  }

  bool _sameTransform(Matrix4 a, Matrix4 b) {
    final aStorage = a.storage;
    final bStorage = b.storage;
    for (var index = 0; index < 16; index++) {
      if (aStorage[index] != bStorage[index]) return false;
    }
    return true;
  }

  bool _hasShapeContents(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> shapes, {
    required bool insideGlass,
  }) => shapes.any(
    (entry) => entry.$2.shapes.any(
      (shape) => shape.glassContainsChild == insideGlass,
    ),
  );

  @override
  void paintLiquidGlass(
    PaintingContext context,
    Offset offset,
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> shapes,
    Rect boundingBox,
  ) {
    if (!attached) return;
    final filterBounds = boundingBox.expandToPixelBuckets(devicePixelRatio);
    debugFilterBounds = filterBounds;
    // The engine snapshots this shader's uniforms into the native image
    // filter at creation, so the composed filter can only be reused while
    // every snapshotted input is unchanged. Repaints with identical shader
    // inputs (for example a static layer invalidated by foreground content)
    // skip all Dart and native filter allocation.
    final snapshot = shaderInputSnapshot;
    var shaderFilter = _cachedFilter;
    if (shaderFilter == null || _cachedFilterSnapshot != snapshot) {
      final frostSigma = settings.effectiveFrost;
      final blurFilter = frostSigma > 0
          ? ImageFilter.blur(
              tileMode: TileMode.mirror,
              sigmaX: frostSigma,
              sigmaY: frostSigma,
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

    if (_hasShapeContents(shapes, insideGlass: true)) {
      if (!_clipInputsMatch(shapes)) {
        if (shapes.length == 1 && shapes.first.$3.isIdentity()) {
          _cachedClipPath = shapes.first.$2.path;
        } else {
          final rebuiltPath = Path();
          for (final geometry in shapes) {
            if (!geometry.$1.attached) continue;
            rebuiltPath.addPath(
              geometry.$2.path,
              Offset.zero,
              matrix4: geometry.$3.storage,
            );
          }
          _cachedClipPath = rebuiltPath;
        }
        _cachedClipInputs
          ..clear()
          ..addAll(
            shapes.map((entry) => (entry.$1, entry.$2, entry.$3.clone())),
          );
      }
      _clipPathLayerHandle.layer = context.pushClipPath(
        needsCompositing,
        offset,
        boundingBox,
        _cachedClipPath!,
        (context, offset) {
          paintShapeContents(
            context,
            offset,
            shapes,
            insideGlass: true,
          );
        },
        oldLayer: _clipPathLayerHandle.layer,
      );
    } else {
      // The common case paints children above the material. Avoid retaining
      // an empty ClipPathLayer for every glass layer when there is nothing to
      // paint inside it; independent glass otherwise pays this compositor
      // cost once per shape.
      _clipPathLayerHandle.layer = null;
    }

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

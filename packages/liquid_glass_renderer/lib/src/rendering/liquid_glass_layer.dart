// ignore_for_file: avoid_setters_without_getters, cascade_invocations

import 'dart:math';
import 'dart:ui';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_shaders/flutter_shaders.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/ancestor_clip.dart';
import 'package:liquid_glass_renderer/src/internal/backdrop_capture_debug.dart';
import 'package:liquid_glass_renderer/src/internal/filter_pass_transform.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/multi_shader_builder.dart';
import 'package:liquid_glass_renderer/src/internal/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_renderer/src/internal/rounded_superellipse_parameters.dart';
import 'package:liquid_glass_renderer/src/internal/snap_rect_to_pixels.dart';
import 'package:liquid_glass_renderer/src/internal/transform_tracking_repaint_boundary_mixin.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_capture.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_render_scope.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_settings.dart';
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
///           blend: 20,
///           child: Row(
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
/// ```
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
  ///
  /// The layer also uses [FakeGlass] when Impeller shader filters or Flutter
  /// GPU are unavailable, for example on Skia.
  final bool fake;

  /// Whether to share a [BackdropGroup] capture for backdrop effects.
  ///
  /// The nearest ancestor group is used when one exists. Otherwise this layer
  /// creates a local group so its FakeGlass shapes can share backdrop capture
  /// work. Multiple [LiquidGlassLayer]s need a common ancestor group or an
  /// explicit shared [backdropKey] to share across layer boundaries.
  ///
  /// On Impeller, each independent backdrop capture does a full-screen
  /// readback (~115 mW GPU at 120 Hz on a Pixel 10) before blur or glass
  /// work. Sharing one [BackdropGroup] or [BackdropKey] pays that readback
  /// once: two real layers dropped from 797 mW to 688 mW, two plain σ7 blurs
  /// from 426 mW to 312 mW, on the same device.
  ///
  /// Shared members do not see content painted between them. Group only
  /// elements that sit over the same content plane (for example all root
  /// chrome). Do not put a sheet and the FAB above it in one group.
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

  // Fake and real subtrees never coexist, so one key keeps the user's subtree
  // alive across a renderer swap without ever being mounted twice.
  final _childKey = GlobalKey(debugLabel: 'LiquidGlassLayer.child');

  void _logDebugFallback(String message) {
    if (!kDebugMode || _loggedFallback) return;
    _loggedFallback = true;
    debugPrint('liquid_glass_renderer: $message');
  }

  void _tryCreateCachedGpuGeometryRenderer() {
    if (widget.fake ||
        !ImageFilter.isShaderFilterSupported ||
        _triedGpuGeometryRenderer) {
      return;
    }
    final renderer = FlutterGpuGeometryRenderer.tryCreateCached(
      ShaderKeys.gpuGeometryShaderBundle,
    );
    if (renderer == null) return;
    _gpuGeometryRenderer = renderer;
    _triedGpuGeometryRenderer = true;
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
  void initState() {
    super.initState();
    _tryCreateCachedGpuGeometryRenderer();
  }

  @override
  void didUpdateWidget(covariant LiquidGlassLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fake && !widget.fake) {
      _tryCreateCachedGpuGeometryRenderer();
    }
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
  void dispose() {
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
        child: KeyedSubtree(key: _childKey, child: widget.child),
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
                child: child!,
              );
            },
            child: KeyedSubtree(key: _childKey, child: widget.child),
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
    Widget buildFakeSurfaceLayer(
      FragmentShader? surfaceShader,
    ) {
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
      (_, shaders, _) => buildFakeSurfaceLayer(shaders.firstOrNull),
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
  });

  final FragmentShader defaultRenderShader;
  final FragmentShader materialRenderShader;
  final FragmentShader tintRenderShader;
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
      tintRenderShader: tintRenderShader,
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

/// The real glass layer: renders the shared shape geometry into a GPU matte
/// and paints the final shader filter over it. All shared machinery — shape
/// registration, transform and compositor-translation polling, retained
/// ancestor clips, shadows, bounds and the frame state — lives in
/// [LiquidGlassRenderObject]; this class implements only the effect.
@internal
class RenderLiquidGlassLayer extends LiquidGlassRenderObject
    with TransformTrackingRenderObjectMixin
    implements LiquidGlassLayerRenderObject {
  RenderLiquidGlassLayer({
    required this.defaultRenderShader,
    required this.materialRenderShader,
    required this.tintRenderShader,
    required super.backdropKey,
    required super.devicePixelRatio,
    required super.settings,
    required super.defaultAppearance,
    required super.link,
    this._gpuGeometryRenderer,
  }) {
    _updateShaderSettings();
  }

  final FragmentShader defaultRenderShader;
  final FragmentShader materialRenderShader;
  final FragmentShader tintRenderShader;
  FragmentShader get renderShader => switch ((
    _usesShapeAppearances,
    _usesTintOnlyAppearance,
  )) {
    (false, _) => defaultRenderShader,
    (true, true) => tintRenderShader,
    (true, false) => materialRenderShader,
  };

  FlutterGpuGeometryRenderer? _gpuGeometryRenderer;
  FlutterGpuGeometryRenderer? get gpuGeometryRenderer => _gpuGeometryRenderer;
  set gpuGeometryRenderer(FlutterGpuGeometryRenderer? value) {
    if (_gpuGeometryRenderer == value) return;
    _gpuGeometryRenderer = value;
    markNeedsPaint();
  }

  // MARK: Shader inputs

  LiquidGlassAppearance? _uniformAppearance;
  List<LiquidGlassAppearance> _shapeAppearances = const [];
  bool _usesShapeAppearances = false;
  bool _usesTintOnlyAppearance = false;

  /// Whether the latest geometry pass writes per-shape contributor data.
  @visibleForTesting
  bool get debugUsesShapeAppearances => _usesShapeAppearances;

  /// Whether only tint differs, allowing one filtered appearance lookup.
  @visibleForTesting
  bool get debugUsesTintOnlyAppearance => _usesTintOnlyAppearance;

  /// The optional contributor texture sampled by the final material pass.
  @visibleForTesting
  ui.Image? get debugMaterialImage => _materialImage;

  /// Shorter side in logical pixels of the smallest shape in this layer.
  /// Adaptive color models use it to choose the material density; it is
  /// resolved once per geometry update, never per fragment.
  double _materialShortSide = 10000;

  bool _shaderInputsChanged = true;

  /// Whether a uniform or sampler of [renderShader] changed since the last
  /// call, which also resets it.
  ///
  /// The engine copies a shader's uniforms into the native image filter when
  /// that filter is first converted (see
  /// `ReusableFragmentShader::as_image_filter`), so a filter wrapping this
  /// shader may only be reused while this stays false.
  @protected
  bool takeShaderInputsChanged() {
    final changed = _shaderInputsChanged;
    _shaderInputsChanged = false;
    return changed;
  }

  void _updateShaderSettings() {
    _shaderInputsChanged = true;
    final appearance = _uniformAppearance ?? defaultAppearance;
    _writeCommonShaderUniforms(
      defaultRenderShader,
      appearance,
      _materialCenterInMatte,
    );
    _writeCommonShaderUniforms(
      materialRenderShader,
      appearance,
      _materialCenterInMatte,
    );
    _writeCommonShaderUniforms(
      tintRenderShader,
      appearance,
      _materialCenterInMatte,
    );
  }

  void _writeCommonShaderUniforms(
    FragmentShader shader,
    LiquidGlassAppearance appearance,
    Offset materialCenter,
  ) {
    // The final shader fades the whole material with visibility, so the
    // color factors are written at full strength.
    shader.setFloatUniforms(initialIndex: 6, (value) {
      value
        ..setColor(appearance.tint)
        ..setFloats([
          settings.effectiveDisplacementScale * devicePixelRatio,
          settings.dispersion,
          settings.effectiveEdgeDistanceRange * devicePixelRatio,
          settings.highlight,
          1 - settings.effectiveBackdropShrink,
          appearance.saturation,
        ])
        ..setOffset(
          const Offset(0, 1),
        )
        ..setColor(const Color.fromARGB(255, 255, 255, 255))
        ..setColor(
          Color.fromARGB(
            (settings.contourStrength.clamp(0.0, 1.0) * 255).round(),
            0,
            0,
            0,
          ),
        )
        // Rim geometry the presets share; see [GlassRim].
        ..setFloats([
          GlassRim.bevelShadowDirectionality,
          0, // bevel shadow size response
          GlassRim.highlightWidth * devicePixelRatio,
          GlassRim.highlightOppositeStrength,
        ])
        ..setFloats([
          settings.contourWidth * devicePixelRatio,
          0, // contour transmittance
          settings.contourDirectionality,
        ])
        ..setFloats([
          0, // contour offset
          materialCenter.dx * devicePixelRatio,
          materialCenter.dy * devicePixelRatio,
          GlassRim.highlightWrap,
        ])
        ..setFloats([
          appearance.transmissionGamma,
          appearance.vibrancy,
          settings.effectiveTintAmount,
        ])
        ..setFloats([
          settings.bevelShadowStrength,
          GlassRim.bevelShadowDepth * devicePixelRatio,
          GlassRim.bevelShadowOffset * devicePixelRatio,
        ])
        ..setFloats([
          appearance.colorModel.shaderValue,
          appearance.visibility,
          FlutterGpuGeometryRenderer.materialRasterScale.toDouble(),
          _materialShortSide,
        ]);
    });
    // Float indices 53 and 54, after the 47-float common block and the
    // 6-float filter->matte mapping: frosted glass cross-fades its blur away,
    // while unfrosted glass stays alpha-1 and cross-fades its material in the
    // shader, so both match the backdrop exactly at visibility 0.
    shader
      ..setFloat(53, blurPassSigma > 0 ? 1 : 0)
      ..setFloat(54, softensInShader ? 1 : 0);
  }

  /// Largest frost, in device pixels, folded into the final pass instead of
  /// a separate blur pass. Enabling the blur pass costs about four command
  /// buffers per frame on Metal regardless of its radius.
  static const double shaderSofteningMaxDeviceSigma = 1.25;

  /// Whether the frost is small enough for the final pass's softening kernel.
  bool get softensInShader {
    final frost = _frostSigma;
    return frost > 0 &&
        frost * devicePixelRatio <= shaderSofteningMaxDeviceSigma;
  }

  /// Sigma of the separate backdrop blur pass; `0` when there is none.
  double get blurPassSigma => softensInShader ? 0 : _frostSigma;

  double get _frostSigma => settings.effectiveFrost;

  List<double> _appearanceLookupData(
    List<LiquidGlassAppearance> appearances,
  ) {
    // This is used only for mixed frames; unused lookup rows must not depend
    // on the owner's active (possibly different) uniform frame.
    final fallback = defaultAppearance;
    LiquidGlassAppearance at(int index) =>
        index < appearances.length ? appearances[index] : fallback;
    return <double>[
      for (var i = 0; i < 16; i++) ...<double>[
        at(i).tint.r,
        at(i).tint.g,
        at(i).tint.b,
        at(i).tint.a,
      ],
      for (var i = 0; i < 16; i++) ...<double>[
        at(i).saturation / 4,
        at(i).transmissionGamma / 4,
        at(i).vibrancy / 4,
        (at(i).visibility + at(i).colorModel.shaderValue * 2) / 7,
      ],
    ];
  }

  void _setShapeAppearances(List<LiquidGlassAppearance> appearances) {
    final (usesShapeAppearances, usesTintOnlyAppearance, uniformAppearance) =
        _classifyShapeAppearances(appearances, defaultAppearance);
    if (_usesShapeAppearances == usesShapeAppearances &&
        _usesTintOnlyAppearance == usesTintOnlyAppearance &&
        _uniformAppearance == uniformAppearance &&
        listEquals(_shapeAppearances, appearances)) {
      return;
    }
    _usesShapeAppearances = usesShapeAppearances;
    _usesTintOnlyAppearance = usesTintOnlyAppearance;
    _uniformAppearance = uniformAppearance;
    _shapeAppearances = List.unmodifiable(appearances);
    _updateShaderSettings();
  }

  // MARK: Retained frame hooks

  /// Whether the committed shapes exist but none can be drawn by this
  /// effect — a function of the committed geometry, so it stays correct
  /// when a retained refresh commits new shapes between paints.
  bool get drawableEmpty =>
      shapesWithGeometry.isNotEmpty && !hasDrawableGlass(shapesWithGeometry);

  /// True once geometry has been encoded, so ancestor motion can stay on the
  /// compositor without crossing this layer's repaint boundary.
  @protected
  bool get hasReusableGeometry => _geometryImage != null;

  @override
  GlassFrameState get hiddenFrameState => GlassFrameState.idle;

  @override
  bool hasDrawableGlass(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
  ) => geometries.any(
    (entry) => entry.$2.shapes.any(
      (shape) =>
          _matteShapeBasis(entry.$3, shape.shapeToGeometry ?? _identity) !=
          null,
    ),
  );

  @override
  bool isSnapshotCurrent(
    RenderLiquidGlassGeometry geometry,
    GeometryCache snapshot,
  ) => geometry.hasCurrentMatteRevision(snapshot.matteRevision);

  @override
  void onSettingsChanged(LiquidGlassSettings old) {
    final geometryInputsChanged =
        old.effectiveRefractionHeight != settings.effectiveRefractionHeight ||
        old.effectiveRefractionAmount != settings.effectiveRefractionAmount ||
        old.refractionFitsShape != settings.refractionFitsShape ||
        old.contourWidth != settings.contourWidth;
    _updateShaderSettings();
    if (geometryInputsChanged) needsGeometryUpdate = true;
  }

  @override
  void onAppearanceChanged() => _updateShaderSettings();

  @override
  void onDevicePixelRatioChanged() {
    _updateShaderSettings();
    needsGeometryUpdate = true;
  }

  // MARK: Retained matte

  /// Pre-rendered geometry texture in screen space
  ui.Image? _geometryImage;
  ui.Image? _materialImage;
  bool _ownsGeometryImages = false;

  /// The bounding box of the geometry matte in the coordinate space of the
  /// shader
  Rect _geometryMatteBounds = Rect.zero;
  Offset _materialCenterInMatte = Offset.zero;
  // The matte and material map fill the top-left of textures that only grow.
  Size _geometryTextureSize = Size.zero;
  Size _materialTextureSize = const Size(1, 1);

  /// The pre-rendered geometry texture in screen space.
  @protected
  ui.Image? get geometryImage => _geometryImage;

  @visibleForTesting
  ui.Image? get debugGeometryImage => _geometryImage;

  /// The bounding box of the geometry matte in screen space.
  @protected
  Rect get geometryMatteBounds => _geometryMatteBounds;

  /// Layer-local bounds of the geometry matte. Ancestor transforms must not
  /// change this: they are applied by the compositor, not the shader.
  @visibleForTesting
  Rect get debugGeometryMatteBounds => _geometryMatteBounds;

  final _originalShadows = LayerHandle<ContainerLayer>();

  /// Refreshes already recorded contributors before layer-tree descent.
  /// No child painting occurs here, and the unchanged/translation paths do
  /// not call this method or evaluate geometry.
  @protected
  bool refreshRetainedGeometry(
    void Function(
      List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)>,
      Rect,
      Offset,
    )
    updateMaterial,
  ) {
    if ((_geometryImage == null && !drawableEmpty) ||
        frameState == GlassFrameState.idle ||
        debugPaintLiquidGlassGeometry) {
      return false;
    }
    final candidate = <(RenderLiquidGlassGeometry, GeometryCache, Matrix4)>[];
    final bounds = collectFrameGeometry(candidate);
    // Topology changes need normal painting to rebuild clip ancestry.
    if (bounds == null ||
        !listEquals(retainedStructure, geometryStructure(candidate))) {
      return false;
    }
    commitFrameGeometry(candidate);
    final materialBounds = _prepareGeometryAppearance(bounds);
    if (!hasDrawableGlass(shapesWithGeometry)) {
      rememberFrameInputs();
    } else {
      // Keep old borrowed handles valid until the replacement is installed.
      if (!_ownsGeometryImages && _geometryImage != null) {
        final geometry = _geometryImage!.clone();
        ui.Image? material;
        try {
          material = _materialImage?.clone();
        } catch (_) {
          geometry.dispose();
          rethrow;
        }
        _geometryImage = geometry;
        _materialImage = material;
        _ownsGeometryImages = true;
      }
      final result = _buildGpuGeometryImage(shapesWithGeometry, bounds);
      _releaseGeometryImageHandles();
      _geometryImage = result.image;
      _materialImage = result.materialImage;
      _geometryMatteBounds = result.matteBounds;
      _geometryTextureSize = result.textureSize;
      _materialTextureSize = result.materialTextureSize;
      _materialCenterInMatte = result.materialCenter;
      _setShapeAppearances(result.appearances);
      _rememberEncodedGeometry(bounds);
      _bindGeometryShader(result.image);
    }
    needsGeometryUpdate = false;
    link
      ..updateAllGeometries()
      ..markClean();
    _recordOriginalShadows(retainedPaintOffset);
    updateMaterial(shapesWithGeometry, materialBounds, retainedPaintOffset);
    syncAncestorClips();
    return true;
  }

  void _clearGeometryImage() {
    _originalShadows.layer = null;
    _releaseGeometryImageHandles();
    clearFrameInputs();
  }

  void _releaseGeometryImageHandles() {
    if (_ownsGeometryImages) {
      _geometryImage?.dispose();
      _materialImage?.dispose();
      _ownsGeometryImages = false;
    }
    _geometryImage = null;
    _materialImage = null;
  }

  void _rememberEncodedGeometry(Rect bounds) {
    encodedGeometryBounds = bounds;
    rememberFrameInputs();
  }

  bool _reuseUniformlyTranslatedGeometry(Rect bounds) {
    final delta = encodedMatteDelta(bounds);
    if (delta == null) return false;
    _geometryMatteBounds = _geometryMatteBounds.shift(delta);
    _materialCenterInMatte += delta;
    _rememberEncodedGeometry(bounds);
    return true;
  }

  // MARK: Painting

  @override
  void paintFrame(
    PaintingContext context,
    Offset offset,
    Rect? geometryBounds,
  ) {
    if (geometryBounds == null) {
      _clearGeometryImage();
      _releaseCompositorFilter();
      releaseRetainedEffectLayer();
      return;
    }
    final materialPaintBounds = _prepareGeometryAppearance(geometryBounds);
    switch (frameState) {
      case GlassFrameState.empty:
        _clearGeometryImage();
        _releaseCompositorFilter();
        if (shapesWithGeometry.isEmpty) {
          releaseRetainedEffectLayer();
          return;
        }
        rememberFrameInputs();
        needsGeometryUpdate = false;
        link.markClean();
        paintRetainedEffect(context, offset, (effectContext, effectOffset) {
          _recordOriginalShadows(effectOffset);
          if (_originalShadows.layer case final shadows?) {
            effectContext.addLayer(shadows);
          }
          _paintMaterialFilter(
            effectContext,
            effectOffset,
            materialPaintBounds,
          );
        });
      case GlassFrameState.idle:
        // Keep the encoded snapshot of the last active matte untouched so
        // ancestor motion stays compositor-only when the glass becomes
        // visible again. Skip the backdrop filter so idle glass does not
        // sample.
        updateIdleAncestorClips();
        _releaseCompositorFilter();
        paintRetainedEffect(context, offset, (effectContext, effectOffset) {});
      case GlassFrameState.active:
        if (needsGeometryUpdate || _geometryImage == null || link.isDirty) {
          link
            ..updateAllGeometries()
            ..markClean();

          final canReuseTranslatedGeometry =
              !needsGeometryUpdate &&
              _geometryImage != null &&
              _reuseUniformlyTranslatedGeometry(geometryBounds);
          needsGeometryUpdate = false;

          if (!canReuseTranslatedGeometry) {
            _clearGeometryImage();
            final gpuResult = _buildGpuGeometryImage(
              shapesWithGeometry,
              geometryBounds,
            );
            _geometryImage = gpuResult.image;
            _materialImage = gpuResult.materialImage;
            _geometryMatteBounds = gpuResult.matteBounds;
            _geometryTextureSize = gpuResult.textureSize;
            _materialTextureSize = gpuResult.materialTextureSize;
            _materialCenterInMatte = gpuResult.materialCenter;
            _setShapeAppearances(gpuResult.appearances);
            _rememberEncodedGeometry(geometryBounds);
          }
        }

        paintRetainedEffect(context, offset, (effectContext, effectOffset) {
          if (debugPaintLiquidGlassGeometry) {
            _debugPaintGeometry(effectContext, effectOffset);
          } else if (_geometryImage != null) {
            _bindGeometryShader(_geometryImage!);
            _recordOriginalShadows(effectOffset);
            if (_originalShadows.layer case final shadows?) {
              effectContext.addLayer(shadows);
            }
            _paintMaterialFilter(
              effectContext,
              effectOffset,
              materialPaintBounds,
            );
          }
        });
    }
  }

  Rect _prepareGeometryAppearance(Rect boundingBox) {
    final usedShapeAppearances = _usesShapeAppearances;
    final usedTintOnlyAppearance = _usesTintOnlyAppearance;
    final appearances = [
      for (final (_, geometry, _) in shapesWithGeometry)
        for (final shape in geometry.shapes) shape.appearance,
    ];
    final appearanceValuesChanged = !listEquals(
      _shapeAppearances,
      appearances,
    );
    _setShapeAppearances(appearances);
    if (usedShapeAppearances != _usesShapeAppearances ||
        usedTintOnlyAppearance != _usesTintOnlyAppearance ||
        (_usesShapeAppearances && appearanceValuesChanged)) {
      // Mixed material data is encoded in the geometry render target. Only
      // uniform appearance changes can be applied with final-pass uniforms.
      needsGeometryUpdate = true;
    }
    final materialBounds = boundingBox.inflate(_contourOutset);
    effectPaintBounds = expandBoundsForShadows(materialBounds);
    return materialBounds;
  }

  // Resource binding is separate from recording/painting children so a
  // changed geometry frame can be prepared without invoking child paint.
  void _bindGeometryShader(ui.Image geometryImage) {
    syncCoordinateMapping();
    final activeRenderShader = renderShader;
    activeRenderShader
      ..setFloatUniforms(initialIndex: 2, (value) {
        value
          ..setOffset(_geometryMatteBounds.topLeft * devicePixelRatio)
          ..setSize(_geometryMatteBounds.size * devicePixelRatio);
      })
      ..setFloatUniforms(initialIndex: 34, (value) {
        value.setOffset(_materialCenterInMatte * devicePixelRatio);
      })
      // Float index 59, after uBackdropBounds.
      ..setFloatUniforms(initialIndex: 59, (value) {
        final matteSize = _geometryMatteBounds.size * devicePixelRatio;
        value.setFloats([
          if (_geometryTextureSize.isEmpty) ...[
            1,
            1,
          ] else ...[
            matteSize.width / _geometryTextureSize.width,
            matteSize.height / _geometryTextureSize.height,
          ],
          _materialTextureSize.width,
          _materialTextureSize.height,
        ]);
      })
      // Sampler 0 is the image-filter input. The engine replaces its texture
      // with the backdrop but keeps the sampling set here, so any bound image
      // selects bilinear or nearest backdrop sampling at no cost.
      ..setImageSampler(
        0,
        geometryImage,
        filterQuality: FilterQuality.low,
      )
      // Nearest: the matte packs 12-bit normal angle and displacement codes
      // across byte boundaries, which filtering between texels would mix.
      ..setImageSampler(1, geometryImage);
    if (_materialImage case final materialImage?) {
      if (_usesTintOnlyAppearance) {
        activeRenderShader.setImageSampler(
          2,
          materialImage,
          filterQuality: FilterQuality.low,
        );
      } else {
        activeRenderShader
          ..setImageSampler(2, materialImage)
          ..setImageSampler(3, materialImage, filterQuality: FilterQuality.low);
      }
    }
    if (!identical(geometryImage, _boundGeometryImage) ||
        !identical(_materialImage, _boundMaterialImage) ||
        _geometryMatteBounds != _boundMatteBounds) {
      _boundGeometryImage = geometryImage;
      _boundMaterialImage = _materialImage;
      _boundMatteBounds = _geometryMatteBounds;
      _shaderInputsChanged = true;
    }
  }

  ui.Image? _boundGeometryImage;
  ui.Image? _boundMaterialImage;
  Rect? _boundMatteBounds;

  // Own a replaceable picture rather than recording shadows together with
  // unrelated foreground. Geometry refresh may replace this before submission
  // without asking any child render object to paint outside the paint phase.
  void _recordOriginalShadows(Offset offset) {
    final hasShadows = shapesWithGeometry.any(
      (entry) => entry.$2.shapes.any((shape) => shape.shadows.isNotEmpty),
    );
    if (!hasShadows) {
      _originalShadows.layer = null;
      return;
    }
    final slot = _originalShadows.layer ??= ContainerLayer();
    slot.removeAllChildren();
    if (drawableEmpty) return;
    final recorder = ui.PictureRecorder();
    drawGlassShadows(Canvas(recorder), offset);
    final picture = PictureLayer(effectPaintBounds.shift(offset))
      ..picture = recorder.endRecording();
    slot.append(picture);
  }

  // MARK: Coordinate mapping

  Matrix4 get shaderCoordinateTransform => filterPassTransform(
    this,
    seeding: compositionProbeSeeding,
    devicePixelRatio: devicePixelRatio,
    translation: compositorTranslation,
  );

  (double, double, double, double, double, double)? _coordinateMapping;
  Rect? _backdropBounds;

  /// Layer-local rect the native filter captures backdrop for, or `null`
  /// when it is unbounded. Refraction mirrors samples that would leave it:
  /// outside the clip the filter input is transparent.
  @protected
  Rect? get backdropSampleBounds {
    final clip = _filterClip;
    if (clip == null || blurPassSigma <= 0) return clip;
    final translation = compositorTranslation;
    var captured = clip.shift(translation);
    final ancestorClips = [
      retainedClipBounds,
      localPaintClipAbove(
        this,
        stopAt: (ancestor) => ancestor is RenderLiquidGlassCapture,
      ),
    ];
    for (final ancestorClip in ancestorClips) {
      if (ancestorClip != null) captured = captured.intersect(ancestorClip);
    }
    return captured.shift(-translation);
  }

  /// The [backdropSampleBounds] last written to the shader.
  @visibleForTesting
  Rect? get debugBackdropSampleBounds => _backdropBounds;

  @protected
  bool syncCoordinateMapping() {
    final mapping = _currentCoordinateMapping();
    final backdropBounds = backdropSampleBounds;
    final changed =
        mapping != _coordinateMapping || backdropBounds != _backdropBounds;
    _coordinateMapping = mapping;
    _backdropBounds = backdropBounds;
    if (changed) _shaderInputsChanged = true;
    _writeCoordinateMapping(renderShader, mapping, backdropBounds);
    return changed;
  }

  (double, double, double, double, double, double) _currentCoordinateMapping() {
    final globalToMatte = Matrix4.inverted(shaderCoordinateTransform);
    final origin = MatrixUtils.transformPoint(globalToMatte, Offset.zero);
    final axisX = MatrixUtils.transformPoint(globalToMatte, const Offset(1, 0));
    final axisY = MatrixUtils.transformPoint(globalToMatte, const Offset(0, 1));
    return (
      axisX.dx - origin.dx,
      axisY.dx - origin.dx,
      axisX.dy - origin.dy,
      axisY.dy - origin.dy,
      origin.dx * devicePixelRatio,
      origin.dy * devicePixelRatio,
    );
  }

  void _writeCoordinateMapping(
    FragmentShader shader,
    (double, double, double, double, double, double) mapping,
    Rect? backdropBounds,
  ) {
    shader.setFloatUniforms(initialIndex: 47, (value) {
      value.setFloats([
        mapping.$1,
        mapping.$2,
        mapping.$3,
        mapping.$4,
        mapping.$5,
        mapping.$6,
      ]);
    });
    // Float index 55, after the frost flags.
    final matteBounds = backdropBounds ?? Rect.largest;
    shader.setFloatUniforms(initialIndex: 55, (value) {
      value.setFloats([
        matteBounds.left * devicePixelRatio,
        matteBounds.top * devicePixelRatio,
        matteBounds.right * devicePixelRatio,
        matteBounds.bottom * devicePixelRatio,
      ]);
    });
  }

  // MARK: Native filter

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

  // The native filter clip, kept on stable pixel buckets in the translated
  // frame so retained compositor motion does not resize its render target.
  Rect? get _filterClip {
    final bounds = _filterMaterialBounds;
    if (bounds == null) return null;
    final translation = compositorTranslation;
    return bounds
        .shift(translation)
        .expandToPixelBuckets(devicePixelRatio)
        .shift(-translation);
  }

  // Unblurred, the filter input is the backdrop inside the filter's own clip.
  // With a blur pass, Impeller re-rasterizes the blurred input into the
  // filter's coverage, which every clip around the filter narrows: the
  // retained clips between this layer and its shapes, and the clips above
  // this layer up to its pass. The texture is transparent outside it.
  ImageFilter? _cachedFilter;

  ImageFilter _updateShaderFilter() {
    final inputsChanged = takeShaderInputsChanged();
    if (_cachedFilter != null && !inputsChanged) return _cachedFilter!;
    final shader = ImageFilter.shader(renderShader);
    final frostSigma = blurPassSigma;
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
    return filter;
  }

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
    } else {
      syncCoordinateMapping();
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

  void _paintMaterialFilter(
    PaintingContext context,
    Offset offset,
    Rect materialBounds,
  ) {
    if (!attached) return;
    // The engine snapshots this shader's uniforms into the native image
    // filter at creation, so the composed filter can only be reused while
    // every snapshotted input is unchanged. Repaints with identical shader
    // inputs (for example a static layer invalidated by foreground content)
    // skip all Dart and native filter allocation.
    final filterBounds = _syncMaterialFilter(materialBounds, offset);
    final shaderLayer = _shaderHandle.layer;
    assert(() {
      if (!drawableEmpty && shaderLayer != null) {
        debugRegisterBackdropCapture(this, backdropKey);
      }
      return true;
    }(), 'Count independent backdrop captures in debug builds.');

    _clipRectLayerHandle.layer = context.pushClipRect(
      needsCompositing,
      offset,
      filterBounds,
      (context, offset) {
        if (drawableEmpty) return;
        context.pushLayer(shaderLayer!, (context, offset) {}, offset);
      },
      oldLayer: _clipRectLayerHandle.layer,
    );
  }

  /// Drops native backdrop-filter state while this sample is idle.
  void _releaseCompositorFilter() {
    _shaderHandle.layer = null;
    _clipRectLayerHandle.layer = null;
    _cachedFilter = null;
  }

  // MARK: Compositing

  @override
  void onTransformChanged() {
    // Synchronize the frame's mapping after retained translation is resolved.
    if (!hasReusableGeometry && !hasReusableIdleContents) markNeedsPaint();
  }

  @override
  void onCompositing() {
    if (!attached) return;
    runCompositorPoll();
  }

  @override
  void onCompositorTranslated(Offset translation) {
    final clip = _filterClip;
    if (clip != null && _clipRectLayerHandle.layer != null) {
      _clipRectLayerHandle.layer!.clipRect = clip.shift(_filterPaintOffset);
    }
    if (!drawableEmpty && hasReusableGeometry && syncCoordinateMapping()) {
      _shaderHandle.layer?.filter = _updateShaderFilter();
    }
  }

  @override
  void onCompositorTranslationMissed(
    ({bool needsRepaint, Offset? translation}) motion,
  ) {
    // A pass-origin change — the probe enabling, or a capture's clip moving
    // with paint-only changes inside it — moves no tracked transform, so the
    // translation poll misses it. Re-sync the coordinate mapping into the
    // retained filter, or repaint when its inputs cannot be reused.
    if (syncCoordinateMapping()) {
      if (!drawableEmpty &&
          hasReusableGeometry &&
          _shaderHandle.layer != null) {
        _shaderHandle.layer!.filter = _updateShaderFilter();
      } else {
        markNeedsPaint();
      }
    }
    if (motion.needsRepaint &&
        (_shaderHandle.layer != null || drawableEmpty) &&
        _clipRectLayerHandle.layer != null &&
        refreshRetainedGeometry((shapes, bounds, offset) {
          _syncMaterialFilter(bounds, offset);
        })) {
      return;
    }
    if (motion.needsRepaint) markNeedsPaint();
  }

  void _debugPaintGeometry(PaintingContext context, Offset offset) {
    if (_geometryImage case final geometryImage?) {
      final bounds = _geometryMatteBounds;
      context.canvas
        ..save()
        ..translate(
          bounds.left,
          bounds.top,
        )
        ..scale(1 / devicePixelRatio)
        ..drawImageRect(
          geometryImage,
          Offset.zero & bounds.size * devicePixelRatio,
          (offset * devicePixelRatio) & bounds.size * devicePixelRatio,
          Paint()..blendMode = BlendMode.src,
        )
        ..restore();
    }
  }

  @override
  void dispose() {
    _shaderHandle.layer = null;
    _clipRectLayerHandle.layer = null;
    _cachedFilter = null;
    _clearGeometryImage();
    _gpuGeometryRenderer = null;
    super.dispose();
  }

  // MARK: Geometry

  @protected
  bool needsGeometryUpdate = true;

  final List<double> _shapeData = [];
  final List<double> _rseData = [];
  final List<double> _boundsData = [];
  static final Matrix4 _identity = Matrix4.identity();

  @override
  double get materialOutset => _contourOutset;

  double get _contourOutset {
    if (settings.contourWidth <= 0) return 0;
    return max(
      0.5 / devicePixelRatio,
      settings.contourWidth + 1.0 / devicePixelRatio,
    );
  }

  /// How far outside the material the composed filter reads the backdrop:
  /// the blur kernel (3 sigma), the peak edge displacement including its
  /// dispersion, and, with [LiquidGlassSettings.backdropShrink], the extra
  /// content revealed on the face. A `LiquidGlassCapture` must contain this
  /// reach or the filter samples its own edge.
  double backdropSamplingReach(Rect material) {
    final blur = blurPassSigma > 0
        ? blurPassSigma * 3 + 1 / devicePixelRatio
        : (softensInShader ? 1 / devicePixelRatio : 0.0);
    final displacement =
        settings.effectiveDisplacementScale *
        (1 + settings.dispersion.abs() * 0.5);
    final scale = 1 - settings.effectiveBackdropShrink;
    final revealed = (1 / scale - 1) * max(material.width, material.height) / 2;
    return blur + displacement + revealed;
  }

  @override
  double effectSamplingReach(Rect material) => backdropSamplingReach(material);

  /// Half-extents along the matte axes of a shape with local half-size
  /// [halfSize] mapped by the affine basis ([axisX], [axisY]). The geometry
  /// shader culls with these boxes instead of mapping every pixel into each
  /// shape's local space. Ellipses and rounded rectangles are exact;
  /// continuous corners extend further into the corner than a circular arc of
  /// the same radius, so they use their box.
  static Size _matteHalfExtents(
    RawShapeType type,
    Size halfSize,
    double cornerRadius,
    Offset axisX,
    Offset axisY,
  ) {
    double extent(double x, double y) {
      switch (type) {
        case RawShapeType.ellipse:
          return sqrt(
            pow(x * halfSize.width, 2) + pow(y * halfSize.height, 2),
          );
        case RawShapeType.roundedRectangle:
          final radius = min(cornerRadius, halfSize.shortestSide);
          return x.abs() * (halfSize.width - radius) +
              y.abs() * (halfSize.height - radius) +
              radius * sqrt(x * x + y * y);
        case RawShapeType.squircle:
          return x.abs() * halfSize.width + y.abs() * halfSize.height;
      }
    }

    return Size(extent(axisX.dx, axisY.dx), extent(axisX.dy, axisY.dy));
  }

  // The encoder's drawable-shape decision. Called only while preparing
  // geometry, never during retained compositing sync.
  ({Offset axisX, Offset axisY, double determinant})? _matteShapeBasis(
    Matrix4 geometryToLayer,
    Matrix4 shapeToGeometry,
  ) {
    Offset toMatte(Offset point) => MatrixUtils.transformPoint(
      geometryToLayer,
      MatrixUtils.transformPoint(shapeToGeometry, point),
    );
    final origin = toMatte(Offset.zero);
    final axisX = toMatte(const Offset(1, 0)) - origin;
    final axisY = toMatte(const Offset(0, 1)) - origin;
    final determinant = axisX.dx * axisY.dy - axisY.dx * axisX.dy;
    if (determinant.abs() < 1e-8) return null;
    return (axisX: axisX, axisY: axisY, determinant: determinant);
  }

  _GpuGeometryFrame _buildGpuGeometryImage(
    List<(RenderLiquidGlassGeometry, GeometryCache, Matrix4)> geometries,
    Rect bounds,
  ) {
    final renderer = _gpuGeometryRenderer;
    if (renderer == null) {
      throw StateError(
        'Flutter GPU is required for LiquidGlass. Enable it in the platform '
        'manifest or with --enable-flutter-gpu.',
      );
    }

    try {
      // Centered SDF antialiasing needs half a physical pixel outside the
      // mathematical shape. Keep that margin in the persistent geometry
      // texture so the positive side of the fade is not clipped at the matte
      // edge.
      final aaPadding = max(0.5 / devicePixelRatio, _contourOutset);
      // The matte is in this layer's local coordinates. Ancestor transforms
      // are applied once by the compositor; baking them in would apply scale
      // and rotation twice.
      final boundsInMatteSpace = bounds
          .inflate(aaPadding)
          .snapToPixels(devicePixelRatio);
      final materialCenter = bounds.center;

      final textureWidth = (boundsInMatteSpace.width * devicePixelRatio).ceil();
      final textureHeight = (boundsInMatteSpace.height * devicePixelRatio)
          .ceil();

      if (textureWidth <= 0 || textureHeight <= 0) {
        throw StateError('Cannot render empty liquid-glass geometry.');
      }

      // Gather shapes in cache order. A negative blend marker starts a new
      // group; this preserves smooth unions within a group without blending
      // unrelated standalone glass widgets together.
      _shapeData.clear();
      _rseData.clear();
      _boundsData.clear();
      final appearances = <LiquidGlassAppearance>[];
      var numShapes = 0;
      var shortSide = double.infinity;

      for (final (_, geometry, geometryToLayer) in geometries) {
        var firstInGroup = true;
        for (final shape in geometry.shapes) {
          if (numShapes >= 16) break; // MAX_SHAPES limit

          final shapeToGeometry = shape.shapeToGeometry ?? _identity;
          final basis = _matteShapeBasis(geometryToLayer, shapeToGeometry);
          if (basis == null) continue;
          final (:axisX, :axisY, :determinant) = basis;

          // Inverse 2D affine basis maps matte-space physical pixels back to
          // the shape's own physical-pixel coordinate system.
          final inverse00 = axisY.dy / determinant;
          final inverse01 = -axisY.dx / determinant;
          final inverse10 = -axisX.dy / determinant;
          final inverse11 = axisX.dx / determinant;

          // The minimum singular value conservatively converts local SDF
          // distances back to screen pixels under non-uniform scaling.
          final trace =
              axisX.dx * axisX.dx +
              axisX.dy * axisX.dy +
              axisY.dx * axisY.dx +
              axisY.dy * axisY.dy;
          final discriminant = max(
            0,
            trace * trace - 4 * determinant * determinant,
          );
          final distanceScale = sqrt(
            max(0.0, (trace - sqrt(discriminant)) * 0.5),
          );

          final centerInGeometry = MatrixUtils.transformPoint(
            shapeToGeometry,
            Offset(
              shape.renderObject.size.width / 2,
              shape.renderObject.size.height / 2,
            ),
          );
          final centerInLayer = MatrixUtils.transformPoint(
            geometryToLayer,
            centerInGeometry,
          );
          final centerInMatte = centerInLayer;

          // The inverse affine basis above already maps matte coordinates back
          // into the shape's local coordinate system. Using the transformed
          // AABB here would apply scale a second time (and turn rotations into
          // oversized primitives), which is especially visible for stretched
          // shapes in a blend group.
          final size = shape.renderObject.size;
          final rseParameters = roundedSuperellipseParameters(
            size,
            shape.rawCornerRadius,
            scale: devicePixelRatio,
          );
          // The geometry shader tests each cap's angular span as
          // 1 - cos(span); FakeGlass reads the spans themselves.
          rseParameters[2] = 1.0 - cos(rseParameters[2]);
          rseParameters[3] = 1.0 - cos(rseParameters[3]);
          _rseData.addAll(rseParameters);
          final center = centerInMatte * devicePixelRatio;
          final halfExtents = _matteHalfExtents(
            shape.rawShapeType,
            size * devicePixelRatio / 2,
            shape.rawCornerRadius * devicePixelRatio,
            axisX,
            axisY,
          );
          _boundsData
            ..add(center.dx - halfExtents.width)
            ..add(center.dy - halfExtents.height)
            ..add(center.dx + halfExtents.width)
            ..add(center.dy + halfExtents.height);
          final blendMarker = firstInGroup
              ? -(geometry.blend * devicePixelRatio + 1)
              : geometry.blend * devicePixelRatio;

          _shapeData
            // vec4 0: primitive parameters.
            ..add(
              shape.appearance.visibility <= 0
                  ? 0
                  : shape.rawShapeType.shaderIndex,
            )
            ..add(size.width * devicePixelRatio)
            ..add(size.height * devicePixelRatio)
            ..add(shape.rawCornerRadius * devicePixelRatio)
            // vec4 1: inverse affine basis.
            ..add(inverse00)
            ..add(inverse01)
            ..add(inverse10)
            ..add(inverse11)
            // vec4 2: transformed center, distance scale, group marker.
            ..add(centerInMatte.dx * devicePixelRatio)
            ..add(centerInMatte.dy * devicePixelRatio)
            ..add(distanceScale)
            ..add(blendMarker);
          appearances.add(shape.appearance);
          shortSide = min(shortSide, size.shortestSide);
          numShapes++;
          firstInGroup = false;
        }
      }

      if (numShapes == 0) {
        throw StateError('No invertible liquid-glass shapes to render.');
      }
      if (shortSide != _materialShortSide) {
        _materialShortSide = shortSide;
        _updateShaderSettings();
      }
      final (usesShapeAppearances, usesTintOnlyAppearance, _) =
          _classifyShapeAppearances(appearances, defaultAppearance);

      final result = renderer.render(
        width: textureWidth,
        height: textureHeight,
        shapeData: _shapeData,
        rseData: _rseData,
        boundsData: _boundsData,
        numShapes: numShapes,
        refractionHeight: settings.effectiveRefractionHeight * devicePixelRatio,
        refractionAmount: settings.effectiveRefractionAmount * devicePixelRatio,
        edgeDistanceRange:
            settings.effectiveEdgeDistanceRange * devicePixelRatio,
        refractionFitsShape: settings.refractionFitsShape,
        contourExtent: aaPadding * devicePixelRatio,
        writeMaterials: usesShapeAppearances,
        writeTintOnly: usesTintOnlyAppearance,
        appearanceData: usesShapeAppearances
            ? _appearanceLookupData(appearances)
            : const <double>[],
        offsetX: boundsInMatteSpace.left * devicePixelRatio,
        offsetY: boundsInMatteSpace.top * devicePixelRatio,
      );
      return (
        image: result.image,
        materialImage: renderer.materialImage,
        materialCenter: materialCenter,
        textureSize: Size(
          result.textureWidth.toDouble(),
          result.textureHeight.toDouble(),
        ),
        materialTextureSize: switch (renderer.materialImage) {
          final image? => Size(image.width.toDouble(), image.height.toDouble()),
          null => const Size(1, 1),
        },
        appearances: appearances,
        matteBounds: Rect.fromLTWH(
          boundsInMatteSpace.left,
          boundsInMatteSpace.top,
          result.width / devicePixelRatio,
          result.height / devicePixelRatio,
        ),
      );
    } catch (e) {
      throw StateError('Flutter GPU geometry render failed: $e');
    }
  }
}

// Images here borrow the renderer's handles. A retained temporary frame must
// clone both images before another render can dispose those borrowed handles.
typedef _GpuGeometryFrame = ({
  Size textureSize,
  Size materialTextureSize,
  ui.Image image,
  ui.Image? materialImage,
  Rect matteBounds,
  Offset materialCenter,
  List<LiquidGlassAppearance> appearances,
});

(bool, bool, LiquidGlassAppearance?) _classifyShapeAppearances(
  List<LiquidGlassAppearance> appearances,
  LiquidGlassAppearance fallback,
) {
  final first = appearances.isEmpty ? fallback : appearances.first;
  final mixed = appearances.any((appearance) => appearance != first);
  final tintOnly =
      mixed &&
      appearances.every(
        (appearance) =>
            appearance.saturation == first.saturation &&
            appearance.transmissionGamma == first.transmissionGamma &&
            appearance.vibrancy == first.vibrancy &&
            appearance.visibility == first.visibility &&
            appearance.colorModel == first.colorModel,
      );
  return (mixed, tintOnly, tintOnly || !mixed ? first : null);
}

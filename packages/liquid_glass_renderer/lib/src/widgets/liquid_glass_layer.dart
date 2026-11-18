import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/rendering/full_glass.dart';
import 'package:liquid_glass_renderer/src/rendering/geometry_render_link.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';
import 'package:liquid_glass_renderer/src/rendering/shaders.dart';
import 'package:liquid_glass_renderer/src/widgets/consolidated_fake_glass_layer.dart';
import 'package:liquid_glass_renderer/src/widgets/fake_glass.dart';
import 'package:liquid_glass_renderer/src/widgets/glass_host.dart';
import 'package:liquid_glass_renderer/src/widgets/glass_pixel_ratio.dart';
import 'package:liquid_glass_renderer/src/widgets/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/widgets/liquid_glass_blend_group.dart';
import 'package:liquid_glass_renderer/src/widgets/liquid_glass_precache.dart';
import 'package:liquid_glass_renderer/src/widgets/liquid_glass_render_scope.dart';
import 'package:liquid_glass_renderer/src/widgets/multi_shader_builder.dart';

/// Represents a layer of multiple [LiquidGlass] shapes or
/// [LiquidGlassBlendGroup]s that have shared [LiquidGlassSettings] and will be
/// rendered together.
///
/// If you create a [LiquidGlassLayer] with one or more [LiquidGlass] or
/// [LiquidGlassBlendGroup] widgets, the liquid glass effect will be rendered
/// where this layer is.
///
/// Widgets between the layer and its [LiquidGlass] widgets that paint, such
/// as a colored background, paint over the glass: the layer draws all of its
/// glass before its child.
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
///             radius: 10,
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
///               LiquidGlass(
///                 shape: const LiquidOval(),
///                 child: const SizedBox.square(
///                   dimension: 100,
///                 ),
///               ),
///               LiquidGlass(
///                 shape: const LiquidRoundedSuperellipse(
///                   radius: 20,
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
    this.settings,
    this.defaultAppearance,
    this.fake = false,
    this.field,
    this.backdrop = const LiquidGlassBackdrop.read(),
    super.key,
  }) : frame = null;

  /// Creates a [LiquidGlassLayer] whose settings, field and default
  /// appearance follow [frame].
  ///
  /// Every notification writes the new frame straight into the layer's
  /// render object, real or fake, so the glass the layer draws shows it in
  /// the same frame, its shapes that set no appearance of their own
  /// included; nothing rebuilds. Widgets below that read the settings or
  /// the default appearance from the tree ([settingsOf], a nested
  /// [LiquidGlass] that opens its own layer, the fade of a [LiquidGlass]'s
  /// child that sets no appearance) see those of the frame the layer last
  /// built with.
  const LiquidGlassLayer.live({
    required ValueListenable<LiquidGlassLayerFrame> this.frame,
    required this.child,
    this.fake = false,
    this.backdrop = const LiquidGlassBackdrop.read(),
    super.key,
  }) : settings = null,
       field = null,
       defaultAppearance = null;

  /// The subtree in which you should include at least one [LiquidGlass] widget.
  ///
  /// The [LiquidGlassLayer] will automatically register all [LiquidGlass]
  /// widgets in the subtree as shapes and render them.
  final Widget child;

  /// The settings for the liquid glass effect for all shapes in this layer.
  ///
  /// When omitted, the iOS 27 regular settings follow the ambient platform
  /// brightness, as [defaultAppearance] does, so glass given neither is the
  /// light regular glass in light mode and the dark one in dark mode
  /// ([LiquidGlassMaterial.ios27Regular]). A layer made with
  /// [LiquidGlassLayer.live] takes them from its frame.
  final LiquidGlassSettings? settings;

  /// Appearance inherited by shapes that do not provide an override.
  ///
  /// When omitted, the fitted iOS 27 regular appearance follows the ambient
  /// platform brightness. A layer made with [LiquidGlassLayer.live] takes it
  /// from its frame.
  final LiquidGlassAppearance? defaultAppearance;

  /// Whether to replace all liquid glass effects in this layer with
  /// [FakeGlass] effects.
  ///
  /// The layer also draws fake glass while full glass loads and where it
  /// does not draw, for example on Skia ([liquidGlassSupport]).
  final bool fake;

  /// The distance field of the one body this layer's shapes form, when the
  /// caller has fused them already.
  ///
  /// The layer then shades the body the field describes instead of its
  /// shapes' outlines and blend groups, and casts its shadows by the
  /// field's edge. See [LiquidGlassField].
  final LiquidGlassField? field;

  /// Where the glass takes what it shows through: read behind the layer by
  /// default, or a backdrop the caller knows. See [LiquidGlassBackdrop].
  ///
  /// A layer that draws fake glass reads what is behind it whatever this
  /// says.
  final LiquidGlassBackdrop backdrop;

  /// The frames of a layer made with [LiquidGlassLayer.live], or null for
  /// one that uses [settings], [field] and [defaultAppearance].
  final ValueListenable<LiquidGlassLayerFrame>? frame;

  /// The settings of the nearest [LiquidGlassLayer] above [context], which
  /// its glass draws with, or null where there is no layer; [context]
  /// rebuilds when they change.
  static LiquidGlassSettings? maybeSettingsOf(BuildContext context) =>
      LiquidGlassRenderScope.maybeSettingsOf(context);

  /// The settings of the nearest [LiquidGlassLayer] above [context], which
  /// its glass draws with; [context] rebuilds when they change.
  ///
  /// There must be such a layer: [maybeSettingsOf] gives null where there is
  /// none.
  static LiquidGlassSettings settingsOf(BuildContext context) =>
      maybeSettingsOf(context) ?? (throw noLiquidGlassLayerError(context));

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty('settings', settings, defaultValue: null))
      ..add(
        DiagnosticsProperty(
          'defaultAppearance',
          defaultAppearance,
          defaultValue: null,
        ),
      )
      ..add(FlagProperty('fake', value: fake, ifTrue: 'fake'))
      ..add(DiagnosticsProperty('field', field, defaultValue: null))
      ..add(
        DiagnosticsProperty(
          'backdrop',
          backdrop,
          defaultValue: const LiquidGlassBackdrop.read(),
        ),
      )
      ..add(DiagnosticsProperty('frame', frame, defaultValue: null));
  }

  @override
  State<LiquidGlassLayer> createState() => _LiquidGlassLayerState();
}

class _LiquidGlassLayerState extends State<LiquidGlassLayer> {
  final _link = GeometryRenderLink();

  static bool _loggedFallback = false;

  // Fake and real subtrees never coexist, so one key keeps the user's subtree
  // alive across a renderer swap without ever being mounted twice.
  final _childKey = GlobalKey(debugLabel: 'LiquidGlassLayer.child');

  // The layer's render object, real or fake, which a live frame is written
  // into.
  final _layerKey = GlobalKey(debugLabel: 'LiquidGlassLayer.layer');

  LiquidGlassSettings get _settings =>
      widget.frame?.value.settings ?? widget.settings ?? _platform.settings;

  LiquidGlassField? get _field => widget.frame?.value.field ?? widget.field;

  // iOS 27 regular glass in the platform brightness: what a layer given no
  // settings or no default appearance draws with.
  late LiquidGlassMaterial _platform;
  Brightness? _platformBrightness;

  LiquidGlassAppearance get _defaultAppearance =>
      widget.frame?.value.defaultAppearance ??
      widget.defaultAppearance ??
      _platform.appearance;

  void _onLiveFrame() {
    if (_layerKey.currentContext?.findRenderObject()
        case final LiquidGlassRenderObject layer) {
      layer
        ..settings = _settings
        ..field = _field
        ..defaultAppearance = _defaultAppearance;
    }
  }

  void _onFullGlass() {
    if (!widget.fake) setState(() {});
  }

  void _logFallback(String reason) {
    if (!kDebugMode || _loggedFallback) return;
    _loggedFallback = true;
    debugPrint(
      'liquid_glass_renderer: LiquidGlassLayer is using FakeGlass. '
      '$reason Enable Impeller and Flutter GPU for the full glass effect.',
    );
  }

  @override
  void initState() {
    super.initState();
    FullGlass.state.addListener(_onFullGlass);
    widget.frame?.addListener(_onLiveFrame);
  }

  @override
  void didUpdateWidget(covariant LiquidGlassLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.frame, widget.frame)) {
      oldWidget.frame?.removeListener(_onLiveFrame);
      widget.frame?.addListener(_onLiveFrame);
    }
  }

  @override
  void dispose() {
    FullGlass.state.removeListener(_onFullGlass);
    widget.frame?.removeListener(_onLiveFrame);
    _link.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    if (brightness != _platformBrightness) {
      _platformBrightness = brightness;
      _platform = LiquidGlassMaterial.ios27Regular(brightness: brightness);
    }
    final defaultAppearance = _defaultAppearance;
    final glass = widget.fake ? null : FullGlass.state.value;
    switch (glass) {
      case FullGlassPending():
        FullGlass.loadAfterFrame();
      case FullGlassUnavailable(:final reason):
        _logFallback(reason);
      case FullGlassReady() || null:
        break;
    }
    if (glass is! FullGlassReady) {
      return _buildFakeLayer(
        defaultAppearance: defaultAppearance,
        settings: _settings,
        child: KeyedSubtree(key: _childKey, child: widget.child),
      );
    }

    return RepaintBoundary(
      child: LiquidGlassRenderScope(
        settings: _settings,
        defaultAppearance: defaultAppearance,
        child: GlassHost.layer(
          link: _link,
          child: _RawShapes(
            key: _layerKey,
            glass: glass,
            field: _field,
            solidBackdrop: switch (widget.backdrop) {
              LiquidGlassSolidBackdrop(:final color) => color,
              LiquidGlassReadBackdrop() => null,
            },
            settings: _settings,
            defaultAppearance: defaultAppearance,
            link: _link,
            child: KeyedSubtree(key: _childKey, child: widget.child),
          ),
        ),
      ),
    );
  }

  Widget _buildFakeLayer({
    required LiquidGlassAppearance defaultAppearance,
    required LiquidGlassSettings settings,
    required Widget child,
  }) {
    // A boundary of its own, as the real layer has: ancestor motion moves
    // the retained surfaces without recording them again.
    Widget buildFakeSurfaceLayer(Map<String, FragmentShader> shaders) {
      return RepaintBoundary(
        child: LiquidGlassRenderScope(
          settings: settings,
          defaultAppearance: defaultAppearance,
          fake: true,
          child: GlassHost.layer(
            link: _link,
            child: ConsolidatedFakeGlassLayer(
              key: _layerKey,
              link: _link,
              settings: settings,
              defaultAppearance: defaultAppearance,
              surfaceShader: shaders[ShaderKeys.fakeGlassSurface],
              fieldShader: shaders[ShaderKeys.fakeGlassFieldSurface],
              field: _field,
              child: child,
            ),
          ),
        ),
      );
    }

    return MultiShaderBuilder(
      assetKeys: ShaderKeys.fakeLayerAssets,
      (_, shaders, _) => buildFakeSurfaceLayer(shaders),
      child: buildFakeSurfaceLayer(const {}),
    );
  }
}

class _RawShapes extends SingleChildRenderObjectWidget {
  const _RawShapes({
    required this.glass,
    required this.field,
    required this.solidBackdrop,
    required this.settings,
    required this.defaultAppearance,
    required Widget super.child,
    required this.link,
    super.key,
  });

  final FullGlassReady glass;
  final LiquidGlassField? field;

  final Color? solidBackdrop;
  final LiquidGlassSettings settings;
  final LiquidGlassAppearance defaultAppearance;
  final GeometryRenderLink link;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderLiquidGlassLayer(
        glass: glass,
        devicePixelRatio: glassDevicePixelRatioOf(context),
        settings: settings,
        defaultAppearance: defaultAppearance,
        link: link,
      )
      ..field = field
      ..solidBackdrop = solidBackdrop;
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLiquidGlassLayer renderObject,
  ) {
    renderObject
      ..link = link
      ..devicePixelRatio = glassDevicePixelRatioOf(context)
      ..settings = settings
      ..defaultAppearance = defaultAppearance
      ..field = field
      ..solidBackdrop = solidBackdrop;
  }
}

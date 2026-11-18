import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:meta/meta.dart';

/// The error of glass built at [context] with no `LiquidGlassLayer` above it.
@internal
FlutterError noLiquidGlassLayerError(BuildContext context) =>
    FlutterError.fromParts([
      ErrorSummary('No LiquidGlassLayer found.'),
      ErrorDescription(
        '${context.widget.runtimeType} draws its glass on the nearest '
        'LiquidGlassLayer above it, and there is none.',
      ),
      ErrorHint('Wrap the glass in a LiquidGlassLayer.'),
      context.describeElement('The context used was'),
    ]);

enum _ScopeAspect { settings, defaultAppearance }

/// What a `LiquidGlassLayer` gives the widgets under it.
@internal
class LiquidGlassRenderScope extends InheritedModel<Object> {
  /// Creates a new [LiquidGlassRenderScope].
  const LiquidGlassRenderScope({
    required this.settings,
    required this.defaultAppearance,
    required super.child,
    this.fake = false,
    super.key,
  });

  final LiquidGlassSettings settings;

  final LiquidGlassAppearance defaultAppearance;

  /// Whether the layer is consolidated fake glass: shapes register with it
  /// without backdrop filters of their own, and it paints each fake surface.
  final bool fake;

  /// The scope of the nearest layer above [context], which there must be;
  /// [context] rebuilds when any of it changes.
  static LiquidGlassRenderScope of(BuildContext context) =>
      maybeOf(context) ?? (throw noLiquidGlassLayerError(context));

  /// The scope of the nearest layer above [context], or null where there is
  /// none; [context] rebuilds when any of it changes.
  static LiquidGlassRenderScope? maybeOf(BuildContext context) =>
      InheritedModel.inheritFrom<LiquidGlassRenderScope>(context);

  /// The settings of the nearest layer above [context], or null where
  /// there is none; [context] rebuilds when they change.
  static LiquidGlassSettings? maybeSettingsOf(BuildContext context) =>
      InheritedModel.inheritFrom<LiquidGlassRenderScope>(
        context,
        aspect: _ScopeAspect.settings,
      )?.settings;

  /// The default appearance of the nearest layer above [context], which
  /// there must be; [context] rebuilds when it changes.
  static LiquidGlassAppearance defaultAppearanceOf(BuildContext context) =>
      (InheritedModel.inheritFrom<LiquidGlassRenderScope>(
                context,
                aspect: _ScopeAspect.defaultAppearance,
              ) ??
              (throw noLiquidGlassLayerError(context)))
          .defaultAppearance;

  @override
  bool updateShouldNotify(LiquidGlassRenderScope oldWidget) =>
      oldWidget.settings != settings ||
      oldWidget.defaultAppearance != defaultAppearance ||
      oldWidget.fake != fake;

  @override
  bool updateShouldNotifyDependent(
    LiquidGlassRenderScope oldWidget,
    Set<Object> dependencies,
  ) =>
      dependencies.contains(_ScopeAspect.settings) &&
          oldWidget.settings != settings ||
      dependencies.contains(_ScopeAspect.defaultAppearance) &&
          oldWidget.defaultAppearance != defaultAppearance;
}

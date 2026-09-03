import 'package:flutter/cupertino.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/state.dart';

/// A glass surface that joins the nearest ambient [LiquidGlassLayer]. This
/// keeps ordinary sibling controls on one backdrop capture; callers opt into
/// a small nested layer only for lenses that sit on top of another surface.
///
/// Material: by default the surface follows the live playground settings
/// (which default to the fitted iOS 27 toolbar material). Clear lenses that
/// sit on top of other glass pass their own [settings] instead.
class GlassSurface extends HookWidget {
  const GlassSurface({
    required this.child,
    required this.shape,
    super.key,
    this.settings,
    this.appearance,
    this.shadows = const [],
    this.useOwnLayer = false,
  });

  final LiquidShape shape;
  final Widget child;

  /// Overrides the live settings. Used by clear lenses (thumbs, selection
  /// indicators, loupes) that must not inherit the frosted toolbar material.
  final LiquidGlassSettings? settings;
  final LiquidGlassAppearance? appearance;
  final List<BoxShadow> shadows;

  /// Creates a small nested layer for lenses that sit on top of another glass
  /// surface. Ordinary sibling controls should stay in the ambient layer.
  final bool useOwnLayer;

  @override
  Widget build(BuildContext context) {
    final liveSettings = useValueListenable(settingsNotifier);
    final liveAppearance = useValueListenable(appearanceNotifier);
    final fake = useValueListenable(fakeNotifier);

    final common = (
      settings: settings ?? liveSettings,
      appearance: appearance ?? liveAppearance,
      fake: fake,
      useBackdropGroup: false,
      shadows: shadows,
      shape: shape,
      child: child,
    );
    return useOwnLayer
        ? LiquidGlass.withOwnLayer(
            settings: common.settings,
            appearance: common.appearance,
            fake: common.fake,
            useBackdropGroup: common.useBackdropGroup,
            shadows: common.shadows,
            shape: common.shape,
            child: common.child,
          )
        : LiquidGlass.auto(
            settings: common.settings,
            appearance: common.appearance,
            fake: common.fake,
            useBackdropGroup: common.useBackdropGroup,
            shadows: common.shadows,
            shape: common.shape,
            child: common.child,
          );
  }
}

/// Clear-lens material for elements that sit on top of other glass: no frost,
/// no tint, only edge optics. Based on the fitted loupe probe settings.
const clearLensSettings = LiquidGlassSettings(
  thickness: 8,
  edgeRefraction: 16,
  frost: 0,
  highlight: 0.7,
  highlightWidth: 2,
  contourStrength: 0.2,
  contourWidth: 1,
);

const clearLensAppearance = LiquidGlassAppearance(tint: Color(0x3dffffff));

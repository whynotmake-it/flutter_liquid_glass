/// Liquid glass as widgets: `LiquidGlass` puts a shape of glass in the tree,
/// `LiquidGlassLayer` lets glass share one layer and its settings,
/// `LiquidGlassBlendGroup` makes nearby glass blend into one surface, and
/// `FakeGlass` gives a cheaper look that reads no backdrop.
/// `LiquidGlassVisibility` fades glass in and out, and `GlassPlanOverlay`
/// shows each frame's plan over the app.
///
/// For app developers who want glass.
///
/// Glass is cheap out of the box: an app optimizes nothing by hand to keep
/// its frames.
library;

export 'src/widgets/fake_glass.dart' show FakeGlass;
export 'src/widgets/glass_plan_overlay.dart' show GlassPlanOverlay;
export 'src/widgets/liquid_glass.dart' show LiquidGlass;
export 'src/widgets/liquid_glass_blend_group.dart' show LiquidGlassBlendGroup;
export 'src/widgets/liquid_glass_layer.dart' show LiquidGlassLayer;
export 'src/widgets/liquid_glass_visibility.dart' show LiquidGlassVisibility;

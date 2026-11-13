/// Interactive effects on glass: `GlassGlow` lights the glass it sits in
/// under a finger, and `LiquidStretch` stretches glass as it is dragged
/// (`RawLiquidStretch` takes the drag from its caller).
///
/// For those who build their own interactive glass without a widget library
/// on top.
///
/// An effect reacts to touches and drives the glass it lies in; it draws no
/// glass of its own. Nothing below depends on it, so glass without an effect
/// pays nothing for one.
library;

export 'src/effects/glass_drag_builder.dart' show GestureMode;
export 'src/effects/glass_glow.dart' show GlassGlow;
export 'src/effects/stretch.dart' show LiquidStretch, RawLiquidStretch;

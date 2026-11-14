/// Liquid glass for Flutter: what an app needs to put glass on screen, in
/// one import.
///
/// `painting` describes glass as values (shapes, settings, appearance) and
/// `widgets` puts it in the tree (`LiquidGlass`, `LiquidGlassLayer`,
/// `LiquidGlassBlendGroup`, `FakeGlass`).
///
/// The other libraries are for those who build on the renderer and are
/// imported by name: `composer` for the plan of a frame and its report,
/// `rendering` for the render objects and layers that carry the plan out,
/// `effects` for glass that reacts to touch (`GlassGlow`, `LiquidStretch`).
library;

export 'painting.dart' hide RectScaling;
export 'widgets.dart';

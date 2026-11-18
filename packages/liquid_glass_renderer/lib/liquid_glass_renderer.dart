/// Liquid glass for Flutter: what an app needs to put glass on screen, in
/// one import.
///
/// `painting` describes glass as values (shapes, settings, appearance) and
/// `widgets` puts it in the tree (`LiquidGlass`, `LiquidGlassLayer`,
/// `LiquidGlassBlendGroup`, `FakeGlass`).
///
/// `rendering` is for those who build on the renderer and is imported by
/// name: the layers that carry a frame's plan out, and the report of what
/// a frame's glass took.
library;

export 'painting.dart';
export 'widgets.dart';

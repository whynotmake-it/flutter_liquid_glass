/// iOS 27 Liquid Glass controls, bars and presentations for Flutter, with
/// UIKit's measured motion.
///
/// An app puts a `GlassScope` at its root: the theme, and liquid glass
/// where the device draws it well. A `GlassRendererScope` picks another
/// renderer: `LiquidGlassRenderer`, `FakeGlassRenderer`,
/// `FlatGlassRenderer`, `AdaptiveGlassRenderer` or the app's own. Without
/// a scope, controls draw flat. Exports the six libraries of the package,
/// kinesis, the motion the controls run on, and the glass renderer's
/// shapes and fields, which the controls take.
library;

export 'package:kinesis/kinesis.dart';
export 'package:liquid_glass_renderer/painting.dart'
    show
        LiquidGlassField,
        LiquidOval,
        LiquidRoundedRectangle,
        LiquidRoundedSuperellipse,
        LiquidShape;

export 'foundation.dart';
export 'liquid.dart';
export 'motions.dart';
export 'raw.dart';
export 'surfaces.dart';
export 'widgets.dart';

/// The code that carries out a frame's plan: the render objects and layers
/// of glass, the reads and copies of the screen, the shaders and their
/// variants, the geometry computed on the GPU, the frost and the clips.
///
/// What a widget library builds on: `LiquidGlassBackdropFilterLayer` is a
/// backdrop filter drawn from a copy the frame's plan makes,
/// `LiquidGlassUnderlay` teaches glass how layer types of other packages
/// draw, so it can copy past them, and `LiquidGlassBentContent` paints what
/// lies over a glass shape bent at its rim, as a lifted iOS lens shows what
/// it selects. `glassReadsCopies` turns the copies of the screen on or off.
///
/// What a frame's glass took: `GlassFrameReport` tells which copies of the
/// screen the frame's plan read, at what cost, for budgets held in tests
/// and for tuning; `GlassFrameReports` hands every frame's report to its
/// listeners and `debugPrintGlassFrameReports` prints them.
/// `debugPaintLiquidGlassGeometry` paints the geometry in place of the
/// glass.
///
/// It decides nothing the plan decides; it draws what the plan says. The
/// backdrop glass shows is never a frame late.
library;

export 'src/rendering/backdrop_filter_layer.dart'
    show LiquidGlassBackdropFilterHost, LiquidGlassBackdropFilterLayer;
export 'src/rendering/bent_content.dart' show LiquidGlassBentContent;
export 'src/rendering/debug.dart' show debugPaintLiquidGlassGeometry;
export 'src/rendering/frame_report.dart'
    show
        GlassFrameReport,
        GlassFrameReportCallback,
        GlassFrameReports,
        GlassReadReport,
        GlassReadSource,
        debugPrintGlassFrameReports;
export 'src/rendering/liquid_glass_underlay.dart'
    show LiquidGlassLayerEffects, LiquidGlassUnderlay;
export 'src/rendering/read.dart' show glassReadsCopies;

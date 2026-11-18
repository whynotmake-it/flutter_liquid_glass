/// The liquid glass renderer and the renderers built on it, the root widget
/// `GlassScope` that sets them up for an app, and the only library of the
/// package that draws with the glass package `liquid_glass_renderer`. The
/// others take only its values (shapes, fields, looks), which draw nothing.
///
/// For the app developer who wants the package's glass with one widget at
/// the root: `GlassScope` holds the theme, animated when it changes, the
/// renderer, liquid glass where the device draws it well, and the frame
/// rate fed by the app's scrolls. Without a scope, controls draw flat.
///
/// For the app that picks a renderer or lets its user pick one:
/// `LiquidGlassRenderer` (real glass), `FakeGlassRenderer` (blurred and
/// lit, no refraction) and `AdaptiveGlassRenderer` (real glass where the
/// device draws it well, fake glass elsewhere and on the web), set in a
/// `GlassRendererScope`, and `precacheGlass`, which readies the glass
/// before the first frame. It also publishes what the liquid renderer
/// reports of a frame for debugging (`GlassFrameReport`,
/// `GlassFrameReports`, `LiquidGlassReportOverlay`,
/// `debugPrintGlassFrameReports`).
///
/// It declares no control, and no renderer here knows a control by name:
/// what a body needs arrives as data in its description. Nothing but the
/// umbrella imports it, so no other library picks a glass renderer for
/// the app.
library;

export 'src/liquid/adaptive.dart' show AdaptiveGlassRenderer, precacheGlass;
export 'src/liquid/frame_report.dart'
    show
        GlassFrameReport,
        GlassFrameReportCallback,
        GlassFrameReports,
        GlassReadReport,
        GlassReadSource,
        LiquidGlassReportOverlay,
        debugPrintGlassFrameReports;
export 'src/liquid/liquid.dart' show FakeGlassRenderer, LiquidGlassRenderer;
export 'src/liquid/scope.dart' show GlassScope;

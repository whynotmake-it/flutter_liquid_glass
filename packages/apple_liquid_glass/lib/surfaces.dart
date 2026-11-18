/// A way to say "here is a body of glass": `GlassSurface`, described by
/// the glass values of `foundation` (material, shape, outline, frame), its
/// clip (`GlassClip`), fusion group (`GlassGroup`, `GlassMerge`) and the
/// solid backdrop that stands in for glass (`GlassSolidBackdrop`); and the
/// renderer seam, `GlassRenderer`, with the details it builds every
/// surface, group and scroll edge from.
///
/// For the app developer who makes glass bodies of their own, such as a
/// card or a panel, that follow the renderer the app picks, and for the
/// author of a renderer, who subclasses `GlassRenderer` and sets it in a
/// `GlassRendererScope` like the package's own. Without a scope above,
/// surfaces draw flat.
///
/// It promises that a surface describes what it needs and the renderer
/// decides how it is drawn: every renderer, the package's and an app's,
/// builds from the same details. It names no liquid renderer: this library
/// holds the seam and `FlatGlassRenderer`, which draws with no glass
/// shader and no backdrop read; the glass renderers are in `liquid`.
///
/// It declares no control.
library;

export 'src/surfaces/clip.dart' show GlassClip;
export 'src/surfaces/flat.dart' show FlatGlassRenderer;
export 'src/surfaces/follow.dart' show ListenableFollower;
export 'src/surfaces/group.dart' show GlassGroup, GlassMerge;
export 'src/surfaces/highlight.dart'
    show
        GlassHighlight,
        GlassHighlightLook,
        GlassHighlightPaint,
        GlassHighlights;
export 'src/surfaces/renderer.dart'
    show
        GlassGroupDetails,
        GlassRenderer,
        GlassScrollEdgeDetails,
        GlassSurfaceDetails;
export 'src/surfaces/renderer_scope.dart' show GlassRendererScope;
export 'src/surfaces/scroll_edge.dart' show RenderScrollEdge, ScrollEdgeBand;
export 'src/surfaces/solid_backdrop.dart' show GlassSolidBackdrop;
export 'src/surfaces/surface.dart' show GlassSurface;

/// The code that carries out a frame's plan: the render objects and layers
/// of glass, the reads and copies of the screen, the shaders and their
/// variants, the geometry computed on the GPU, the frost and the clips.
///
/// `LiquidGlassLayerFrame` is what a live layer shades with,
/// `LiquidGlassBackdropFilterLayer` a backdrop filter drawn from a copy the
/// frame's plan makes, and `LiquidGlassUnderlay` teaches glass how layer
/// types of other packages draw, so it can copy past them.
/// `debugPaintLiquidGlassGeometry` paints the geometry in place of the glass.
/// `RenderLiquidGlassContent` holds the child of one glass shape and the
/// light a touch raises under it.
/// `LiquidGlassBentContent` paints what lies over a glass shape bent at its
/// rim, as a lifted iOS lens shows what it selects.
///
/// For those who write their own glass render object at a low level.
///
/// It decides nothing the plan decides; it draws what the plan says. The
/// backdrop glass shows is never a frame late.
library;

export 'src/rendering/backdrop_filter_layer.dart'
    show LiquidGlassBackdropFilterHost, LiquidGlassBackdropFilterLayer;
export 'src/rendering/bent_content.dart'
    show LiquidGlassBentContent, LiquidGlassContentBend;
export 'src/rendering/consolidated_fake_glass_layer.dart'
    show RenderConsolidatedFakeGlassLayer;
export 'src/rendering/copy_haze.dart' show debugGlassHaze;
export 'src/rendering/debug.dart' show debugPaintLiquidGlassGeometry;
export 'src/rendering/fake_glass.dart' show FakeGlassRole, RenderFakeGlass;
export 'src/rendering/flutter_gpu_geometry_renderer.dart'
    show FlutterGpuGeometryRenderer;
export 'src/rendering/geometry_render_link.dart' show GeometryRenderLink;
export 'src/rendering/glass_composer.dart'
    show debugGlassPolicy, debugGlassPrices;
export 'src/rendering/glass_content.dart' show RenderLiquidGlassContent;
export 'src/rendering/glass_shadow.dart' show RenderGlassShadow;
export 'src/rendering/liquid_glass.dart'
    show RenderLiquidGlass, RenderLiveGlassFrame;
export 'src/rendering/liquid_glass_blend_group.dart'
    show GlassGroupLink, RenderLiquidGlassBlendGroup;
export 'src/rendering/liquid_glass_layer.dart' show RenderLiquidGlassLayer;
export 'src/rendering/liquid_glass_render_object.dart'
    show LiquidGlassRenderObject;
export 'src/rendering/liquid_glass_underlay.dart'
    show LiquidGlassLayerEffects, LiquidGlassUnderlay;
export 'src/rendering/live_paint_size.dart' show LivePaintSize;
export 'src/rendering/paint_fake_glass_surface.dart'
    show fakeGlassSurfaceOutset;
export 'src/rendering/precache.dart' show precacheLiquidGlass;
export 'src/rendering/read.dart' show debugGlassCopies;
export 'src/rendering/render_liquid_glass_geometry.dart'
    show LiquidGlassShapeRenderObject, RenderLiquidGlassGeometry, ShapeGeometry;
export 'src/rendering/shader_programs.dart' show GlassShaderPrograms;
export 'src/rendering/shaders.dart' show ShaderKeys;
export 'src/rendering/shape_set.dart' show debugGlassLean;

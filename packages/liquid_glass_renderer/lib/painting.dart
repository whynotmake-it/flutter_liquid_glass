/// Liquid glass described as values: its shape, its look and how it meets
/// what lies behind it.
///
/// `LiquidShape` and its kinds give the outline, `LiquidGlassSettings` the
/// optics (refraction, frost, highlight, contour), `LiquidGlassHaze` the
/// wide blur mixed into what the glass shows, `LiquidGlassAppearance` and
/// `LiquidGlassColorModel` the material, `LiquidGlassBackdrop` where the
/// glass takes what it shows through, `LiquidGlassField` the outline of a
/// body its owner computed itself, `LiquidGlassGlow` the light a finger
/// raises on a shape, `LiquidGlassShadow` the shadow iOS casts under glass
/// of a size, and `LiquidGlassShapeFrame` one frame of a live shape.
/// `LiquidGlassSupport` says whether the device draws full glass, and on
/// what GPU.
///
/// For anyone who describes glass without drawing it, such as a widget
/// library that maps its own shapes and materials onto glass.
///
/// Its types are immutable values. It creates no render object, no layer and
/// no shader: the libraries above it draw what these values describe.
library;

export 'src/painting/liquid_glass_appearance.dart' show LiquidGlassAppearance;
export 'src/painting/liquid_glass_backdrop.dart' show LiquidGlassBackdrop;
export 'src/painting/liquid_glass_color_model.dart'
    show
        GlassColorBleed,
        GlassColorCurve,
        GlassColorParameters,
        GlassToneRamp,
        LiquidGlassColorModel;
export 'src/painting/liquid_glass_field.dart' show LiquidGlassField;
export 'src/painting/liquid_glass_glow.dart' show LiquidGlassGlow;
export 'src/painting/liquid_glass_haze.dart' show LiquidGlassHaze;
export 'src/painting/liquid_glass_layer_frame.dart' show LiquidGlassLayerFrame;
export 'src/painting/liquid_glass_settings.dart'
    show GlassRim, LiquidGlassSettings;
export 'src/painting/liquid_glass_shadow.dart' show LiquidGlassShadow;
export 'src/painting/liquid_glass_shape_frame.dart' show LiquidGlassShapeFrame;
export 'src/painting/liquid_glass_support.dart'
    show LiquidGlassDeviceClass, LiquidGlassSupport;
export 'src/painting/liquid_shape.dart'
    show
        LiquidOval,
        LiquidRoundedRectangle,
        LiquidRoundedSuperellipse,
        LiquidShape;
export 'src/painting/rect_scaling.dart' show RectScaling;

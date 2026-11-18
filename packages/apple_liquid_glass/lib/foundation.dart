/// The iOS design language as values, for anyone who wants iOS's colours
/// and type in their own widgets.
///
/// Colours that resolve against the brightness, contrast and interface
/// level around them (`GlassDynamicColor`, the palette `GlassColors`); text
/// roles and their typography (`GlassTextRole`, `GlassDefaultTextStyle`);
/// the traits of the environment (`GlassTraits`); the values that describe
/// a glass body, which pick no renderer: its material (`Glass`,
/// `GlassRole`), free outline (`GlassOutline`), touch glow
/// (`GlassTouchGlow`) and one frame of it (`GlassFrame`), whose shape is
/// one of the glass renderer's values (`LiquidShape`); and
/// the theme (`GlassTheme`, `GlassThemeData`, `GlassColorScheme`): a
/// container of colours, type and a list of component styles
/// (`GlassStyle`), found by type, that names no component and does
/// nothing by itself; and the words the widgets say to assistive
/// technology (`GlassLocalizations`), English unless the app loads a
/// translation through Flutter's `Localizations`.
///
/// It promises that the traits report what Flutter reports (contrast, bold
/// text) and Reduce Motion through kinesis's one channel,
/// `MotionTraitsOverride`. Flutter reports no Reduce Transparency, so an
/// app gives it, and the other traits Flutter does not know, with
/// `GlassTraitsOverride`.
///
/// It declares no control and no presentation.
library;

export 'src/foundation/body.dart' show GlassBody, glassCornerRadii;
export 'src/foundation/colors.dart' show GlassColors, GlassDynamicColor;
export 'src/foundation/direction.dart' show GlassDirection;
export 'src/foundation/frame.dart' show GlassFrame;
export 'src/foundation/glass.dart'
    show Glass, GlassLens, GlassLensContent, GlassRole;
export 'src/foundation/label_text.dart' show glassLabelTextOf;
export 'src/foundation/localizations.dart'
    show DefaultGlassLocalizations, GlassLocalizations;
export 'src/foundation/media.dart' show GlassMediaQueryData;
export 'src/foundation/outline.dart' show GlassOutline;
export 'src/foundation/target.dart'
    show
        glassButtonReach,
        glassMinimumTarget,
        glassMinimumTargetExtent,
        glassTargetReach;
export 'src/foundation/theme.dart'
    show GlassColorScheme, GlassStyle, GlassTheme, GlassThemeData;
export 'src/foundation/touch_glow.dart' show GlassTouchGlow;
export 'src/foundation/traits.dart'
    show GlassInterfaceLevel, GlassTraits, GlassTraitsOverride;
export 'src/foundation/typography.dart'
    show GlassDefaultTextStyle, GlassTextRole, GlassTextScale;

import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/playground/presets.dart';
import 'package:liquid_glass_renderer_example/playground/scenes/draggable_glass.dart';
import 'package:motor/motor.dart';

/// Whether controls below adapt to the backdrop, and which glass they use.
class AdaptiveScope extends InheritedWidget {
  const AdaptiveScope({
    required this.source,
    required this.style,
    required super.child,
    super.key,
  });

  /// The backdrop to sample, or `null` to follow the app brightness.
  final LiquidGlassBrightnessSource? source;
  final GlassStyle style;

  static AdaptiveScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AdaptiveScope>()!;

  @override
  bool updateShouldNotify(AdaptiveScope oldWidget) =>
      source != oldWidget.source || style != oldWidget.style;
}

/// Controls that switch between light and dark glass together.
///
/// The group estimates the brightness of the backdrop behind its whole
/// bounds, so neighboring controls never disagree.
class AdaptiveGroup extends StatelessWidget {
  const AdaptiveGroup({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final source = AdaptiveScope.of(context).source;
    if (source == null) return child;
    return LiquidGlassAdaptiveBrightness(source: source, child: child);
  }
}

/// Size of the glyphs on glass controls: CupertinoIcons at this size match
/// the SF Symbols in iOS 27 toolbar buttons (`chevron.left` 18.3 pt tall,
/// `square.and.arrow.up` 24 pt, `ellipsis` dots 7.8 pt apart).
const controlGlyphSize = 26.0;

/// Glass for one control, with glyphs that stay legible on it and the touch
/// glow beneath them.
///
/// Inside an adaptive [AdaptiveGroup] the glass and glyphs follow the group's
/// estimate; otherwise the shape inherits the layer's appearance.
class ControlGlass extends StatelessWidget {
  const ControlGlass({required this.shape, required this.child, super.key});

  final LiquidShape shape;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = AdaptiveScope.of(context);
    final brightness = scope.source == null
        ? null
        : LiquidGlassAdaptiveBrightness.maybeOf(context)?.brightness;
    if (brightness == null) return _glass(context, null);
    return CupertinoTheme(
      data: CupertinoTheme.of(context).copyWith(brightness: brightness),
      child: Builder(
        builder: (context) =>
            _glass(context, scope.style.appearance(brightness)),
      ),
    );
  }

  Widget _glass(BuildContext context, LiquidGlassAppearance? appearance) {
    return LiquidStretch(
      child: LiquidGlass(
        shape: shape,
        appearance: appearance,
        shadows: glassShadows,
        child: GlowContent(
          child: MotionBuilder(
            motion: const CupertinoMotion.smooth(),
            converter: const ColorRgbMotionConverter(),
            value: CupertinoColors.label.resolveFrom(context),
            builder: (context, glyph, child) => IconTheme(
              data: IconThemeData(color: glyph, size: controlGlyphSize),
              child: DefaultTextStyle(
                style: TextStyle(
                  color: glyph,
                  fontSize: 15,
                  letterSpacing: -0.2,
                ),
                child: child!,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

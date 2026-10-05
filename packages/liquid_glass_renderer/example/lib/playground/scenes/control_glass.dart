import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/playground/scenes/draggable_glass.dart';
import 'package:motor/motor.dart';

/// Size of the glyphs on glass controls: CupertinoIcons at this size match
/// the SF Symbols in iOS 27 toolbar buttons (`chevron.left` 18.3 pt tall,
/// `square.and.arrow.up` 24 pt, `ellipsis` dots 7.8 pt apart).
const controlGlyphSize = 26.0;

/// Glass for one control, with glyphs that stay legible on it and the touch
/// glow beneath them. The shape inherits the layer's appearance.
class ControlGlass extends StatelessWidget {
  const ControlGlass({required this.shape, required this.child, super.key});

  final LiquidShape shape;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LiquidStretch(
      child: LiquidGlass(
        shape: shape,
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

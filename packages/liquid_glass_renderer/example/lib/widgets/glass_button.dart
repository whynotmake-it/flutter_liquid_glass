import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/widgets/glass_surface.dart';
import 'package:motor/motor.dart';

/// A liquid glass button, ported from the reference widget's behavior: the
/// face glows under touch ([GlassGlow]) and the pill squashes and stretches
/// through an interactive spring while pressed ([LiquidStretch]).
class GlassButton extends StatefulWidget {
  const GlassButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.tint,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    super.key,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData? icon;

  /// When set, the button face carries this tint instead of neutral glass.
  final Color? tint;
  final EdgeInsetsGeometry padding;

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tint = widget.tint;
    return LiquidStretch(
      interactionScale: .97,
      stretch: .25,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        child: SingleMotionBuilder(
          motion: const Motion.interactiveSpring(snapToEnd: true),
          value: _pressed ? 0.96 : 1.0,
          builder: (context, scale, child) => Transform.scale(
            scale: scale,
            child: child,
          ),
          child: GlassSurface(
            shape: const LiquidRoundedSuperellipse(borderRadius: 9000),
            appearance: LiquidGlassAppearance(
              tint: tint ?? const Color(0x1fffffff),
            ),
            child: GlassGlow(
              child: Padding(
                padding: widget.padding,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 6,
                  children: [
                    if (widget.icon != null)
                      Icon(
                        widget.icon,
                        size: 17,
                        color: CupertinoColors.label.resolveFrom(context),
                      ),
                    Text(
                      widget.label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.label.resolveFrom(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A circular icon button carved from the same glass material that glows and
/// stretches under touch.
class GlassIconButton extends StatefulWidget {
  const GlassIconButton({
    required this.icon,
    required this.onPressed,
    this.size = 44,
    this.tint,
    super.key,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final double size;
  final Color? tint;

  @override
  State<GlassIconButton> createState() => _GlassIconButtonState();
}

class _GlassIconButtonState extends State<GlassIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onPressed,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      child: SingleMotionBuilder(
        motion: const Motion.interactiveSpring(snapToEnd: true),
        value: _pressed ? 0.92 : 1.0,
        builder: (context, scale, child) => Transform.scale(
          scale: scale,
          child: child,
        ),
        child: GlassSurface(
          shape: const LiquidOval(),
          appearance: LiquidGlassAppearance(
            tint: widget.tint ?? const Color(0x1fffffff),
          ),
          child: GlassGlow(
            child: SizedBox.square(
              dimension: widget.size,
              child: Icon(
                widget.icon,
                size: 20,
                color: CupertinoColors.label.resolveFrom(context),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

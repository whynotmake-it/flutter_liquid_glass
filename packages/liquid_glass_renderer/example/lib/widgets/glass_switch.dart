import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/widgets/glass_surface.dart';
import 'package:motor/motor.dart';

/// A liquid glass switch, ported from the reference widget's behavior:
///
/// - the track is a glass pill whose tint fills towards system green while
///   the switch turns on,
/// - the knob is a clear lens stacked on the track that travels with a snappy
///   spring, squashes through [LiquidStretch] while held, and glows through
///   [GlassGlow] on touch.
class GlassSwitch extends StatefulWidget {
  const GlassSwitch({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  State<GlassSwitch> createState() => _GlassSwitchState();
}

class _GlassSwitchState extends State<GlassSwitch> {
  static const _trackWidth = 51.0;
  static const _trackHeight = 31.0;

  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final target = widget.value ? 1.0 : 0.0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onChanged(!widget.value),
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      child: SingleMotionBuilder(
        motion: const Motion.snappySpring(snapToEnd: true),
        value: target,
        child: _GlassSwitchKnob(pressed: _pressed),
        builder: (context, progress, knob) => GlassSurface(
          shape: const LiquidRoundedSuperellipse(borderRadius: 9000),
          appearance: LiquidGlassAppearance(
            tint: Color.lerp(
              const Color(0x14ffffff),
              const Color(0x5930d158),
              progress,
            )!,
          ),
          child: Container(
            width: _trackWidth,
            height: _trackHeight,
            padding: const EdgeInsets.all(2),
            alignment: Alignment(progress * 2 - 1, 0),
            child: knob,
          ),
        ),
      ),
    );
  }
}

/// The switch's small glass lens knob.
class _GlassSwitchKnob extends StatelessWidget {
  const _GlassSwitchKnob({required this.pressed});

  final bool pressed;

  @override
  Widget build(BuildContext context) {
    return LiquidStretch(
      interactionScale: pressed ? 1.1 : 1,
      stretch: .4,
      child: const GlassSurface(
        settings: clearLensSettings,
        appearance: LiquidGlassAppearance(tint: Color(0xf2ffffff)),
        useOwnLayer: true,
        shape: LiquidOval(),
        child: SizedBox.square(dimension: 27),
      ),
    );
  }
}

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/playground/presets.dart';
import 'package:liquid_glass_renderer_example/playground/scenes/adaptive_controls.dart';
import 'package:liquid_glass_renderer_example/playground/scenes/simple_bottom_bar.dart';

/// Everyday controls: navigation buttons at the top and a bottom bar. Every
/// shape samples the one shared backdrop capture.
///
/// With [adaptive] on, the top controls and the bottom bar each switch
/// between light and dark glass as a group, following the backdrop behind
/// them.
class ControlsScene extends StatelessWidget {
  const ControlsScene({
    required this.adaptive,
    required this.style,
    required this.source,
    super.key,
  });

  final ValueListenable<bool> adaptive;
  final ValueListenable<GlassStyle> style;
  final LiquidGlassBrightnessSource source;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([adaptive, style]),
      builder: (context, controls) => AdaptiveScope(
        source: adaptive.value ? source : null,
        style: style.value,
        child: controls!,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              children: [
                AdaptiveGroup(
                  child: Row(
                    children: [
                      CircleButton(icon: CupertinoIcons.chevron_left),
                      Spacer(),
                      _ButtonCapsule(
                        icons: [
                          CupertinoIcons.square_arrow_up,
                          CupertinoIcons.ellipsis,
                        ],
                      ),
                    ],
                  ),
                ),
                Spacer(),
                // Integration point for the bottom bar.
                SimpleBottomBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CircleButton extends StatelessWidget {
  const CircleButton({required this.icon, this.size = 48, super.key});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ControlGlass(
      shape: const LiquidOval(),
      child: SizedBox.square(dimension: size, child: Icon(icon)),
    );
  }
}

class _ButtonCapsule extends StatelessWidget {
  const _ButtonCapsule({required this.icons});

  final List<IconData> icons;

  @override
  Widget build(BuildContext context) {
    return ControlGlass(
      shape: const LiquidRoundedSuperellipse(borderRadius: 24),
      child: SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final icon in icons) SizedBox(width: 42, child: Icon(icon)),
            ],
          ),
        ),
      ),
    );
  }
}

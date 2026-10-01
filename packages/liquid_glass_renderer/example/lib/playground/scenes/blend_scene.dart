import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/playground/scenes/draggable_glass.dart';

/// Shapes in one [LiquidGlassBlendGroup] that merge as they are dragged
/// together.
class BlendScene extends StatelessWidget {
  const BlendScene({required this.blend, super.key});

  final ValueListenable<double> blend;

  @override
  Widget build(BuildContext context) {
    final glyph = CupertinoColors.label.resolveFrom(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final center = constraints.biggest.center(Offset.zero);
        return ValueListenableBuilder(
          valueListenable: blend,
          builder: (context, blend, shapes) =>
              LiquidGlassBlendGroup(blend: blend, child: shapes!),
          child: IconTheme(
            data: IconThemeData(color: glyph, size: 24),
            child: Stack(
              children: [
                DraggableGlass(
                  center: center,
                  offset: const Offset(-18, 44),
                  size: const Size(196, 64),
                  shape: const LiquidRoundedSuperellipse(borderRadius: 32),
                  grouped: true,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Icon(CupertinoIcons.bold),
                      Icon(CupertinoIcons.italic),
                      Icon(CupertinoIcons.underline),
                    ],
                  ),
                ),
                DraggableGlass(
                  center: center,
                  offset: const Offset(118, 44),
                  size: const Size(64, 64),
                  shape: const LiquidOval(),
                  grouped: true,
                  child: const Icon(CupertinoIcons.textformat),
                ),
                DraggableGlass(
                  center: center,
                  offset: const Offset(-28, -54),
                  size: const Size(88, 88),
                  shape: const LiquidOval(),
                  grouped: true,
                  child: const Icon(CupertinoIcons.plus, size: 32),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

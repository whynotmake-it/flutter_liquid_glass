import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/playground/scenes/draggable_glass.dart';

/// Large, empty shapes for judging refraction, magnification and blur over
/// the backdrop.
class LensScene extends StatelessWidget {
  const LensScene({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final center = constraints.biggest.center(Offset.zero);
        return Stack(
          children: [
            DraggableGlass(
              center: center,
              offset: const Offset(-56, -40),
              size: const Size.square(156),
              shape: const LiquidOval(),
            ),
            DraggableGlass(
              center: center,
              offset: const Offset(44, 96),
              size: const Size(232, 80),
              shape: const LiquidRoundedSuperellipse(borderRadius: 40),
            ),
          ],
        );
      },
    );
  }
}

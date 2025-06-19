import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/shared.dart';

void main() {
  runApp(const ClockApp());
}

class ClockApp extends StatelessWidget {
  const ClockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const ImagePageView(
      child: LiquidGlassLayer(
        child: Center(
          child: Row(
            children: [
              LiquidGlass(
                shape: LiquidRoundedSuperellipse(
                  borderRadius: Radius.circular(100),
                ),
                child: const SizedBox.square(dimension: 100),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

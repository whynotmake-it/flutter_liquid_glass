import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/shared.dart';

void main() {
  runApp(MaterialApp(home: ShapesExample()));
}

final settingsNotifier = ValueNotifier(LiquidGlassSettings());

class ShapesExample extends HookWidget {
  const ShapesExample({super.key});

  @override
  Widget build(BuildContext context) {
    final lightAngleController = useRotatingAnimationController();
    final lightAngle = useAnimation(lightAngleController);

    final settings = useValueListenable(
      settingsNotifier,
    ).copyWith(lightAngle: lightAngle);

    return GestureDetector(
      onTap: () {
        SettingsSheet(
          settingsNotifier: settingsNotifier,
          lightAngleAnimation: lightAngleController,
        ).show(context);
      },
      child: ImagePageView(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: LiquidGlassLayer(
              settings: settings,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 64,
                children: [
                  LiquidGlass.inLayer(
                    child: SizedBox.square(dimension: 200),
                    shape: LiquidRoundedSuperellipse(
                      borderRadius: Radius.circular(64),
                    ),
                  ),
                  LiquidGlass.inLayer(
                    child: SizedBox.square(dimension: 200),
                    shape: LiquidOval(),
                  ),
                  LiquidGlass.inLayer(
                    child: SizedBox.square(dimension: 200),
                    shape: LiquidRoundedRectangle(
                      borderRadius: Radius.circular(40),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_liquid_glass/flutter_liquid_glass.dart';
import 'package:rivership/rivership.dart';
import 'package:springster/springster.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends HookWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    final debug = useState(false);
    final thicknessVisible = useState(true);

    final flip = useKeyedState(false, keys: []);

    final spring = Spring.bouncy.copyWith(durationSeconds: .8, bounce: 0.4);

    const offset1 = Offset(200, 200);
    const offset2 = Offset(200, 450);

    const size1 = Size(150, 100);
    const size2 = Size(150, 100);

    final thickness = useSingleMotion(
      value: thicknessVisible.value ? 48 : 0,
      motion: SpringMotion(spring),
    );

    final lightAngleController = useAnimationController(
      duration: const Duration(seconds: 5),
      lowerBound: 0,
      upperBound: 2 * pi,
    )..repeat();

    final lightAngle = useAnimation(lightAngleController);

    final offset = useOffsetMotion(
      value: flip.value ? offset1 : offset2,
      motion: SpringMotion(spring),
    );

    final size = useSizeMotion(
      value: flip.value ? size1 : size2,
      motion: SpringMotion(spring.copyWithDamping(durationSeconds: 1.2)),
    );

    final cornerRadius = useSingleMotion(
      value: flip.value ? 50 : 20,
      motion: SpringMotion(spring.copyWithDamping(durationSeconds: 1.2)),
    );

    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            flip.value = !flip.value;
          },

          child: const Icon(Icons.flip),
        ),
        body: GestureDetector(
          onTap: () {
            thicknessVisible.value = !thicknessVisible.value;
          },
          onLongPress: () {
            debug.value = !debug.value;
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.asset('assets/iphone.png', fit: BoxFit.cover),
              ),
              RawSquircles(
                debugRenderRefractionMap: debug.value,
                squircle1: Squircle(
                  center: offset1,
                  size: size1,
                  cornerRadius: cornerRadius,
                ),
                squircle2: Squircle(
                  center: offset,
                  size: size,
                  cornerRadius: cornerRadius,
                ),
                settings: LiquidGlassSettings(
                  thickness: thickness,
                  chromaticAberration: 0.0,
                  blend: 50,
                  lightAngle: lightAngle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

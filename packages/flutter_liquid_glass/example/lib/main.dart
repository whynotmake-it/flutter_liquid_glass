import 'dart:math';
import 'dart:ui';

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

    final spring = Spring.bouncy.copyWith(durationSeconds: .8, bounce: 0.3);

    const offset1 = Offset(100, 150);
    const offset2 = Offset(200, 550);

    const size1 = Size(100, 100);
    const size2 = Size(300, 100);

    final thickness = useSingleMotion(
      value: thicknessVisible.value ? 20 : 0,
      motion: SpringMotion(spring),
    );

    final blur = thickness * .1;

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
      value: flip.value ? size1 * 0.5 : size2,
      motion: SpringMotion(spring.copyWithDamping(durationSeconds: 1.2)),
    );

    final cornerRadius = useSingleMotion(
      value: flip.value ? 15 : 20,
      motion: SpringMotion(spring.copyWithDamping(durationSeconds: 1.2)),
    );

    final baseColor = Theme.of(
      context,
    ).colorScheme.surface.withValues(alpha: 0.1);

    final color = useTweenAnimation(
      ColorTween(begin: baseColor, end: baseColor),
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
              Positioned.fill(child: Container(color: Colors.transparent)),
              if (!debug.value)
                Positioned.fill(
                  child: Image.asset('assets/iphone.png', fit: BoxFit.cover),
                ),

              Positioned(
                top: offset1.dy - size1.height / 2,
                left: offset1.dx - size1.width / 2,

                child: ClipRSuperellipse(
                  borderRadius: BorderRadiusGeometry.circular(cornerRadius),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                    child: SizedBox(width: size1.width, height: size1.height),
                  ),
                ),
              ),
              Positioned(
                top: offset.dy - size.height / 2,
                left: offset.dx - size.width / 2,

                child: ClipRSuperellipse(
                  borderRadius: BorderRadiusGeometry.circular(cornerRadius),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                    child: SizedBox(
                      width: size.width,
                      height: size.height,

                      child: AnimatedSizeSwitcher(
                        duration: const Duration(milliseconds: 500),
                        transitionBuilder: (child, animation) =>
                            ScaleTransition(
                              scale: animation.drive(
                                Tween<double>(begin: 2, end: 1),
                              ),
                              child: FadeTransition(
                                opacity: CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeInOut,
                                ),
                                child: child,
                              ),
                            ),
                        child: flip.value || thicknessVisible.value == false
                            ? SizedBox.shrink()
                            : Center(child: FlutterLogo(size: 50)),
                      ),
                    ),
                  ),
                ),
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
                  glassColor: color!.withValues(
                    alpha: color.a * (thickness / 20).clamp(0, 1),
                  ),
                  chromaticAberration: 0.01,
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

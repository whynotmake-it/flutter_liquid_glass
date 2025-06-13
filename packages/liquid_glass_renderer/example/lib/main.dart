import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:rivership/rivership.dart';
import 'package:smooth_sheets/smooth_sheets.dart';

void main() {
  runApp(const MainApp());
}

final thicknessNotifier = ValueNotifier<double>(30);

final blurFactorNotifier = ValueNotifier<double>(0.01);

final cornerRadiusNotifier = ValueNotifier<double>(50);

final glassColorNotifier = ValueNotifier<Color>(Colors.transparent);

final lightIntensityNotifier = ValueNotifier<double>(0.4);

final blendNotifier = ValueNotifier<double>(50);

class MainApp extends HookWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    final thicknessVisible = useState(true);

    final blend = useValueListenable(blendNotifier);

    final spring = Spring.bouncy.copyWith(durationSeconds: .8, bounce: 0.3);

    final thickness = useSingleMotion(
      value: thicknessVisible.value ? thicknessNotifier.value : 0,
      motion: SpringMotion(spring),
    );

    final blur = thickness * blurFactorNotifier.value;

    final lightAngleController = useAnimationController(
      duration: const Duration(seconds: 5),
      lowerBound: 0,
      upperBound: 2 * pi,
    )..repeat();

    final lightAngle = useAnimation(lightAngleController);

    final cornerRadius = useSingleMotion(
      value: cornerRadiusNotifier.value,
      motion: SpringMotion(spring.copyWithDamping(durationSeconds: 1.2)),
    );

    final color = useTweenAnimation(
      ColorTween(
        begin: glassColorNotifier.value,
        end: glassColorNotifier.value,
      ),
    )!;

    return MaterialApp(
      home: Builder(
        builder: (context) {
          return Scaffold(
            extendBodyBehindAppBar: true,
            floatingActionButton: FloatingActionButton(
              onPressed: () {
                Navigator.push(
                  context,
                  ModalSheetRoute(
                    barrierColor: Colors.black26,
                    swipeDismissible: true,
                    builder: (context) {
                      return SettingsSheet();
                    },
                  ),
                );
              },

              child: const Icon(Icons.color_lens),
            ),

            body: GestureDetector(
              onTap: () {
                thicknessVisible.value = !thicknessVisible.value;
              },

              child: Stack(
                children: [
                  Positioned.fill(child: Container(color: Colors.transparent)),
                  Positioned.fill(
                    child: Image.asset(
                      'assets/wallpaper.webp',
                      fit: BoxFit.cover,
                    ),
                  ),

                  Positioned.fill(
                    child: LiquidGlassLayer(
                      settings: LiquidGlassSettings(
                        thickness: thickness,
                        lightAngle: lightAngle,
                        glassColor: color.withValues(
                          alpha: color.a * thickness / 20,
                        ),
                        lightIntensity: lightIntensityNotifier.value,
                        blend: blend,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        spacing: 40,
                        children: [
                          Align(
                            alignment: Alignment.topCenter,
                            child: DragDismissable(
                              threshold: double.maxFinite,
                              velocityThreshold: double.maxFinite,
                              spring: Spring.bouncy,
                              child: LiquidGlass.inLayer(
                                blur: blur,
                                shape: LiquidGlassSquircle(
                                  borderRadius: Radius.circular(cornerRadius),
                                ),
                                child: Container(
                                  color: Colors.transparent,
                                  child: SizedBox.square(dimension: 100),
                                ),
                              ),
                            ),
                          ),
                          Center(
                            child: DragDismissable(
                              threshold: double.maxFinite,
                              velocityThreshold: double.maxFinite,
                              spring: Spring.bouncy,
                              child: LiquidGlass.inLayer(
                                glassContainsChild: false,
                                blur: blur,
                                shape: LiquidGlassSquircle(
                                  borderRadius: Radius.circular(cornerRadius),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(24.0),
                                  child: FlutterLogo(size: 200),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class SettingsSheet extends StatelessWidget {
  const SettingsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Sheet(
      scrollConfiguration: const SheetScrollConfiguration(),
      initialOffset: SheetOffset(0.5),
      snapGrid: SheetSnapGrid(snaps: [SheetOffset(0.5), SheetOffset(1)]),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SafeArea(
          child: LiquidGlass(
            blur: 20,
            glassContainsChild: false,
            settings: LiquidGlassSettings(
              thickness: 40,
              lightIntensity: .1,
              ambientStrength: 0,
              glassColor: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: 0.4),
            ),
            shape: LiquidGlassSquircle(borderRadius: Radius.circular(24)),
            child: DefaultTextStyle(
              style: Theme.of(context).textTheme.bodyLarge!,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Settings',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 16),
                    Text('Thickness:'),
                    CupertinoSlider(
                      value: thicknessNotifier.value,
                      onChanged: (value) {
                        thicknessNotifier.value = value;
                      },
                      min: 0,
                      max: 100,
                    ),
                    Text('Corner Radius:'),
                    CupertinoSlider(
                      value: cornerRadiusNotifier.value,
                      onChanged: (value) {
                        cornerRadiusNotifier.value = value;
                      },
                      min: 1,
                      max: 100,
                    ),
                    Text('Light Intensity:'),
                    CupertinoSlider(
                      value: lightIntensityNotifier.value,
                      onChanged: (value) {
                        lightIntensityNotifier.value = value;
                      },
                      min: 0,
                      max: 1,
                    ),

                    Text('Blur:'),
                    CupertinoSlider(
                      value: blurFactorNotifier.value,
                      onChanged: (value) {
                        blurFactorNotifier.value = value;
                      },
                    ),
                    Text('Liquid Factor™:'),
                    CupertinoSlider(
                      value: blendNotifier.value,
                      onChanged: (value) {
                        blendNotifier.value = value;
                      },
                      min: 0,
                      max: 100,
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

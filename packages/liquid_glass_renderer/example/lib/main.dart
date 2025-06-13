import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:rivership/rivership.dart';
import 'package:smooth_sheets/smooth_sheets.dart';

void main() {
  runApp(const MainApp());
}

final thicknessNotifier = ValueNotifier<double>(20);

final blurFactorNotifier = ValueNotifier<double>(.02);

final cornerRadiusNotifier = ValueNotifier<double>(100);

final glassColorNotifier = ValueNotifier<Color>(
  const Color.fromARGB(0, 255, 255, 255),
);

final lightIntensityNotifier = ValueNotifier<double>(5);

final blendNotifier = ValueNotifier<double>(50);

final chromaticAberrationNotifier = ValueNotifier<double>(1);

class MainApp extends HookWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    final thicknessVisible = useState(true);

    final blend = useValueListenable(blendNotifier);

    final chromaticAberration = useValueListenable(chromaticAberrationNotifier);

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

    final colorScheme = ColorScheme.fromSeed(
      brightness: Brightness.dark,
      seedColor: Color(0xFF287390),
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.from(
        colorScheme: colorScheme,
        textTheme: GoogleFonts.lexendDecaTextTheme().apply(
          displayColor: colorScheme.onSurface,
          bodyColor: colorScheme.onSurface,
        ),
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return GestureDetector(
              onTap: () {
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
              child: Background(
                child: LiquidGlassLayer(
                  settings: LiquidGlassSettings(
                    thickness: thickness,
                    lightAngle: lightAngle,
                    glassColor: color.withValues(
                      alpha: color.a * thickness / 20,
                    ),
                    lightIntensity: lightIntensityNotifier.value,
                    ambientStrength: 0.8,
                    outlineIntensity: 2,
                    blend: blend,
                    chromaticAberration: chromaticAberration,
                  ),
                  child: Stack(
                    alignment: Alignment.bottomLeft,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 90, left: 140),
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
                              child: SizedBox.square(dimension: 160),
                            ),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.topRight,
                        child: DragDismissable(
                          threshold: double.maxFinite,
                          velocityThreshold: double.maxFinite,
                          spring: Spring.bouncy,
                          child: LiquidGlass.inLayer(
                            glassContainsChild: false,
                            blur: blur,
                            shape: LiquidGlassRoundedRectangle(
                              borderRadius: Radius.circular(0),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(64.0),
                              child: FlutterLogo(size: 200),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class Background extends HookWidget {
  const Background({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final showHint = useDelayed(
      delay: Duration(seconds: 1),
      before: false,
      after: true,
    );
    useEffect(() {
      if (showHint) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "Drag Glass or tap anywhere!",
                style: GoogleFonts.lexendDecaTextTheme().bodyLarge!.copyWith(
                  color: Theme.of(context).colorScheme.onInverseSurface,
                ),
              ),
            ),
          );
        });
      }
      return null;
    }, [showHint]);

    return SizedBox.expand(
      child: Container(
        color: Theme.of(context).colorScheme.surface,
        child: Container(
          margin: const EdgeInsets.only(bottom: 64, left: 64),
          decoration: ShapeDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(80)),
            ),
          ),
          child: Container(
            margin: const EdgeInsets.only(bottom: 16, left: 16),
            decoration: ShapeDecoration(
              image: DecorationImage(
                image: AssetImage('assets/wallpaper.webp'),
                fit: BoxFit.cover,
              ),
              shape: RoundedSuperellipseBorder(
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(64),
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(64.0),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Text(
                      'Liquid\nGlass\nRenderer',
                      style: GoogleFonts.lexendDecaTextTheme().headlineLarge
                          ?.copyWith(
                            fontSize: 120,
                            height: 1,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF287390),
                          ),
                    ),
                  ),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SettingsSheet extends StatelessWidget {
  const SettingsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Sheet(
      dragConfiguration: SheetDragConfiguration(),
      scrollConfiguration: const SheetScrollConfiguration(),
      initialOffset: SheetOffset(1),
      snapGrid: SheetSnapGrid(snaps: [SheetOffset(0.5), SheetOffset(1)]),
      child: Padding(
        padding: const EdgeInsets.all(32.0),
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
                      max: 5,
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
                    Text('Chromatic Aberration:'),
                    CupertinoSlider(
                      value: chromaticAberrationNotifier.value,
                      onChanged: (value) {
                        chromaticAberrationNotifier.value = value;
                      },
                      min: 0,
                      max: 10,
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

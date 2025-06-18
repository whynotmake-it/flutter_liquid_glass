import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:rivership/rivership.dart';
import 'package:smooth_sheets/smooth_sheets.dart';

void main() {
  runApp(const MainApp());
}

final thicknessNotifier = ValueNotifier<double>(20);

final blurNotifier = ValueNotifier<double>(0.0);

final cornerRadiusNotifier = ValueNotifier<double>(100);

final glassColorNotifier = ValueNotifier<Color>(
  const Color.fromARGB(0, 255, 255, 255),
);

final lightIntensityNotifier = ValueNotifier<double>(1);

final blendNotifier = ValueNotifier<double>(50);

final chromaticAberrationNotifier = ValueNotifier<double>(1);

final ambientStrengthNotifier = ValueNotifier<double>(0.5);

final refractiveIndexNotifier = ValueNotifier<double>(1.51);

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

    final blur = useValueListenable(blurNotifier);

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

    final settings = LiquidGlassSettings(
      thickness: thickness,
      lightAngle: lightAngle,
      glassColor: color.withValues(alpha: color.a * thickness / 20),
      lightIntensity: lightIntensityNotifier.value,
      ambientStrength: ambientStrengthNotifier.value,
      blend: blend,
      chromaticAberration: chromaticAberration,
      refractiveIndex: refractiveIndexNotifier.value,
    );
    return CallbackShortcuts(
      bindings: {
        LogicalKeySet(LogicalKeyboardKey.space): () {
          thicknessVisible.value = !thicknessVisible.value;
        },
      },
      child: MaterialApp(
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
                      viewportPadding: const EdgeInsets.all(100),
                      builder: (context) {
                        return SettingsSheet();
                      },
                    ),
                  );
                },
                child: Background(
                  lightAngle: lightAngle,
                  child: LiquidGlassLayer(
                    settings: settings,
                    child: Stack(
                      alignment: Alignment.bottomLeft,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: 105,
                            left: 130,
                          ),
                          child: DragDismissable(
                            threshold: double.maxFinite,
                            velocityThreshold: double.maxFinite,
                            spring: Spring.bouncy,
                            child: LiquidGlass.inLayer(
                              blur: blur,
                              shape: LiquidRoundedSuperellipse(
                                borderRadius: Radius.circular(cornerRadius),
                              ),
                              child: Container(
                                color: Colors.transparent,
                                child: SizedBox(height: 120, width: 180),
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
                              shape: LiquidRoundedSuperellipse(
                                borderRadius: Radius.circular(cornerRadius),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(64.0),
                                child: Glassify(
                                  blur: thickness / 5,
                                  settings: settings,
                                  child: FlutterLogo(size: 200),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.topLeft,
                          child: DragDismissable(
                            threshold: double.maxFinite,
                            velocityThreshold: double.maxFinite,
                            spring: Spring.bouncy,
                            child: LiquidGlass.inLayer(
                              glassContainsChild: false,
                              blur: blur,
                              shape: LiquidOval(),
                              child: Container(
                                width: 100,
                                height: 80,
                                color: Colors.transparent,
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
      ),
    );
  }
}

class Background extends HookWidget {
  const Background({super.key, required this.child, required this.lightAngle});

  final Widget child;

  final double lightAngle;

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
                    child: Glassify(
                      blur: 3,
                      settings: LiquidGlassSettings(
                        thickness: 8,
                        lightAngle: lightAngle,
                        lightIntensity: 1,
                        ambientStrength: 0.3,
                        chromaticAberration: 0,
                        glassColor: Theme.of(
                          context,
                        ).colorScheme.inversePrimary.withValues(alpha: .8),
                        refractiveIndex: 1.3,
                      ),
                      child: Text(
                        'Liquid\nGlass\nRenderer',
                        style: GoogleFonts.lexendDecaTextTheme().headlineLarge
                            ?.copyWith(
                              fontSize: 120,
                              height: 1,
                              fontWeight: FontWeight.w900,
                            ),
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

class SettingsSheet extends HookWidget {
  const SettingsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final thickness = useValueListenable(thicknessNotifier);
    final cornerRadius = useValueListenable(cornerRadiusNotifier);
    final lightIntensity = useValueListenable(lightIntensityNotifier);
    final blurFactor = useValueListenable(blurNotifier);
    final blend = useValueListenable(blendNotifier);
    final chromaticAberration = useValueListenable(chromaticAberrationNotifier);
    final ambientStrength = useValueListenable(ambientStrengthNotifier);
    final refractionStrength = useValueListenable(refractiveIndexNotifier);

    return Sheet(
      dragConfiguration: SheetDragConfiguration(),
      scrollConfiguration: const SheetScrollConfiguration(),
      initialOffset: SheetOffset(1),
      shrinkChildToAvoidDynamicOverlap: true,
      shrinkChildToAvoidStaticOverlap: true,
      snapGrid: SheetSnapGrid(snaps: [SheetOffset(0.5), SheetOffset(1)]),
      child: SafeArea(
        child: LiquidGlass(
          blur: 20,
          glassContainsChild: false,
          settings: LiquidGlassSettings(
            thickness: 30,
            lightIntensity: .2,
            lightAngle: .2 * pi,

            ambientStrength: 2,
            chromaticAberration: 2,
            glassColor: Theme.of(
              context,
            ).colorScheme.surface.withValues(alpha: 0.4),
          ),
          shape: LiquidRoundedSuperellipse(borderRadius: Radius.circular(24)),
          child: DefaultTextStyle(
            style: Theme.of(context).textTheme.bodyLarge!,
            child: Align(
              alignment: Alignment.topCenter,
              child: SingleChildScrollView(
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Thickness:'),
                          Text(thickness.toStringAsFixed(2)),
                        ],
                      ),
                      CupertinoSlider(
                        value: thickness,
                        onChanged: (value) {
                          thicknessNotifier.value = value;
                        },
                        min: 0,
                        max: 160,
                      ),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Corner Radius:'),
                          Text(cornerRadius.toStringAsFixed(2)),
                        ],
                      ),
                      CupertinoSlider(
                        value: cornerRadius,
                        onChanged: (value) {
                          cornerRadiusNotifier.value = value;
                        },
                        min: 0,
                        max: 100,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Light Intensity:'),
                          Text(lightIntensity.toStringAsFixed(2)),
                        ],
                      ),
                      CupertinoSlider(
                        value: lightIntensity,
                        onChanged: (value) {
                          lightIntensityNotifier.value = value;
                        },
                        min: 0,
                        max: 5,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Ambient Strength:'),
                          Text(ambientStrength.toStringAsFixed(2)),
                        ],
                      ),
                      CupertinoSlider(
                        value: ambientStrength,
                        onChanged: (value) {
                          ambientStrengthNotifier.value = value;
                        },
                        min: 0,
                        max: 5,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Blur:'),
                          Text(blurFactor.toStringAsFixed(2)),
                        ],
                      ),
                      CupertinoSlider(
                        value: blurFactor,
                        onChanged: (value) {
                          blurNotifier.value = value;
                        },
                        min: 0,
                        max: 40,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Liquid Factor™:'),
                          Text(blend.toStringAsFixed(2)),
                        ],
                      ),
                      CupertinoSlider(
                        value: blend,
                        onChanged: (value) {
                          blendNotifier.value = value;
                        },
                        min: 0,
                        max: 100,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Chromatic Aberration:'),
                          Text(chromaticAberration.toStringAsFixed(2)),
                        ],
                      ),
                      CupertinoSlider(
                        value: chromaticAberration,
                        onChanged: (value) {
                          chromaticAberrationNotifier.value = value;
                        },
                        min: 0,
                        max: 10,
                      ),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Refractive Index:'),
                          Text(refractionStrength.toStringAsFixed(2)),
                        ],
                      ),
                      CupertinoSlider(
                        value: refractionStrength,
                        onChanged: (value) {
                          refractiveIndexNotifier.value = value;
                        },
                        min: 1,
                        max: 3,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/shared.dart';
import 'package:rivership/rivership.dart';

void main() {
  runApp(const MainApp());
}

final settingsNotifier = ValueNotifier<LiquidGlassSettings>(
  LiquidGlassSettings(
    thickness: 20,
    lightAngle: 0.5 * pi,
    blend: 50,
    chromaticAberration: 1,
  ),
);

final cornerRadiusNotifier = ValueNotifier<double>(100);

final glassColorNotifier = ValueNotifier<Color>(
  const Color.fromARGB(0, 255, 255, 255),
);

class MainApp extends HookWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    final thicknessVisible = useState(true);
    final flutterLogoVisible = useState(false);

    final userSettings = useValueListenable(settingsNotifier);

    final motion = CupertinoMotion.bouncy();

    final flutterLogoThickness = useSingleMotion(
      value: flutterLogoVisible.value ? userSettings.thickness : 0,
      motion: motion,
    );

    final lightAngleController = useRotatingAnimationController();
    final lightAngle = useAnimation(lightAngleController);

    final cornerRadius = useSingleMotion(
      value: cornerRadiusNotifier.value,
      motion: CupertinoMotion.smooth(),
    );

    final colorScheme = ColorScheme.fromSeed(
      brightness: Brightness.dark,
      seedColor: Color(0xFF287390),
    );

    final settings = userSettings.copyWith(lightAngle: lightAngle);
    return CallbackShortcuts(
      bindings: {
        LogicalKeySet(LogicalKeyboardKey.space): () {
          thicknessVisible.value = !thicknessVisible.value;
        },
        LogicalKeySet(LogicalKeyboardKey.keyF): () {
          flutterLogoVisible.value = !flutterLogoVisible.value;
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
                onTap: () => SettingsSheet(
                  settingsNotifier: settingsNotifier,
                  lightAngleAnimation: lightAngleController,
                ).show(context),
                child: Background(
                  lightAngle: lightAngle,
                  textVisible: thicknessVisible.value,
                  child: LiquidGlassLayer(
                    settings: settings,
                    child: Stack(
                      alignment: Alignment.bottomLeft,
                      children: [
                        Align(
                          alignment: Alignment.center,
                          child: Glassify(
                            settings: settings.copyWith(
                              blur: flutterLogoThickness / 5,
                              thickness: flutterLogoThickness,
                            ),
                            child: FlutterLogo(size: 200),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: 105,
                            left: 130,
                          ),
                          child: DragDismissable(
                            threshold: double.maxFinite,
                            velocityThreshold: double.maxFinite,
                            motion: CupertinoMotion.bouncy(),
                            child: LiquidGlass.inLayer(
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
                            motion: CupertinoMotion.bouncy(),
                            child: LiquidGlass.inLayer(
                              glassContainsChild: false,
                              shape: LiquidRoundedSuperellipse(
                                borderRadius: Radius.circular(cornerRadius),
                              ),
                              child: Glassify(
                                settings: settings.copyWith(
                                  blur: 5,
                                  thickness: 10,
                                  glassColor: Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: .2),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(64.0),
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
                            motion: CupertinoMotion.bouncy(),
                            child: LiquidGlass.inLayer(
                              glassContainsChild: false,
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
  const Background({
    super.key,
    required this.child,
    required this.lightAngle,
    required this.textVisible,
  });

  final Widget child;

  final double lightAngle;

  final bool textVisible;

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

    final textThickness = useSingleMotion(
      value: textVisible ? 8 : 0,
      motion: CupertinoMotion.bouncy(),
    );

    return SizedBox.expand(
      child: Stack(
        children: [
          ImagePageView(
            child: Padding(
              padding: const EdgeInsets.all(64.0),
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Glassify(
                      settings: LiquidGlassSettings(
                        blur: 3,
                        thickness: textThickness,
                        lightAngle: lightAngle,
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
                ],
              ),
            ),
          ),
          Padding(padding: EdgeInsetsGeometry.all(64), child: child),
        ],
      ),
    );
  }
}

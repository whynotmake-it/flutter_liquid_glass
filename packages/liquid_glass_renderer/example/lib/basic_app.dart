import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/shared.dart';

void main() {
  runApp(CupertinoApp(home: BasicApp()));
}

final settingsNotifier = ValueNotifier(
  LiquidGlassSettings(
    thickness: 20,
    blur: 10,
    refractiveIndex: 1.2,
    glassColor: Colors.white.withValues(alpha: 0.1),
  ),
);

class BasicApp extends HookWidget {
  const BasicApp({super.key});

  @override
  Widget build(BuildContext context) {
    useStream(Stream.periodic(const Duration(seconds: 1)));
    final lightAngleController = useRotatingAnimationController();
    final lightAngle = useAnimation(lightAngleController);

    final settings = useValueListenable(
      settingsNotifier,
    ).copyWith(lightAngle: lightAngle);

    final time = DateTime.now();

    final format = DateFormat('HH:mm');

    return GestureDetector(
      onTap: () {
        SettingsSheet(
          settingsNotifier: settingsNotifier,
          lightAngleAnimation: lightAngleController,
        ).show(context);
      },
      child: ImagePageView(
        child: Center(
          child: FittedBox(
            fit: BoxFit.contain,
            child: LiquidGlass(
              settings: settings.copyWith(glassColor: Colors.transparent),
              shape: LiquidRoundedRectangle(borderRadius: Radius.circular(64)),
              child: Padding(
                padding: const EdgeInsets.all(64.0),
                child: Glassify(
                  child: Text(
                    format.format(time),
                    style: GoogleFonts.lexendGigaTextTheme().headlineLarge!
                        .copyWith(fontSize: 200),
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

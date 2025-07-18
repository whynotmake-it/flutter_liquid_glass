import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/shared.dart';
import 'package:rivership/rivership.dart';

void main() {
  runApp(MaterialApp(home: GridExample()));
}

final settingsNotifier = ValueNotifier(LiquidGlassSettings());

class GridExample extends HookWidget {
  const GridExample({super.key});

  @override
  Widget build(BuildContext context) {
    useStream(Stream.periodic(const Duration(seconds: 1)));
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
        child: LiquidGlassLayer(
          settings: settings.copyWith(glassColor: Colors.transparent),

          child: Padding(
            padding: const EdgeInsets.all(64),
            child: GridView.extent(
              maxCrossAxisExtent: 100,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              children: [
                for (final i in List.generate(64, (index) => index))
                  GridItem(index: i),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class GridItem extends HookWidget {
  GridItem({super.key, required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final clicked = useState(false);
    final motion = clicked.value
        ? CupertinoMotion.interactive()
        : CupertinoMotion.bouncy();
    final scale = useSingleMotion(
      value: clicked.value ? 1.5 : 1,
      motion: motion,
    );

    return GestureDetector(
      onTapDown: (details) {
        clicked.value = true;
      },
      onTapUp: (details) {
        clicked.value = false;
      },
      onTapCancel: () {
        clicked.value = false;
      },
      child: Transform.scale(
        scale: scale,
        child: LiquidGlass.inLayer(
          child: SizedBox.expand(
            child: Container(
              color: Colors.transparent,
              child: DefaultTextStyle(
                style: GoogleFonts.lexendDecaTextTheme().bodyLarge!,
                child: Center(child: Text("${index + 1}")),
              ),
            ),
          ),
          shape: LiquidRoundedRectangle(borderRadius: Radius.circular(16)),
        ),
      ),
    );
  }
}

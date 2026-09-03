import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_renderer_example/state.dart';
import 'package:liquid_glass_renderer_example/widgets/backgrounds.dart';
import 'package:liquid_glass_renderer_example/widgets/loupe.dart';

/// The loupe playground: a clear glass lens trails the finger through a
/// spring. The magnifier paints a higher-resolution backdrop first and the
/// glass layer applies its edge optics on top of the magnified pixels.
class LensPage extends StatelessWidget {
  const LensPage({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: const Color(0x00000000),
      child: Stack(
        children: [
          const Positioned.fill(child: Grid()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Text(
                'Lens',
                style: CupertinoTheme.of(context)
                    .textTheme
                    .navLargeTitleTextStyle
                    .copyWith(
                      color: const Color(0xff1c1917),
                      shadows: _headerShadows,
                    ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 120, 20, 120),
              child: DraggableLoupe(
                settings: settingsNotifier.value,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _headerShadows = [
  Shadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 2)),
];

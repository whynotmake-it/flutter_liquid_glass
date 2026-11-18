import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

/// Scrolling glass content for renderer regressions: 15 standalone shapes,
/// or the same shapes merged in [LiquidGlassBlendGroup]s.
class ScrollingGlass extends StatelessWidget {
  const ScrollingGlass({required this.blended, super.key});

  final bool blended;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 40, 20, 220),
          sliver: SliverList.list(
            children: [
              for (var row = 0; row < 5; row++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 180),
                  child: blended
                      ? const LiquidGlassBlendGroup(child: _Row())
                      : const _Row(),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row();

  @override
  Widget build(BuildContext context) {
    Widget glass(LiquidShape shape, double width) {
      return LiquidGlass(
        shape: shape,
        child: SizedBox(width: width, height: 64),
      );
    }

    return Row(
      spacing: 12,
      children: [
        glass(const LiquidRoundedSuperellipse(radius: 32), 180),
        glass(const LiquidOval(), 64),
        glass(const LiquidOval(), 64),
      ],
    );
  }
}

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/backdrop.dart';
import 'package:apple_liquid_glass_example/widgets.dart';
import 'package:flutter/widgets.dart';

/// A glass card that lifts on a tap: one `withSpring` around the change,
/// one `MotionTransition` around the card. The Reduce Motion switch
/// overrides the page's motion traits, and the lift's spring carries a
/// `reduced` alternative that does not bounce.
class TwoLines extends StatefulWidget {
  const TwoLines({
    required this.reduceMotion,
    required this.onReduceMotion,
    super.key,
  });

  final bool reduceMotion;
  final ValueChanged<bool> onReduceMotion;

  @override
  State<TwoLines> createState() => _TwoLinesState();
}

final class _Card extends Motion {
  late final lift = own(MotionValue<double>(0));
}

class _TwoLinesState extends State<TwoLines> {
  static const _lift = Spring(bounce: 0.3, reduced: Spring.smooth);

  final _card = _Card();
  late final _scale = _card.select((c) => 1 + 0.08 * c.lift.valueAt(c.now));
  late final _rise = _card.select((c) => -28 * c.lift.valueAt(c.now));

  void _toggle() => withSpring(
    _lift,
    () => _card.lift.target = _card.lift.target == 0 ? 1 : 0,
  );

  @override
  Widget build(BuildContext context) => GlassListSection(
    header: const Text('Two lines'),
    footer: const Text(
      'The card is a withSpring around the change and a MotionTransition '
      'around the card. Under Reduce Motion the same spring moves without '
      'bouncing.',
    ),
    children: [
      ClipRect(
        child: SizedBox(
          height: 220,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image(image: Wallpaper.bloom.image, fit: BoxFit.cover),
              Center(
                child: MotionScope(
                  motion: _card,
                  child: MotionTransition(
                    scale: _scale,
                    translateY: _rise,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _toggle,
                      child: const SizedBox(
                        width: 220,
                        height: 120,
                        child: GlassSurface(
                          shape: LiquidRoundedSuperellipse(radius: 28),
                          child: Center(
                            child: PhotoText(
                              'Tap me',
                              size: 22,
                              weight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      GlassListRow(
        title: const Text('Reduce Motion'),
        trailing: GlassSwitch(
          value: widget.reduceMotion,
          onChanged: widget.onReduceMotion,
        ),
      ),
    ],
  );
}

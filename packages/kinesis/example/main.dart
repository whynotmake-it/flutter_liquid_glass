import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

void main() => runApp(const KinesisExample());

/// A square that springs between two sizes on a tap, and a puck that
/// follows a finger and springs home with the speed it was let go at.
class KinesisExample extends StatelessWidget {
  /// Creates the example app.
  const KinesisExample({super.key});

  @override
  Widget build(BuildContext context) => WidgetsApp(
    color: const Color(0xFF007AFF),
    builder: (context, _) => const ColoredBox(
      color: Color(0xFFF2F2F7),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [Grow(), Puck()],
      ),
    ),
  );
}

/// A square whose scale springs between 1 and 1.5 on each tap; a tap
/// mid-flight turns it around at the speed it has.
class Grow extends StatefulWidget {
  /// Creates the square.
  const Grow({super.key});

  @override
  State<Grow> createState() => _GrowState();
}

class _GrowState extends State<Grow> {
  final _scale = MotionValue<double>(1);

  void _toggle() => withSpring(
    Spring.bouncy,
    () => _scale.target = _scale.target == 1 ? 1.5 : 1,
  );

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: _toggle,
    child: MotionTransition(
      scale: _scale,
      child: const SizedBox.square(
        dimension: 80,
        child: ColoredBox(color: Color(0xFF007AFF)),
      ),
    ),
  );
}

/// A puck that follows a finger and, on release, springs back home with
/// the finger's velocity.
class Puck extends StatefulWidget {
  /// Creates the puck.
  const Puck({super.key});

  @override
  State<Puck> createState() => _PuckState();
}

class _PuckState extends State<Puck> {
  final _offset = MotionValue(Offset.zero);

  late final _drag = DragInteraction(
    onUpdate: (details) => _offset.target = details.translation,
    onEnd: (details) {
      _offset.velocity = details.velocity;
      withSpring(Spring.bouncy, () => _offset.target = Offset.zero);
    },
  );

  @override
  Widget build(BuildContext context) => InputRegion(
    interactions: [_drag],
    child: MotionTransition(
      offset: _offset,
      child: const SizedBox.square(
        dimension: 64,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Color(0xFFFF9500),
            shape: BoxShape.circle,
          ),
        ),
      ),
    ),
  );
}

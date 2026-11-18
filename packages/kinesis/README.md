# kinesis

Motion for any Flutter app, built the way UIKit does it: springs that keep
their velocity when retargeted, animation transactions, gestures as pure
logic, presentations, and time you can replay exactly in a test.

A `MotionValue` holds the `target` you set and the value on screen. Assign
the target inside `withSpring` and the value springs there. Assign it again
mid-flight and it continues from where it is, at the speed it has.

`Spring` takes either form and maps one exactly onto the other:
`Spring(duration: Duration(milliseconds: 500), bounce: 0.3)` (SwiftUI) and
`Spring.response(0.5, dampingRatio: 0.7)` (UIKit).

## Status

Pre-release (`0.1.0-dev`). The API may still change between versions.

## Install

```sh
flutter pub add kinesis
```

## Requirements

- Flutter 3.47 or newer and Dart 3.13 or newer.
- kinesis is Dart and Flutter only: no plugin and no platform channel. On
  iOS and macOS it uses `dart:ffi` to line up pointer time stamps with frame
  time after the device slept. Where `dart:ffi` is missing, such as on the
  web, a stub takes its place.

## Libraries

`package:kinesis/kinesis.dart` exports the four libraries below. Each can
also be imported alone.

| Library | What it holds |
| --- | --- |
| `package:kinesis/motion.dart` | The motion kernel: `Spring`, `MotionValue`, `withSpring` and `withoutAnimation`, `MotionSelection` for derived values, the frame clock `MotionClock` and `FrameCadence`, and `Motion`, a pure class built from parts such as `Presence`, `Ramp`, `RubberBand`, `MotionRect`, `Projection` and `LayoutMotion`. No widgets. |
| `package:kinesis/input.dart` | Gestures as pure logic: `PressInteraction`, `TapInteraction`, `LongPressInteraction`, `DragInteraction`, `FollowInteraction` and more, combined with `exclusively` and `simultaneously`, and `InteractionSession`, which replays stamped input. Keyboard and accessibility commands arrive on the same path as touches. No widgets. |
| `package:kinesis/widgets.dart` | Motion and input in the widget tree: `MotionTransition` and `MotionDriven` (move, scale, fade and blur a child from motion values without rebuilding it), `MotionLayout` and `SliverMotionList` (animate what layout did), `MotionMeasure`, `MotionScroll`, `InputRegion` and `InputZones` (touch, mouse, focus, keyboard and semantics for a control in one place), `MotionScope`, `MotionTraitsOverride` and `MotionSource`. |
| `package:kinesis/presentation.dart` | Overlays: `Presentation` (the motion and the content), shown by `PresentationRoute` (a popup), `PresentationPageRoute` (a page) or `PresentationPortal` (no route), and `showPresentation`. Every shell handles focus, Escape, Back and screen readers. A route also follows Android's predictive back when its motion mixes in `PredictiveBack`. |
| `package:kinesis/testing.dart` | `ManualMotionClock`, a clock that moves only when told to. Not exported by `kinesis.dart`. |

## A spring-driven value

A tap springs the square's scale between 1 and 1.5. A tap mid-flight turns it
around without a jump. `MotionTransition` applies the value to one composited
layer, so a frame of motion rebuilds no widget.

```dart
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';

class Grow extends StatefulWidget {
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
```

## An interaction

A puck follows the finger and, on release, springs home with the finger's
velocity. Setting `target` outside `withSpring` makes the value jump, which
is what a value under a finger wants. `InputRegion` stamps every event with
its own time, so the drag ends exactly as a replay of it would.

```dart
class Puck extends StatefulWidget {
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
```

## A presentation

A presentation is a motion plus the content drawn over it. The motion mixes
in `Presented`: the shell calls `open` when it is shown and `leave` when it
is dismissed, and ends the route once `presence` is hidden. `Motion.select`
turns a read of the motion into a listenable for `MotionTransition`.

```dart
final class CardMotion extends Motion with Presented {
  CardMotion({super.clock});

  late final Presence _shown = own(Presence(openSpring: Spring.snappy));

  late final MotionSelection<double> opacity = select((m) => m._shown.opacity);

  late final MotionSelection<double> scale = select(
    (m) => 0.9 + 0.1 * m._shown.progress,
  );

  @override
  PresenceStatus get presence => _shown.status;

  @override
  void open(double t) => _shown.open(t);

  @override
  bool leave(double t, DismissTrigger trigger) {
    _shown.hide(t);
    return true;
  }
}

Future<void> showCard(BuildContext context) => showPresentation(
  context,
  PresentationRoute(
    presentation: Presentation<void, CardMotion>(
      motion: (environment) => CardMotion(clock: environment.clock),
      dim: (motion) => 0.3 * motion.opacity.value,
      semanticsLabel: 'Card',
      builder: (context, motion) => Center(
        child: MotionTransition(
          opacity: motion.opacity,
          scale: motion.scale,
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: const SizedBox(
              width: 240,
              height: 160,
              child: ColoredBox(color: Color(0xFFFFFFFF)),
            ),
          ),
        ),
      ),
    ),
  ),
);
```

## Testing

Every operation also has a form with an explicit time, so a motion built
from these values is a pure function of its inputs. `ManualMotionClock` runs
the frame phases only when told to:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';
import 'package:kinesis/testing.dart';

void main() {
  test('the width springs to 200', () {
    final clock = ManualMotionClock();
    final width = MotionValue<double>(100, clock: clock);
    withSpring(Spring.snappy, () => width.target = 200);

    clock.advanceTo(0.1);
    expect(width.value, greaterThan(100));

    clock.advanceTo(2);
    expect(width.value, closeTo(200, 1));
  });
}
```

In a widget tree, `MotionClockScope` gives a subtree its clock, such as a
`ManualMotionClock`.

## Example

[`example/main.dart`](example/main.dart) is a one-file app with the square
and the puck above. Copy it into the `lib/main.dart` of a Flutter app that
depends on kinesis and run it.

## License

Apache 2.0, see [LICENSE](LICENSE).

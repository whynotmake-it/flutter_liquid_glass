import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';
import 'package:kinesis/testing.dart';

/// Writes the phases of the touch it follows.
final class _Follows extends Interaction {
  final List<String> heard = [];

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput():
        heard.add('down');
      case PointerMoveInput():
        heard.add('move');
      case PointerUpInput():
        heard.add('up');
      case PointerCancelInput():
        heard.add('cancel');
      default:
    }
    return InteractionUpdate.none;
  }
}

/// One zone over the whole of [child].
Widget _zone(
  List<Interaction> interactions,
  Listenable frames, {
  required Widget child,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: InputZones<int>(
    zones: [InputZone(id: 0, interactions: interactions)],
    frameOf: (id) => const InputZoneFrame(Rect.fromLTWH(0, 0, 800, 600)),
    frames: frames,
    child: child,
  ),
);

void main() {
  setUp(MotionClock.debugReset);

  late ValueNotifier<int> frames;
  setUp(() => frames = ValueNotifier(0));
  tearDown(() => frames.dispose());

  Future<TestGesture> pull(WidgetTester tester, int points) async {
    final gesture = await tester.startGesture(const Offset(200, 300));
    for (var i = 0; i < points; i++) {
      await gesture.moveBy(const Offset(0, -1));
      await tester.pump();
    }
    return gesture;
  }

  testWidgets('a scroll view inside the zones that passes its slop on the '
      'same move takes the touch from a zone, as from a region', (
    tester,
  ) async {
    final drag = DragInteraction(
      axis: Axis.vertical,
      slop: 12,
      contends: true,
      global: true,
    );
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      _zone(
        [drag],
        frames,
        child: ListView.builder(
          controller: scroll,
          itemCount: 100,
          itemBuilder: (context, i) => const SizedBox(height: 50),
        ),
      ),
    );
    final gesture = await pull(tester, 40);
    expect(drag.started, isFalse);
    expect(scroll.offset, greaterThan(0));
    await gesture.up();
  });

  testWidgets('the zones stamp a touch on the clock of the motions around '
      'them', (tester) async {
    final clock = ManualMotionClock(start: 5);
    double? started;
    final drag = DragInteraction(
      axis: Axis.vertical,
      slop: 12,
      onStart: (details) => started = details.time,
    );
    await tester.pumpWidget(
      MotionClockScope(
        clock: clock,
        child: _zone([drag], frames, child: const SizedBox.expand()),
      ),
    );
    final gesture = await pull(tester, 20);
    await gesture.up();
    expect(started, 5);
  });

  testWidgets('a zone disabled under a finger leaves the host its touch, and '
      'the next touch starts anew', (tester) async {
    final host = _Follows();
    final row = _Follows();
    final enabled = ValueNotifier(true);
    addTearDown(enabled.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ValueListenableBuilder(
          valueListenable: enabled,
          builder: (context, on, child) => InputZones<int>(
            zones: [
              InputZone(id: 0, interactions: [row], enabled: on),
            ],
            frameOf: (id) =>
                const InputZoneFrame(Rect.fromLTWH(0, 0, 800, 600)),
            frames: frames,
            interactions: [host],
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(const Offset(200, 300));
    await tester.pump();
    enabled.value = false;
    await tester.pump();
    expect(row.heard, ['down', 'cancel']);
    await gesture.moveBy(const Offset(0, 5));
    await gesture.up();
    await tester.pump();
    expect(host.heard, ['down', 'move', 'up']);

    host.heard.clear();
    await tester.tapAt(const Offset(200, 300));
    await tester.pump();
    expect(host.heard, ['down', 'up']);
    expect(row.heard, ['down', 'cancel']);
  });
}

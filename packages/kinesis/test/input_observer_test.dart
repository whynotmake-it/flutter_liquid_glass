import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

/// Writes down what it hears, in global coordinates, as a context menu's
/// hold does with the touches on its anchor.
class _Observer extends Interaction {
  _Observer() : super(role: InteractionRole.observer);

  final List<String> heard = [];
  final List<double> times = [];
  Offset Function(Offset local) _toGlobal = _same;

  static Offset _same(Offset p) => p;

  @override
  void bindRegion(Offset Function(Offset local) toGlobal) =>
      _toGlobal = toGlobal;

  String _at(Offset local) {
    final global = _toGlobal(local);
    return '${global.dx.round()},${global.dy.round()}';
  }

  @override
  InteractionUpdate handle(InteractionInput input) {
    final line = switch (input) {
      PointerDownInput(:final pointer, :final position) =>
        'down $pointer ${_at(position)}',
      PointerMoveInput(:final pointer, :final position) =>
        'move $pointer ${_at(position)}',
      PointerUpInput(:final pointer, :final position) =>
        'up $pointer ${_at(position)}',
      PointerCancelInput(:final pointer) => 'cancel $pointer',
      _ => null,
    };
    if (line != null) {
      heard.add(line);
      times.add(input.time);
    }
    return const InteractionUpdate(claims: true, recognizes: true);
  }
}

Widget _app(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(alignment: Alignment.topLeft, child: child),
);

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('an observer hears a touch a button below it wins, from down '
      'to up, stamped at each event', (tester) async {
    final observer = _Observer();
    var taps = 0;
    final press = [PressInteraction(onTap: (t) => taps++)];
    await tester.pumpWidget(
      _app(
        InputRegion(
          interactions: [observer],
          child: InputRegion(
            interactions: press,
            child: const SizedBox(width: 100, height: 50),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(const Offset(20, 20), pointer: 1);
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveTo(
      const Offset(24, 22),
      timeStamp: const Duration(milliseconds: 16),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up(timeStamp: const Duration(milliseconds: 32));
    expect(taps, 1, reason: 'the button kept its touch');
    expect(observer.heard, ['down 1 20,20', 'move 1 24,22', 'up 1 24,22']);
    expect(observer.times[1], greaterThanOrEqualTo(observer.times[0]));
    expect(observer.times[2], greaterThanOrEqualTo(observer.times[1]));
  });

  testWidgets('an observer joins no arena: a tap below it is accepted at '
      'the touch, and a scroll around it still scrolls while it hears the '
      'moves', (tester) async {
    final observer = _Observer();
    var tapDowns = 0;
    await tester.pumpWidget(
      _app(
        InputRegion(
          interactions: [_Observer()],
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => tapDowns++,
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      ),
    );
    final tap = await tester.startGesture(const Offset(50, 50));
    await tester.pump();
    expect(tapDowns, 1, reason: 'the tap is alone in the arena');
    await tap.up();

    await tester.pumpWidget(
      _app(
        SizedBox(
          width: 100,
          height: 300,
          child: ListView(
            children: [
              InputRegion(
                interactions: [observer],
                child: const SizedBox(height: 100),
              ),
              const SizedBox(height: 1000),
            ],
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(const Offset(50, 50), pointer: 1);
    for (var i = 0; i < 5; i++) {
      await gesture.moveBy(const Offset(0, -10));
      await tester.pump();
    }
    await gesture.up();
    await tester.pump();
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scroll.position.pixels, greaterThan(0));
    expect(observer.heard.first, 'down 1 50,50');
    expect(observer.heard.last, startsWith('up 1 '));
    expect(
      observer.heard.where((line) => line.startsWith('move')),
      hasLength(5),
    );
  });

  testWidgets('an observer hears several fingers at once, beside a press '
      'that follows the first', (tester) async {
    final observer = _Observer();
    var taps = 0;
    await tester.pumpWidget(
      _app(
        InputRegion(
          interactions: [
            PressInteraction(onTap: (t) => taps++),
            observer,
          ],
          child: const SizedBox(width: 200, height: 100),
        ),
      ),
    );
    final first = await tester.startGesture(const Offset(10, 10), pointer: 1);
    final second = await tester.startGesture(
      const Offset(100, 10),
      pointer: 2,
    );
    await second.moveTo(const Offset(110, 10));
    await second.up();
    await first.up();
    expect(taps, 1);
    expect(observer.heard, [
      'down 1 10,10',
      'down 2 100,10',
      'move 2 110,10',
      'up 2 110,10',
      'up 1 10,10',
    ]);
  });

  testWidgets('disabling the region cancels what its observer hears', (
    tester,
  ) async {
    final observer = _Observer();
    Widget region({required bool enabled}) => _app(
      InputRegion(
        interactions: [observer],
        enabled: enabled,
        child: const SizedBox(width: 100, height: 50),
      ),
    );
    await tester.pumpWidget(region(enabled: true));
    final gesture = await tester.startGesture(const Offset(20, 20), pointer: 1);
    await tester.pumpWidget(region(enabled: false));
    await gesture.up();
    expect(observer.heard, ['down 1 20,20', 'cancel 1']);
  });

  test('a session hands observers every pointer and keeps them when the '
      'touch is lost', () {
    final observer = _Observer();
    final session = InteractionSession([observer]);
    const size = Size(100, 50);
    final down = session.handle(
      const PointerDownInput(
        time: 0,
        pointer: 1,
        position: Offset(1, 1),
        regionSize: size,
      ),
    );
    expect(down.reject, isTrue, reason: 'nothing takes part in the arena');
    expect(down.claim, isFalse);
    expect(session.observes(1), isTrue);
    expect(session.lost(1, 0.01).events, isEmpty);
    session.handle(
      PointerUpInput(
        time: 0.02,
        pointer: 1,
        position: const Offset(2, 2),
        regionBox: Offset.zero & size,
      ),
    );
    expect(session.observes(1), isFalse);
    expect(observer.heard, ['down 1 1,1', 'up 1 2,2']);
  });

  test('an observer hears only the pointers it accepts', () {
    final observer = _Observer();
    final session = InteractionSession([observer]);
    session.handle(
      const PointerDownInput(
        time: 0,
        pointer: 1,
        position: Offset.zero,
        regionSize: Size(10, 10),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      ),
    );
    expect(session.observes(1), isFalse);
  });
}

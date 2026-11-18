import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';
import 'package:kinesis/testing.dart';

/// Writes down every touch event it hears with its stamp, and raises a
/// slide event for every move, as a menu's finger does over its rows.
class _Recorder extends Interaction {
  _Recorder({super.role});

  final List<String> heard = [];
  final List<double> times = [];

  @override
  bool accepts(PointerDownInput down) => true;

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
    if (line == null) return InteractionUpdate.none;
    heard.add(line);
    times.add(input.time);
    return InteractionUpdate(
      events: [
        if (input is PointerMoveInput)
          ScrubChangeEvent(time: input.time, selected: input.position),
      ],
    );
  }

  static String _at(Offset p) => '${p.dx.round()},${p.dy.round()}';
}

void main() {
  setUp(MotionClock.debugReset);

  final haptics = <String>[];

  setUp(() {
    haptics.clear();
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments as String);
          }
          return null;
        });
  });

  tearDown(
    () => TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );

  // Pumps [child] and returns a context inside it.
  Future<BuildContext> pump(
    WidgetTester tester,
    Widget child, {
    MotionClock? clock,
  }) async {
    late BuildContext context;
    final Widget built = Builder(
      builder: (c) {
        context = c;
        return child;
      },
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: clock == null
            ? built
            : MotionClockScope(clock: clock, child: built),
      ),
    );
    return context;
  }

  int routes() => GestureBinding.instance.pointerRouter.debugGlobalRouteCount;

  testWidgets('an armed capture runs a touch anywhere through its '
      'interactions at the stamps a region gives the same touch', (
    tester,
  ) async {
    final region = _Recorder(role: InteractionRole.observer);
    final context = await pump(
      tester,
      InputRegion(interactions: [region], child: const SizedBox.expand()),
    );
    final recorder = _Recorder();
    final capture = InputCapture(context: context, interactions: [recorder]);
    addTearDown(capture.dispose);
    capture.arm();
    expect(capture.armed, isTrue);
    final gesture = await tester.startGesture(
      const Offset(300, 400),
      pointer: 1,
    );
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveTo(
      const Offset(310, 420),
      timeStamp: const Duration(milliseconds: 16),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up(timeStamp: const Duration(milliseconds: 40));
    expect(recorder.heard, [
      'down 1 300,400',
      'move 1 310,420',
      'up 1 310,420',
    ]);
    expect(recorder.heard, region.heard);
    expect(recorder.times, region.times);
    expect(recorder.times[2], greaterThan(recorder.times[0]));
  });

  testWidgets('under a MotionClockScope it stamps on that clock', (
    tester,
  ) async {
    final clock = ManualMotionClock(start: 5);
    final context = await pump(
      tester,
      const SizedBox.expand(),
      clock: clock,
    );
    final recorder = _Recorder();
    final capture = InputCapture(context: context, interactions: [recorder]);
    addTearDown(capture.dispose);
    capture.arm();
    final gesture = await tester.startGesture(const Offset(20, 30));
    clock.advanceTo(5.25);
    await gesture.moveTo(const Offset(40, 30));
    clock.advanceTo(5.5);
    await gesture.up();
    expect(recorder.heard, hasLength(3));
    expect(recorder.times, [5, 5.25, 5.5]);
  });

  testWidgets('a disarmed capture takes no touch and holds no route', (
    tester,
  ) async {
    final context = await pump(tester, const SizedBox.expand());
    final before = routes();
    final recorder = _Recorder();
    final capture = InputCapture(context: context, interactions: [recorder]);
    addTearDown(capture.dispose);
    await tester.tapAt(const Offset(50, 50));
    capture.arm();
    expect(routes(), before + 1);
    capture.arm();
    expect(routes(), before + 1, reason: 'arming again changes nothing');
    capture.disarm();
    expect(capture.armed, isFalse);
    expect(routes(), before);
    await tester.tapAt(const Offset(60, 60));
    expect(recorder.heard, isEmpty);
  });

  testWidgets('a touch it holds when it disarms runs to its up', (
    tester,
  ) async {
    final context = await pump(tester, const SizedBox.expand());
    final before = routes();
    final recorder = _Recorder();
    final capture = InputCapture(context: context, interactions: [recorder]);
    addTearDown(capture.dispose);
    capture.arm();
    final gesture = await tester.startGesture(
      const Offset(10, 10),
      pointer: 3,
    );
    capture.disarm();
    expect(routes(), before + 1);
    await gesture.moveTo(const Offset(30, 10));
    await gesture.up();
    expect(recorder.heard, ['down 3 10,10', 'move 3 30,10', 'up 3 30,10']);
    expect(routes(), before);
    await tester.tapAt(const Offset(50, 50));
    expect(recorder.heard, hasLength(3));
  });

  testWidgets('a second finger and a button other than the primary are '
      'ignored', (tester) async {
    final context = await pump(tester, const SizedBox.expand());
    final recorder = _Recorder();
    final capture = InputCapture(context: context, interactions: [recorder]);
    addTearDown(capture.dispose);
    capture.arm();
    final first = await tester.startGesture(const Offset(10, 10), pointer: 1);
    final second = await tester.startGesture(
      const Offset(90, 90),
      pointer: 2,
    );
    await second.moveTo(const Offset(95, 95));
    await second.up();
    await first.up();
    final mouse = await tester.startGesture(
      const Offset(50, 50),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryButton,
    );
    await mouse.up();
    expect(recorder.heard, ['down 1 10,10', 'up 1 10,10']);
  });

  testWidgets('the haptic its feedback picks plays for the event that names '
      'one', (tester) async {
    final context = await pump(tester, const SizedBox.expand());
    final recorder = _Recorder();
    final capture = InputCapture(
      context: context,
      interactions: [recorder],
      feedback: (event) =>
          event is ScrubChangeEvent ? MotionHaptic.selection : null,
    );
    addTearDown(capture.dispose);
    capture.arm();
    final gesture = await tester.startGesture(const Offset(10, 10));
    expect(haptics, isEmpty);
    await gesture.moveTo(const Offset(20, 10));
    await gesture.moveTo(const Offset(30, 10));
    await gesture.up();
    expect(haptics, [
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.selectionClick',
    ]);
  });

  testWidgets('disposing cancels the touch it holds and removes the route', (
    tester,
  ) async {
    final context = await pump(tester, const SizedBox.expand());
    final before = routes();
    final recorder = _Recorder();
    final capture = InputCapture(context: context, interactions: [recorder]);
    capture.arm();
    final gesture = await tester.startGesture(
      const Offset(10, 10),
      pointer: 4,
    );
    capture.dispose();
    expect(routes(), before);
    await gesture.up();
    expect(recorder.heard, ['down 4 10,10', 'cancel 4']);
  });
}

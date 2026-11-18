import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

/// Follows one finger over a menu's rows, as a menu does that stretches
/// after a finger beyond its edge: which row is under it now, where it is
/// in the host, and the stamp.
class _Finger extends Interaction {
  _Finger(this.zones);

  final InputZonesController<int> zones;
  final List<(String, int?, Offset)> heard = [];
  final List<double> times = [];

  void _hear(String phase, InteractionInput input, Offset position) {
    heard.add((phase, zones.zoneAt(position), position));
    times.add(input.time);
  }

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput(:final position):
        _hear('down', input, position);
        return const InteractionUpdate(claims: true);
      case PointerMoveInput(:final position):
        _hear('move', input, position);
      case PointerUpInput(:final position):
        _hear('up', input, position);
      case PointerCancelInput():
        heard.add(('cancel', null, Offset.zero));
      default:
    }
    return InteractionUpdate.none;
  }
}

/// Hears what reaches a host interaction besides the finger's path: the
/// arena's acceptance, the mouse over the host, and reports the row under
/// a sliding finger as an event.
class _Listener extends Interaction {
  _Listener(this.zones, {this.contends = false});

  final InputZonesController<int> zones;
  final bool contends;
  final List<String> heard = [];
  int? _row;

  @override
  bool get contendsWithControls => contends;

  @override
  InteractionUpdate handle(InteractionInput input) {
    switch (input) {
      case PointerDownInput(:final position):
        _row = zones.zoneAt(position);
      case PointerMoveInput(:final position):
        final row = zones.zoneAt(position);
        if (row == _row) break;
        _row = row;
        return InteractionUpdate(
          events: [ScrubChangeEvent(time: input.time, selected: row)],
        );
      case PointerAcceptedInput():
        heard.add('accepted');
      case PointerHoverInput(:final position):
        heard.add('hover ${zones.zoneAt(position)}');
      default:
    }
    return InteractionUpdate.none;
  }
}

/// Three rows of 40 points, one under the other, in a 100 point wide menu
/// at (50, 50).
class _Menu extends StatelessWidget {
  const _Menu({
    required this.zones,
    required this.finger,
    required this.frames,
    this.port,
    this.rowTaps,
    this.others = const [],
    this.hostFeedback,
    this.rowInputs,
    this.child = const SizedBox(width: 100, height: 120),
  });

  final InputZonesController<int> zones;
  final _Finger finger;
  final List<Interaction> others;
  final MotionHaptic? Function(InteractionEvent event)? hostFeedback;
  final List<String>? rowInputs;
  final Widget child;
  final Listenable frames;
  final InputPort? port;
  final List<int>? rowTaps;

  @override
  Widget build(BuildContext context) => Positioned(
    left: 50,
    top: 50,
    child: InputZones<int>(
      zones: [
        for (var i = 0; i < 3; i++)
          InputZone(
            id: i,
            interactions: [
              PressInteraction(onTap: (t) => rowTaps?.add(i)),
              if (rowInputs case final inputs?) _Heard(inputs),
            ],
          ),
      ],
      frameOf: (id) => InputZoneFrame(Rect.fromLTWH(0, id * 40.0, 100, 40)),
      frames: frames,
      controller: zones,
      interactions: [finger, ...others],
      hostFeedback: hostFeedback,
      port: port,
      child: child,
    ),
  );
}

/// Writes the arena's acceptance of a row's touch.
class _Heard extends Interaction {
  _Heard(this.heard);

  final List<String> heard;

  @override
  InteractionUpdate handle(InteractionInput input) {
    if (input is PointerAcceptedInput) heard.add('accepted');
    return InteractionUpdate.none;
  }
}

Widget _screen(List<Widget> children) => Directionality(
  textDirection: TextDirection.ltr,
  child: Stack(children: children),
);

void main() {
  setUp(MotionClock.debugReset);

  late InputZonesController<int> zones;
  late ValueNotifier<int> frames;

  setUp(() {
    zones = InputZonesController<int>();
    frames = ValueNotifier(0);
  });

  tearDown(() {
    zones.dispose();
    frames.dispose();
  });

  testWidgets('a host interaction follows one finger from a row across two '
      'more, beyond the host and back, to its release', (tester) async {
    final finger = _Finger(zones);
    await tester.pumpWidget(
      _screen([_Menu(zones: zones, finger: finger, frames: frames)]),
    );
    final gesture = await tester.startGesture(const Offset(100, 70));
    for (final to in const [
      Offset(100, 110),
      Offset(100, 150),
      Offset(100, 230),
      Offset(170, 230),
      Offset(100, 155),
    ]) {
      await gesture.moveTo(to);
      await tester.pump();
    }
    await gesture.up();
    expect(finger.heard, [
      ('down', 0, const Offset(50, 20)),
      ('move', 1, const Offset(50, 60)),
      ('move', 2, const Offset(50, 100)),
      ('move', null, const Offset(50, 180)),
      ('move', null, const Offset(120, 180)),
      ('move', 2, const Offset(50, 105)),
      ('up', 2, const Offset(50, 105)),
    ]);
    for (var i = 1; i < finger.times.length; i++) {
      expect(finger.times[i], greaterThanOrEqualTo(finger.times[i - 1]));
    }
  });

  testWidgets('a touch between the zones and outside them reaches the host, '
      'and a zone under the finger still presses beside it', (tester) async {
    final finger = _Finger(zones);
    final taps = <int>[];
    await tester.pumpWidget(
      _screen([
        _Menu(zones: zones, finger: finger, frames: frames, rowTaps: taps),
      ]),
    );
    await tester.tapAt(const Offset(100, 115));
    expect(taps, [1]);
    expect(finger.heard.first, ('down', 1, const Offset(50, 65)));
    expect(finger.heard.last.$1, 'up');
  });

  testWidgets('the finger that opened the menu arrives through the port on no '
      'zone and slides onto the rows', (tester) async {
    final finger = _Finger(zones);
    final port = InputPort();
    await tester.pumpWidget(
      _screen([
        Positioned(
          left: 0,
          top: 0,
          child: InputRegion(
            interactions: [port.forward],
            child: const SizedBox(width: 40, height: 40),
          ),
        ),
        _Menu(zones: zones, finger: finger, frames: frames, port: port),
      ]),
    );
    await tester.pump();
    final gesture = await tester.startGesture(const Offset(20, 20));
    await gesture.moveTo(const Offset(100, 60));
    await gesture.moveTo(const Offset(100, 100));
    await gesture.up();
    expect(finger.heard, [
      ('down', null, const Offset(-30, -30)),
      ('move', 0, const Offset(50, 10)),
      ('move', 1, const Offset(50, 50)),
      ('up', 1, const Offset(50, 50)),
    ]);
  });

  testWidgets('zoneAt answers no zone for a disabled row or without a host', (
    tester,
  ) async {
    expect(zones.zoneAt(const Offset(10, 10)), isNull);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: InputZones<int>(
            zones: const [
              InputZone(id: 0),
              InputZone(id: 1, enabled: false),
            ],
            frameOf: (id) =>
                InputZoneFrame(Rect.fromLTWH(id * 50.0, 0, 50, 40)),
            frames: frames,
            controller: zones,
            child: const SizedBox(width: 100, height: 40),
          ),
        ),
      ),
    );
    expect(zones.zoneAt(const Offset(10, 10)), 0);
    expect(zones.zoneAt(const Offset(60, 10)), isNull);
    expect(zones.zoneAt(const Offset(10, 60)), isNull);
  });

  testWidgets('a controller follows the newest host while the old one '
      'leaves after it', (tester) async {
    Widget grid(Key key, double left, {bool secondEnabled = true}) =>
        Positioned(
          key: key,
          left: left,
          top: 0,
          child: InputZones<int>(
            zones: [
              const InputZone(id: 0),
              InputZone(id: 1, enabled: secondEnabled),
            ],
            frameOf: (id) =>
                InputZoneFrame(Rect.fromLTWH(id * 50.0, 0, 50, 40)),
            frames: frames,
            controller: zones,
            child: const SizedBox(width: 100, height: 40),
          ),
        );
    const old = ValueKey('old');
    const next = ValueKey('next');
    await tester.pumpWidget(_screen([grid(old, 0)]));
    await tester.pumpWidget(
      _screen([grid(old, 0), grid(next, 200, secondEnabled: false)]),
    );
    await tester.pumpWidget(
      _screen([grid(next, 200, secondEnabled: false)]),
    );
    expect(zones.zoneAt(const Offset(10, 10)), 0);
    expect(zones.zoneAt(const Offset(60, 10)), isNull);
    expect(zones.states(1).value, contains(WidgetState.disabled));
    expect(zones.requestFocus(0), isTrue);
    await tester.pump();
    expect(zones.focusedZone, 0);
  });

  testWidgets('the haptics of a host interaction play through hostFeedback '
      'as the finger slides onto another row', (tester) async {
    final haptics = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final finger = _Finger(zones);
    await tester.pumpWidget(
      _screen([
        _Menu(
          zones: zones,
          finger: finger,
          frames: frames,
          others: [_Listener(zones)],
          hostFeedback: (event) =>
              event is ScrubChangeEvent ? MotionHaptic.selection : null,
        ),
      ]),
    );
    final gesture = await tester.startGesture(const Offset(100, 70));
    await gesture.moveTo(const Offset(100, 75));
    expect(haptics, isEmpty);
    await gesture.moveTo(const Offset(100, 110));
    await gesture.moveTo(const Offset(100, 150));
    await gesture.up();
    expect(haptics, [
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.selectionClick',
    ]);
  });

  testWidgets('the host and the row under the finger hear the arena give '
      'the host the touch', (tester) async {
    final finger = _Finger(zones);
    final listener = _Listener(zones);
    final rows = <String>[];
    await tester.pumpWidget(
      _screen([
        _Menu(
          zones: zones,
          finger: finger,
          frames: frames,
          others: [listener],
          rowInputs: rows,
        ),
      ]),
    );
    await tester.tapAt(const Offset(100, 70));
    expect(listener.heard, ['accepted']);
    expect(rows, ['accepted']);
  });

  testWidgets('the mouse over the host reaches its interactions', (
    tester,
  ) async {
    final finger = _Finger(zones);
    final listener = _Listener(zones);
    await tester.pumpWidget(
      _screen([
        _Menu(zones: zones, finger: finger, frames: frames, others: [listener]),
      ]),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(10, 10));
    await mouse.moveTo(const Offset(100, 115));
    await mouse.moveTo(const Offset(100, 155));
    await mouse.removePointer();
    expect(listener.heard, ['hover 1', 'hover 2']);
  });

  testWidgets('a host interaction that contends with controls starts the '
      'touches of a region inside the host contested', (tester) async {
    final contested = <bool>[];
    final finger = _Finger(zones);
    await tester.pumpWidget(
      _screen([
        _Menu(
          zones: zones,
          finger: finger,
          frames: frames,
          others: [_Listener(zones, contends: true)],
          child: SizedBox(
            width: 100,
            height: 120,
            child: Align(
              alignment: Alignment.bottomRight,
              child: InputRegion(
                interactions: [_Contested(contested)],
                child: const SizedBox(width: 10, height: 10),
              ),
            ),
          ),
        ),
      ]),
    );
    await tester.tapAt(const Offset(145, 165));
    expect(contested, [true]);
  });
}

/// Writes whether the touches it hears start contested.
class _Contested extends Interaction {
  _Contested(this.contested);

  final List<bool> contested;

  @override
  InteractionUpdate handle(InteractionInput input) {
    if (input is PointerDownInput) contested.add(input.contested);
    return InteractionUpdate.none;
  }
}

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';
import 'package:kinesis/testing.dart';

/// A sheet that the drag moves under the finger: its region lies inside
/// the box the drag translates, as a presented sheet's does, with an
/// optional button on it.
class _Sheet extends StatefulWidget {
  const _Sheet({
    required this.drag,
    required this.offset,
    this.button,
    this.scale = 1,
  });

  final DragInteraction drag;
  final ValueNotifier<double> offset;
  final List<Interaction>? button;
  final double scale;

  @override
  State<_Sheet> createState() => _SheetState();
}

class _SheetState extends State<_Sheet> {
  late final List<Interaction> _drag = [widget.drag];

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: ValueListenableBuilder<double>(
      valueListenable: widget.offset,
      builder: (context, offset, child) => Transform.translate(
        offset: Offset(0, offset),
        child: Transform.scale(
          scale: widget.scale,
          alignment: Alignment.topLeft,
          child: child,
        ),
      ),
      child: Align(
        alignment: Alignment.topLeft,
        child: InputRegion(
          interactions: _drag,
          child: SizedBox(
            width: 400,
            height: 400,
            child: Center(
              child: widget.button == null
                  ? null
                  : InputRegion(
                      interactions: widget.button!,
                      statesController: _button,
                      child: const SizedBox(width: 100, height: 100),
                    ),
            ),
          ),
        ),
      ),
    ),
  );

  final _button = WidgetStatesController();

  bool get pressed => _button.value.contains(WidgetState.pressed);

  @override
  void dispose() {
    _button.dispose();
    super.dispose();
  }
}

/// The sheet's pan as UIKit has it: 12 points alone, 18 against a control
/// under the finger, in screen coordinates.
DragInteraction _pan(ValueNotifier<double> offset) => DragInteraction(
  axis: Axis.vertical,
  slop: 12,
  contends: true,
  global: true,
  onUpdate: (details) => offset.value = details.translation.dy,
);

/// Hears where each move of a touch is.
final class _Heard extends Interaction {
  _Heard() : super(role: InteractionRole.observer);

  Offset? last;

  @override
  InteractionUpdate handle(InteractionInput input) {
    if (input is PointerMoveInput) last = input.globalPosition;
    return InteractionUpdate.none;
  }
}

/// A value the keyboard and accessibility step, which no finger reaches.
final class _KeysOnly extends Interaction {
  int steps = 0;

  @override
  bool get adjusts => true;

  @override
  bool get takesPointers => false;

  @override
  InteractionUpdate handle(InteractionInput input) {
    if (input is AdjustInput) steps++;
    return InteractionUpdate.none;
  }
}

/// A region with [interactions] around a list of rows.
Widget _overList(List<Interaction> interactions, ScrollController scroll) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: InputRegion(
        interactions: interactions,
        child: ListView.builder(
          controller: scroll,
          itemCount: 100,
          itemBuilder: (context, i) => const SizedBox(height: 50),
        ),
      ),
    );

void main() {
  setUp(MotionClock.debugReset);

  late ValueNotifier<double> offset;
  setUp(() => offset = ValueNotifier(0));
  tearDown(() => offset.dispose());

  Future<TestGesture> pull(
    WidgetTester tester,
    Offset from,
    int points,
  ) async {
    final gesture = await tester.startGesture(from);
    for (var i = 0; i < points; i++) {
      await gesture.moveBy(const Offset(0, -1));
      await tester.pump();
    }
    return gesture;
  }

  testWidgets('alone, the sheet follows the finger 12 points after the '
      'touch, point for point while it moves under the finger', (
    tester,
  ) async {
    final drag = _pan(offset);
    await tester.pumpWidget(_Sheet(drag: drag, offset: offset));
    final gesture = await pull(tester, const Offset(200, 300), 12);
    expect(drag.started, isFalse);
    for (var i = 13; i <= 40; i++) {
      await gesture.moveBy(const Offset(0, -1));
      await tester.pump();
    }
    expect(drag.started, isTrue);
    expect(offset.value, -28);
    await gesture.up();
  });

  testWidgets('the travel is in screen points even when the sheet was '
      'scaled when the finger touched it', (tester) async {
    final drag = _pan(offset);
    await tester.pumpWidget(_Sheet(drag: drag, offset: offset, scale: 0.5));
    final gesture = await pull(tester, const Offset(100, 150), 12);
    expect(drag.started, isFalse);
    for (var i = 13; i <= 20; i++) {
      await gesture.moveBy(const Offset(0, -1));
      await tester.pump();
    }
    expect(offset.value, -8);
    await gesture.up();
  });

  testWidgets('over a button, the button shows pressed at the touch and the '
      'sheet takes the finger only after 18 points, cancelling it', (
    tester,
  ) async {
    final drag = _pan(offset);
    var taps = 0;
    await tester.pumpWidget(
      _Sheet(
        drag: drag,
        offset: offset,
        button: [PressInteraction(onTap: (t) => taps++)],
      ),
    );
    final sheet = tester.state<_SheetState>(find.byType(_Sheet));
    final gesture = await tester.startGesture(const Offset(200, 200));
    await tester.pump();
    expect(sheet.pressed, isTrue);
    for (var i = 1; i <= 18; i++) {
      await gesture.moveBy(const Offset(0, -1));
      await tester.pump();
    }
    expect(drag.started, isFalse, reason: 'within the contended slop');
    expect(sheet.pressed, isTrue);
    for (var i = 19; i <= 30; i++) {
      await gesture.moveBy(const Offset(0, -1));
      await tester.pump();
    }
    expect(drag.started, isTrue);
    expect(offset.value, -12);
    expect(sheet.pressed, isFalse, reason: 'the sheet took the touch');
    await gesture.up();
    expect(taps, 0);
  });

  testWidgets('over a button, a short touch taps it on release and the sheet '
      'stays', (tester) async {
    final drag = _pan(offset);
    var taps = 0;
    await tester.pumpWidget(
      _Sheet(
        drag: drag,
        offset: offset,
        button: [PressInteraction(onTap: (t) => taps++)],
      ),
    );
    final gesture = await pull(tester, const Offset(200, 200), 15);
    expect(drag.started, isFalse);
    await gesture.up();
    await tester.pump();
    expect(taps, 1);
    expect(offset.value, 0);
  });

  testWidgets('a drag that does not contend leaves a button its touch', (
    tester,
  ) async {
    final drag = DragInteraction(
      axis: Axis.vertical,
      slop: 12,
      onUpdate: (details) => offset.value = details.translation.dy,
    );
    var taps = 0;
    await tester.pumpWidget(
      _Sheet(
        drag: drag,
        offset: offset,
        button: [PressInteraction(onTap: (t) => taps++)],
      ),
    );
    final gesture = await pull(tester, const Offset(200, 200), 30);
    expect(drag.started, isFalse);
    await gesture.up();
    expect(offset.value, 0);
  });

  testWidgets('a scroll view inside that passes its slop on the same move '
      'takes the touch from the contended drag', (tester) async {
    final drag = _pan(offset);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(_overList([drag], scroll));
    final gesture = await pull(tester, const Offset(200, 300), 40);
    expect(drag.started, isFalse);
    expect(offset.value, 0);
    expect(scroll.offset, greaterThan(0));
    await gesture.up();
  });

  testWidgets('an observer hears a move before the recognizers inside the '
      'region', (tester) async {
    final heard = _Heard();
    final seen = <bool>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: InputRegion(
          interactions: [heard],
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: (details) =>
                seen.add(heard.last == details.globalPosition),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    final gesture = await pull(tester, const Offset(200, 300), 40);
    await gesture.up();
    expect(seen, isNotEmpty);
    expect(seen, everyElement(isTrue));
  });

  testWidgets('a finger moving where nothing answers it schedules no frame', (
    tester,
  ) async {
    final drag = _pan(offset);
    await tester.pumpWidget(_Sheet(drag: drag, offset: offset));
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(const Offset(200, 300));
    expect(tester.binding.hasScheduledFrame, isFalse);
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(4, 0));
      expect(tester.binding.hasScheduledFrame, isFalse);
    }
    await gesture.up();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a region that takes no pointers lets a touch through to what '
      'lies under it, and keeps its semantics', (tester) async {
    final semantics = tester.ensureSemantics();
    final keys = _KeysOnly();
    var taps = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => taps++,
              child: const SizedBox.expand(),
            ),
            Center(
              child: InputRegion(
                interactions: [keys],
                semantics: const SemanticsProperties(label: 'Steps'),
                child: const SizedBox(width: 44, height: 44),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.tapAt(tester.getCenter(find.bySemanticsLabel('Steps')));
    expect(taps, 1);
    tester.semantics.performAction(
      find.semantics.byLabel('Steps'),
      SemanticsAction.increase,
    );
    expect(keys.steps, 1);
    semantics.dispose();
  });

  testWidgets('the region stamps a touch on the clock of the motions around '
      'it', (tester) async {
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
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: InputRegion(
            interactions: [drag],
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    final gesture = await pull(tester, const Offset(200, 300), 20);
    await gesture.up();
    expect(started, 5);
  });

  test('a replayed drag starts at its contended slop until the arena gives '
      'it the touch, then at its own', () {
    final drag = DragInteraction(slop: 12, contends: true);
    final session = InteractionSession([drag]);
    session.handle(
      const PointerDownInput(
        time: 0,
        pointer: 1,
        position: Offset.zero,
        regionSize: Size(100, 100),
      ),
    );
    session.handle(
      const PointerMoveInput(
        time: 0.01,
        pointer: 1,
        position: Offset(0, 15),
        regionBox: Rect.fromLTWH(0, 0, 100, 100),
      ),
    );
    expect(drag.started, isFalse);
    session.handle(const PointerAcceptedInput(time: 0.02, pointer: 1));
    session.handle(
      const PointerMoveInput(
        time: 0.03,
        pointer: 1,
        position: Offset(0, 16),
        regionBox: Rect.fromLTWH(0, 0, 100, 100),
      ),
    );
    expect(drag.started, isTrue);
  });
}

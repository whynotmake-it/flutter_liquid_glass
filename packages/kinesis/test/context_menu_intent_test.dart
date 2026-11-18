import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

Widget _app(Widget child) => WidgetsApp(
  color: const Color(0xFF000000),
  builder: (context, _) => Align(alignment: Alignment.topLeft, child: child),
);

Future<void> _shiftF10(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.f10);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('the context menu key and Shift+F10 open the context menu of '
      'a focused region at its centre', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final clicks = <Offset>[];
    var taps = 0;
    await tester.pumpWidget(
      _app(
        InputRegion(
          interactions: [
            PressInteraction(onTap: (t) => taps++),
            SecondaryClickInteraction(onClick: (t, at) => clicks.add(at)),
          ],
          focusNode: focus,
          child: const SizedBox(width: 80, height: 40),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    expect(await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu), isTrue);
    await _shiftF10(tester);
    expect(clicks, [const Offset(40, 20), const Offset(40, 20)]);
    expect(taps, 0);
  });

  testWidgets('a region with no secondary click leaves the keys alone', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      _app(
        InputRegion(
          interactions: [PressInteraction()],
          focusNode: focus,
          child: const SizedBox(width: 80, height: 40),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    expect(await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu), isFalse);
  });

  testWidgets('the focused inner region opens its own menu; the outer one '
      'only when it is focused', (tester) async {
    final outer = FocusNode();
    final inner = FocusNode();
    addTearDown(outer.dispose);
    addTearDown(inner.dispose);
    final log = <String>[];
    await tester.pumpWidget(
      _app(
        InputRegion(
          interactions: [
            SecondaryClickInteraction(onClick: (t, at) => log.add('row $at')),
          ],
          focusNode: outer,
          child: SizedBox(
            width: 200,
            height: 60,
            child: Align(
              alignment: Alignment.topLeft,
              child: InputRegion(
                interactions: [
                  SecondaryClickInteraction(
                    onClick: (t, at) => log.add('cell $at'),
                  ),
                ],
                focusNode: inner,
                child: const SizedBox(width: 50, height: 30),
              ),
            ),
          ),
        ),
      ),
    );
    inner.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    outer.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    expect(log, ['cell Offset(25.0, 15.0)', 'row Offset(100.0, 30.0)']);
  });

  testWidgets('an app maps its own key to the intent and overrides it with '
      'Actions', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final clicks = <Offset>[];
    var overridden = 0;
    Widget region({bool override = false}) => _app(
      Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.keyM): ContextMenuIntent(),
        },
        child: Actions(
          actions: {
            if (override)
              ContextMenuIntent: CallbackAction<ContextMenuIntent>(
                onInvoke: (_) => overridden++,
              ),
          },
          child: InputRegion(
            interactions: [
              SecondaryClickInteraction(onClick: (t, at) => clicks.add(at)),
            ],
            focusNode: focus,
            child: const SizedBox(width: 80, height: 40),
          ),
        ),
      ),
    );
    await tester.pumpWidget(region());
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    expect(clicks, [const Offset(40, 20)]);
    await tester.pumpWidget(region(override: true));
    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    expect((clicks.length, overridden), (1, 1));
  });

  testWidgets('a focused zone opens its context menu at its own centre', (
    tester,
  ) async {
    final zones = InputZonesController<int>();
    addTearDown(zones.dispose);
    final frames = ValueNotifier(0);
    addTearDown(frames.dispose);
    final clicks = <(int, Offset)>[];
    InputZone<int> zone(int id) => InputZone(
      id: id,
      interactions: [
        PressInteraction(),
        SecondaryClickInteraction(onClick: (t, at) => clicks.add((id, at))),
      ],
    );
    await tester.pumpWidget(
      _app(
        InputZones<int>(
          zones: [zone(0), zone(1)],
          frameOf: (id) => InputZoneFrame(Rect.fromLTWH(id * 60.0, 0, 50, 30)),
          frames: frames,
          controller: zones,
          child: const SizedBox(width: 200, height: 40),
        ),
      ),
    );
    zones.requestFocus(1);
    await tester.pump();
    await _shiftF10(tester);
    expect(clicks, [(1, const Offset(25, 15))]);
  });
}

import 'package:apple_liquid_glass/raw.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/motion.dart';

const _frame = Duration(milliseconds: 16);

final class _Row {
  int pressed = 0;
  int info = 0;
  Set<WidgetState> states = const {};
  Set<WidgetState> infoStates = const {};
  ValueListenable<double>? highlight;
}

Widget _app(Widget child) => WidgetsApp(
  color: const Color(0xFF000000),
  builder: (context, _) => FocusScope(
    autofocus: true,
    child: Align(
      alignment: Alignment.topCenter,
      child: SizedBox(width: 402, child: child),
    ),
  ),
);

Widget _row(
  _Row log, {
  bool enabled = true,
  bool pressable = true,
  bool info = false,
  bool infoPressable = true,
  bool selected = false,
}) => RawGlassListRow(
  enabled: enabled,
  selected: selected,
  onPressed: pressable ? () => log.pressed++ : null,
  onInfoPressed: infoPressable ? () => log.info++ : null,
  infoCenterInset: 31,
  infoBuilder: info
      ? (context, details) {
          log.infoStates = details.states;
          return const SizedBox.square(dimension: 22);
        }
      : null,
  builder: (context, details) {
    log.states = details.states;
    log.highlight = details.highlight;
    return const SizedBox(height: 53, child: Text('Wi-Fi'));
  },
);

Future<void> _tab(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.pump();
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(_frame);
  }
}

Finder get _info => find.bySemanticsLabel('More info');

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('a tap presses the row and its highlight shows and fades', (
    tester,
  ) async {
    final log = _Row();
    await tester.pumpWidget(_app(_row(log)));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Wi-Fi')),
    );
    await tester.pump(_frame);
    expect(log.highlight!.value, 1);
    expect(log.states, contains(WidgetState.pressed));
    await gesture.up();
    await _settle(tester);
    expect(log.pressed, 1);
    expect(log.highlight!.value, 0);
    expect(log.states, isNot(contains(WidgetState.pressed)));
  });

  testWidgets('Space and Enter press the focused row', (tester) async {
    final log = _Row();
    await tester.pumpWidget(_app(_row(log)));
    await _tab(tester);
    expect(log.states, contains(WidgetState.focused));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(log.pressed, 2);
    await _settle(tester);
  });

  testWidgets('a disabled row takes no press and no focus and clears its '
      'highlight', (tester) async {
    final log = _Row();
    await tester.pumpWidget(_app(_row(log)));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Wi-Fi')),
    );
    await tester.pump(_frame);
    expect(log.highlight!.value, 1);
    await tester.pumpWidget(_app(_row(log, enabled: false)));
    expect(log.highlight!.value, 0);
    expect(log.states, contains(WidgetState.disabled));
    expect(log.states, isNot(contains(WidgetState.pressed)));
    await gesture.up();
    await tester.tap(find.text('Wi-Fi'), warnIfMissed: false);
    await _tab(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await _settle(tester);
    expect(log.pressed, 0);
    expect(log.states, isNot(contains(WidgetState.focused)));
  });

  testWidgets('a row without onPressed is inert and reads as text', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final log = _Row();
    await tester.pumpWidget(_app(_row(log, pressable: false, selected: true)));
    expect(log.states, contains(WidgetState.disabled));
    expect(
      tester.getSemantics(find.text('Wi-Fi')),
      matchesSemantics(
        label: 'Wi-Fi',
        hasSelectedState: true,
        isSelected: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('the info button takes its taps apart from the row, in 44 '
      'points, and is a Tab stop of its own', (tester) async {
    final log = _Row();
    await tester.pumpWidget(_app(_row(log, info: true)));
    final row = tester.getRect(find.byType(RawGlassListRow));
    final center = tester.getCenter(_info);
    expect(center, Offset(row.right - 31, row.center.dy));
    await tester.tap(_info);
    await _settle(tester);
    expect((log.pressed, log.info), (0, 1));
    await tester.tapAt(center + const Offset(0, 20));
    await _settle(tester);
    expect((log.pressed, log.info), (0, 2));
    await tester.tapAt(row.topLeft + const Offset(40, 26));
    await _settle(tester);
    expect((log.pressed, log.info), (1, 2));

    await _tab(tester);
    await _tab(tester);
    expect(log.infoStates, contains(WidgetState.focused));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect((log.pressed, log.info), (1, 3));
    await _settle(tester);
  });

  testWidgets('without onInfoPressed or with the row disabled the info '
      'button is disabled', (tester) async {
    final log = _Row();
    await tester.pumpWidget(_app(_row(log, info: true, infoPressable: false)));
    expect(log.infoStates, contains(WidgetState.disabled));
    await tester.pumpWidget(_app(_row(log, info: true, enabled: false)));
    expect(log.infoStates, contains(WidgetState.disabled));
    await tester.tap(_info, warnIfMissed: false);
    await _settle(tester);
    expect(log.info, 0);
  });

  testWidgets('screen readers see the row and the info button as two '
      'buttons with their own actions', (tester) async {
    final semantics = tester.ensureSemantics();
    final log = _Row();
    await tester.pumpWidget(_app(_row(log, info: true, selected: true)));
    expect(
      tester.getSemantics(find.text('Wi-Fi')),
      matchesSemantics(
        label: 'Wi-Fi',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
        hasSelectedState: true,
        isSelected: true,
      ),
    );
    expect(
      tester.getSemantics(_info),
      matchesSemantics(
        label: 'More info',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    tester.semantics.tap(find.semantics.byLabel('More info'));
    tester.semantics.tap(find.semantics.byLabel('Wi-Fi'));
    await _settle(tester);
    expect((log.pressed, log.info), (1, 1));
    semantics.dispose();
  });
}

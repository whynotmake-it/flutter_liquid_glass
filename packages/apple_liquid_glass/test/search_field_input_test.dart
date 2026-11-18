import 'dart:ui' show SemanticsAction, Tristate;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'conformance/harness.dart' show globalRect;
import 'presentations/support.dart' show focusedLabel, perform;

const _frame = Duration(milliseconds: 16);

Widget _app(Widget child) => GlassScope(
  renderer: const FlatGlassRenderer(),
  child: WidgetsApp(
    color: const Color(0xFFFFFFFF),
    pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
      settings: settings,
      pageBuilder: (context, _, _) => builder(context),
    ),
    home: Center(child: SizedBox(width: 340, child: child)),
  ),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(_frame);
  }
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('the clear button is a labelled button with a 44 point '
      'target that assistive technology taps', (tester) async {
    final controller = TextEditingController(text: 'glass');
    addTearDown(controller.dispose);
    final changes = <String>[];
    await tester.pumpWidget(
      _app(GlassSearchField(controller: controller, onChanged: changes.add)),
    );
    final clear = find.bySemanticsLabel('Clear text');
    expect(clear, findsOneWidget);
    final data = tester.getSemantics(clear).getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.flagsCollection.isEnabled, Tristate.isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    final rect = globalRect(tester, tester.getSemantics(clear));
    expect(rect.width, greaterThanOrEqualTo(44));
    expect(rect.height, greaterThanOrEqualTo(44));

    perform(tester, clear, SemanticsAction.tap);
    await _settle(tester);
    expect(controller.text, isEmpty);
    expect(changes, ['']);
  });

  testWidgets('a tap at the edge of the clear button target clears', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'glass');
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(GlassSearchField(controller: controller)));
    final clear = find.bySemanticsLabel('Clear text');
    final glyph = tester.getRect(clear);
    expect(glyph.height, lessThan(44));
    await tester.tapAt(Offset(glyph.center.dx, glyph.center.dy + 20));
    await _settle(tester);
    expect(controller.text, isEmpty);
  });

  testWidgets('Tab reaches the clear button', (tester) async {
    final controller = TextEditingController(text: 'glass');
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(GlassSearchField(controller: controller)));
    String? reached;
    for (var i = 0; i < 4 && reached != 'Clear text'; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      reached = focusedLabel(tester);
    }
    expect(reached, 'Clear text');
  });

  testWidgets('Space and Enter on the focused clear button clear the field', (
    tester,
  ) async {
    for (final key in [LogicalKeyboardKey.space, LogicalKeyboardKey.enter]) {
      final controller = TextEditingController(text: 'glass');
      addTearDown(controller.dispose);
      final changes = <String>[];
      await tester.pumpWidget(
        _app(
          GlassSearchField(
            key: ValueKey(key),
            controller: controller,
            onChanged: changes.add,
          ),
        ),
      );
      String? reached;
      for (var i = 0; i < 4 && reached != 'Clear text'; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        reached = focusedLabel(tester);
      }
      expect(reached, 'Clear text');
      await tester.sendKeyEvent(key);
      await _settle(tester);
      expect(controller.text, isEmpty, reason: '$key');
      expect(changes, [''], reason: '$key');
    }
  });

  testWidgets('the app passes the states the field writes to', (
    tester,
  ) async {
    final states = WidgetStatesController();
    addTearDown(states.dispose);
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      _app(GlassSearchField(statesController: states, focusNode: focus)),
    );
    expect(states.value, isNot(contains(WidgetState.focused)));
    focus.requestFocus();
    await tester.pump();
    expect(states.value, contains(WidgetState.focused));
    await tester.pumpWidget(
      _app(
        GlassSearchField(
          statesController: states,
          focusNode: focus,
          enabled: false,
        ),
      ),
    );
    expect(states.value, contains(WidgetState.disabled));
  });

  testWidgets('the text area shows the text cursor, the clear button its '
      'own', (tester) async {
    final controller = TextEditingController(text: 'glass');
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(GlassSearchField(controller: controller)));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(EditableText)));
    await tester.pump();
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      SystemMouseCursors.text,
    );
    await mouse.moveTo(tester.getCenter(find.bySemanticsLabel('Clear text')));
    await tester.pump();
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      isNot(SystemMouseCursors.text),
    );
  });
}

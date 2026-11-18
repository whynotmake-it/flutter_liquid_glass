import 'dart:ui' show Tristate;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = Duration(milliseconds: 16);

Widget _app(
  List<String> log, {
  Map<ShortcutActivator, Intent>? shortcuts,
  TextDirection direction = TextDirection.ltr,
}) => WidgetsApp(
  color: const Color(0xFF000000),
  shortcuts: shortcuts,
  builder: (context, _) => Directionality(
    textDirection: direction,
    child: GlassScope(
      renderer: const FlatGlassRenderer(),
      child: FocusScope(
        autofocus: true,
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 402,
            child: GlassSwipeActions(
              trailing: [
                GlassSwipeAction(
                  title: 'Delete',
                  destructive: true,
                  onPressed: () => log.add('Delete'),
                ),
                GlassSwipeAction(
                  title: 'Flag',
                  onPressed: () => log.add('Flag'),
                ),
              ],
              child: const GlassListRow(title: Text('Message')),
            ),
          ),
        ),
      ),
    ),
  ),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(_frame);
  }
}

Future<void> _open(WidgetTester tester) async {
  await tester.drag(
    find.text('Message'),
    const Offset(-200, 0),
    touchSlopX: 0,
  );
  await _settle(tester);
}

Future<String?> _tab(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.pump();
  return _focused(tester);
}

String? _focused(WidgetTester tester) {
  final node =
      tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode;
  String? found;
  bool visit(SemanticsNode n) {
    final data = n.getSemanticsData();
    if (data.flagsCollection.isFocused == Tristate.isTrue) {
      found = data.label;
      return false;
    }
    n.visitChildren(visit);
    return found == null;
  }

  if (node != null) visit(node);
  return found;
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('a closed row is no Tab stop; an open row stops on each '
      'action, which shows its focus, and Space presses the focused one', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final log = <String>[];
    await tester.pumpWidget(_app(log));
    expect(await _tab(tester), isNull);
    expect(await _tab(tester), isNull);

    await _open(tester);
    final stops = {await _tab(tester), await _tab(tester)};
    expect(stops, {'Delete', 'Flag'});
    final focused = _focused(tester)!;
    final ring = tester.widget<GlassHighlightPaint>(
      find.ancestor(
        of: find.text(focused),
        matching: find.byType(GlassHighlightPaint),
      ),
    );
    expect(ring.states!.value, contains(WidgetState.focused));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await _settle(tester);
    expect(log, [focused]);
    expect(await _tab(tester), isNull);
    semantics.dispose();
  });

  testWidgets("an app's own activation key presses the focused action", (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final log = <String>[];
    await tester.pumpWidget(
      _app(
        log,
        shortcuts: {
          ...WidgetsApp.defaultShortcuts,
          const SingleActivator(LogicalKeyboardKey.space):
              const DoNothingAndStopPropagationIntent(),
          const SingleActivator(LogicalKeyboardKey.keyD):
              const ActivateIntent(),
        },
      ),
    );
    await _open(tester);
    final focused = await _tab(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(log, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await _settle(tester);
    expect(log, [focused]);
    semantics.dispose();
  });

  testWidgets('an open row reads its actions as buttons where they are '
      'drawn and keeps them as custom actions; a closed row reads none', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app([]));
    expect(find.bySemanticsLabel('Delete'), findsNothing);
    expect(find.bySemanticsLabel('Flag'), findsNothing);

    await _open(tester);
    for (final label in ['Delete', 'Flag']) {
      final node = tester.getSemantics(find.bySemanticsLabel(label));
      final data = node.getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      final rect = tester.getRect(find.text(label));
      final drawn = node.transform == null
          ? node.rect
          : MatrixUtils.transformRect(node.transform!, node.rect);
      expect(drawn.width, greaterThanOrEqualTo(rect.width));
    }
    final row = tester.getSemantics(find.byType(GlassSwipeActions));
    expect(row.getSemanticsData().customSemanticsActionIds, hasLength(2));
    semantics.dispose();
  });

  testWidgets('a drag that starts on an action moves the row and presses '
      'nothing; a tap presses it', (tester) async {
    final log = <String>[];
    await tester.pumpWidget(_app(log));
    final closed = tester.getTopLeft(find.text('Message')).dx;
    await _open(tester);
    await tester.drag(find.text('Flag'), const Offset(200, 0), touchSlopX: 0);
    await _settle(tester);
    expect(log, isEmpty);
    expect(tester.getTopLeft(find.text('Message')).dx, closeTo(closed, 0.5));

    await _open(tester);
    await tester.tap(find.text('Flag'));
    await _settle(tester);
    expect(log, ['Flag']);
    expect(tester.getTopLeft(find.text('Message')).dx, closeTo(closed, 0.5));
  });

  testWidgets('right to left, the actions open on the left and take '
      'taps there', (tester) async {
    final log = <String>[];
    await tester.pumpWidget(_app(log, direction: TextDirection.rtl));
    await tester.drag(
      find.text('Message'),
      const Offset(200, 0),
      touchSlopX: 0,
    );
    await _settle(tester);
    final row = tester.getRect(find.byType(GlassSwipeActions));
    expect(tester.getCenter(find.text('Delete')).dx - row.left, lessThan(80));
    await tester.tap(find.text('Delete'));
    await _settle(tester);
    expect(log, ['Delete']);
  });
}

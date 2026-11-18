import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = Duration(milliseconds: 16);
const _spring = Spring.response(0.4);

class _Notes extends StatefulWidget {
  const _Notes({required this.notes, this.swipe = false});

  final List<String> notes;
  final bool swipe;

  @override
  State<_Notes> createState() => _NotesState();
}

class _NotesState extends State<_Notes> {
  late List<String> notes = widget.notes;
  final List<String> pressed = [];
  final List<String> actions = [];

  void change(List<String> next) => setState(() => notes = next);

  Widget _row(String note) {
    final row = GlassListRow(
      key: ValueKey(note),
      title: Text(note),
      onPressed: () => pressed.add(note),
    );
    if (!widget.swipe) return row;
    return GlassSwipeActions(
      trailing: [
        GlassSwipeAction(
          title: 'Delete',
          destructive: true,
          onPressed: () {
            actions.add('delete $note');
            withSpring(
              _spring,
              () => change([
                for (final other in notes)
                  if (other != note) other,
              ]),
            );
          },
        ),
        GlassSwipeAction(
          title: 'Flag',
          onPressed: () => actions.add('flag $note'),
        ),
      ],
      child: row,
    );
  }

  @override
  Widget build(BuildContext context) => MediaQuery(
    data: const MediaQueryData(),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: GlassScope(
        renderer: const FlatGlassRenderer(),
        child: CustomScrollView(
          slivers: [
            GlassSliverListSection(
              ids: notes,
              itemCount: notes.length,
              itemBuilder: (context, i) => _row(notes[i]),
            ),
          ],
        ),
      ),
    ),
  );
}

double _top(WidgetTester tester, String note) =>
    tester.getTopLeft(find.byKey(ValueKey(note))).dy;

double _left(WidgetTester tester, String note) =>
    tester.getTopLeft(find.byKey(ValueKey(note))).dx;

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(_frame);
  }
}

void main() {
  testWidgets('a row inserted inside withSpring pushes the rows below it '
      'down on a spring', (tester) async {
    await tester.pumpWidget(const _Notes(notes: ['a', 'b', 'c']));
    final list = tester.state<_NotesState>(find.byType(_Notes));
    final b = _top(tester, 'b');
    final pitch = b - _top(tester, 'a');

    withSpring(_spring, () => list.change(['a', 'x', 'b', 'c']));
    await tester.pump(_frame);
    expect(_top(tester, 'b'), closeTo(b, 1));
    for (var i = 0; i < 6; i++) {
      await tester.pump(_frame);
    }
    expect(_top(tester, 'b'), greaterThan(b + 1));
    expect(_top(tester, 'b'), lessThan(b + pitch - 1));
    await _settle(tester);
    expect(_top(tester, 'b'), closeTo(b + pitch, 0.5));
  });

  testWidgets('a row deleted inside withSpring stays drawn while it fades '
      'and the rows below it slide up', (tester) async {
    await tester.pumpWidget(const _Notes(notes: ['a', 'b', 'c']));
    final list = tester.state<_NotesState>(find.byType(_Notes));
    final b = _top(tester, 'b');
    final c = _top(tester, 'c');

    withSpring(_spring, () => list.change(['a', 'c']));
    await tester.pump(_frame);
    expect(find.text('b'), findsOneWidget);
    expect(_top(tester, 'c'), closeTo(c, 1));
    await _settle(tester);
    expect(find.text('b'), findsNothing);
    expect(_top(tester, 'c'), closeTo(b, 0.5));
  });

  testWidgets('a swipe opens the trailing actions; a tap on an action '
      'performs it and closes the row', (tester) async {
    await tester.pumpWidget(const _Notes(notes: ['a', 'b'], swipe: true));
    final list = tester.state<_NotesState>(find.byType(_Notes));
    final left = _left(tester, 'a');
    expect(find.text('Delete'), findsNothing);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('a'))),
    );
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(-12, 0));
      await tester.pump(_frame);
    }
    expect(_left(tester, 'a'), lessThan(left - 80));
    await gesture.up();
    await _settle(tester);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Flag'), findsOneWidget);
    final open = _left(tester, 'a');
    expect(open, lessThan(left - 2 * GlassSwipeActions.minActionWidth + 1));

    await tester.tap(find.text('Flag'));
    await _settle(tester);
    expect(list.actions, ['flag a']);
    expect(list.pressed, isEmpty);
    expect(_left(tester, 'a'), closeTo(left, 0.5));
  });

  testWidgets('a tap on an open row closes it without pressing it', (
    tester,
  ) async {
    await tester.pumpWidget(const _Notes(notes: ['a', 'b'], swipe: true));
    final list = tester.state<_NotesState>(find.byType(_Notes));
    final left = _left(tester, 'a');
    await tester.drag(
      find.byKey(const ValueKey('a')),
      const Offset(-200, 0),
      touchSlopX: 0,
    );
    await _settle(tester);
    expect(_left(tester, 'a'), lessThan(left - 100));

    final top = tester.getTopLeft(find.byType(GlassSwipeActions).first).dy;
    await tester.tapAt(Offset(left + 30, top + 20));
    await _settle(tester);
    expect(_left(tester, 'a'), closeTo(left, 0.5));
    expect(list.pressed, isEmpty);
  });

  testWidgets('a full swipe performs the first action, which deletes the '
      'row', (tester) async {
    await tester.pumpWidget(const _Notes(notes: ['a', 'b'], swipe: true));
    final list = tester.state<_NotesState>(find.byType(_Notes));
    final a = _top(tester, 'a');
    await tester.drag(
      find.byKey(const ValueKey('a')),
      const Offset(-600, 0),
      touchSlopX: 0,
    );
    await _settle(tester);
    expect(list.actions, ['delete a']);
    expect(find.text('a'), findsNothing);
    expect(_top(tester, 'b'), closeTo(a, 0.5));
  });

  testWidgets('one row of a list is open at a time', (tester) async {
    await tester.pumpWidget(const _Notes(notes: ['a', 'b'], swipe: true));
    final left = _left(tester, 'a');
    await tester.drag(
      find.byKey(const ValueKey('a')),
      const Offset(-200, 0),
      touchSlopX: 0,
    );
    await _settle(tester);
    await tester.drag(
      find.byKey(const ValueKey('b')),
      const Offset(-200, 0),
      touchSlopX: 0,
    );
    await _settle(tester);
    expect(_left(tester, 'a'), closeTo(left, 0.5));
    expect(_left(tester, 'b'), lessThan(left - 100));
  });

  testWidgets('accessibility offers the actions as custom actions', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(const _Notes(notes: ['a'], swipe: true));
    final list = tester.state<_NotesState>(find.byType(_Notes));
    final node = tester.getSemantics(find.byType(GlassSwipeActions));
    final data = node.getSemanticsData();
    expect(data.customSemanticsActionIds, hasLength(2));
    final flag = CustomSemanticsAction.getIdentifier(
      const CustomSemanticsAction(label: 'Flag'),
    );
    tester.binding.performSemanticsAction(
      SemanticsActionEvent(
        type: SemanticsAction.customAction,
        viewId: tester.view.viewId,
        nodeId: node.id,
        arguments: flag,
      ),
    );
    expect(list.actions, ['flag a']);
    semantics.dispose();
  });
}

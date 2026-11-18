import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

const _spring = Spring.response(0.4);
const _frame = Duration(milliseconds: 16);

class _List extends StatefulWidget {
  const _List({required this.ids, this.controller});

  final List<String> ids;
  final ScrollController? controller;

  @override
  State<_List> createState() => _ListState();
}

class _ListState extends State<_List> {
  late List<String> ids = widget.ids;
  final List<String> taps = [];

  void change(List<String> next) => setState(() => ids = next);

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 100,
        height: 100,
        child: CustomScrollView(
          controller: widget.controller,
          slivers: [
            SliverMotionList(
              ids: ids,
              itemBuilder: (context, id) => GestureDetector(
                key: ValueKey(id as String),
                behavior: HitTestBehavior.opaque,
                onTap: () => taps.add(id),
                child: Semantics(
                  label: id,
                  child: const SizedBox(height: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

double _top(WidgetTester tester, String id) =>
    tester.getTopLeft(find.byKey(ValueKey(id))).dy;

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 90; i++) {
    await tester.pump(_frame);
  }
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('a delete in view leaves a ghost of no extent where the row '
      'was drawn while the rows after it slide up', (tester) async {
    await tester.pumpWidget(const _List(ids: ['a', 'b', 'c']));
    final list = tester.state<_ListState>(find.byType(_List));
    expect(_top(tester, 'c'), 40);

    withSpring(_spring, () => list.change(['a', 'c']));
    await tester.pump(_frame);
    expect(find.byKey(const ValueKey('b')), findsOneWidget);
    expect(_top(tester, 'b'), 20);
    expect(_top(tester, 'c'), 40);

    final tops = <double>[];
    for (var i = 0; i < 6; i++) {
      await tester.pump(_frame);
      tops.add(_top(tester, 'c'));
    }
    expect(tops.first, lessThan(40));
    expect(tops.last, lessThan(tops.first));
    expect(tops.last, greaterThan(20));

    await _settle(tester);
    expect(_top(tester, 'c'), 20);
    expect(find.byKey(const ValueKey('b')), findsNothing);
  });

  testWidgets('an insert in view slides the rows after it down', (
    tester,
  ) async {
    await tester.pumpWidget(const _List(ids: ['a', 'b']));
    final list = tester.state<_ListState>(find.byType(_List));

    withSpring(_spring, () => list.change(['a', 'x', 'b']));
    await tester.pump(_frame);
    expect(_top(tester, 'x'), 20);
    expect(_top(tester, 'b'), 20);
    await tester.pump(_frame);
    await tester.pump(_frame);
    expect(_top(tester, 'b'), greaterThan(20));
    expect(_top(tester, 'b'), lessThan(40));
    await _settle(tester);
    expect(_top(tester, 'b'), 40);
  });

  testWidgets('a ghost is not hit: the row laid out under it is', (
    tester,
  ) async {
    await tester.pumpWidget(const _List(ids: ['a', 'b', 'c']));
    final list = tester.state<_ListState>(find.byType(_List));
    withSpring(_spring, () => list.change(['a', 'c']));
    await tester.pump(_frame);
    await tester.tapAt(const Offset(50, 30));
    expect(list.taps, ['c']);
  });

  testWidgets('a ghost is not read; the rows are read once they rest', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(const _List(ids: ['a', 'b', 'c']));
    final list = tester.state<_ListState>(find.byType(_List));
    withSpring(_spring, () => list.change(['a', 'c']));
    await tester.pump(_frame);
    expect(find.byKey(const ValueKey('b')), findsOneWidget);
    expect(find.bySemanticsLabel('b'), findsNothing);
    await _settle(tester);
    expect(find.bySemanticsLabel('a'), findsOneWidget);
    expect(find.bySemanticsLabel('c'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a scroll during a change bends nothing, and rows scrolled out '
      'and back are placed without motion', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _List(
        ids: [for (var i = 0; i < 40; i++) '$i'],
        controller: controller,
      ),
    );
    final list = tester.state<_ListState>(find.byType(_List));
    withSpring(_spring, () => list.change([for (var i = 1; i < 40; i++) '$i']));
    await tester.pump(_frame);
    await tester.pump(_frame);
    final gap = _top(tester, '2') - _top(tester, '1');
    controller.jumpTo(10);
    await tester.pump(_frame);
    expect(_top(tester, '2') - _top(tester, '1'), closeTo(gap, 2));
    await _settle(tester);

    controller.jumpTo(400);
    await tester.pump(_frame);
    controller.jumpTo(0);
    await tester.pump(_frame);
    expect(_top(tester, '1'), 0);
    expect(_top(tester, '2'), 20);
  });

  testWidgets('a delete out of view moves nothing in view', (tester) async {
    await tester.pumpWidget(_List(ids: [for (var i = 0; i < 40; i++) '$i']));
    final list = tester.state<_ListState>(find.byType(_List));
    withSpring(
      _spring,
      () => list.change([
        for (var i = 0; i < 40; i++)
          if (i != 30) '$i',
      ]),
    );
    await tester.pump(_frame);
    await tester.pump(_frame);
    expect(_top(tester, '2'), 40);
    expect(_top(tester, '3'), 60);
  });
}

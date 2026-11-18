import 'package:apple_liquid_glass/raw.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/motion.dart';

const _frame = Duration(milliseconds: 16);
const _width = 400.0;
const _actionWidth = 80.0;

Widget _row(String name, List<String> log) => RawGlassSwipeActions(
  actionLabels: const ['A', 'B'],
  onAction: (i) => log.add('$name action $i'),
  actionBuilder: (context, details) => SizedBox(
    width: _actionWidth,
    child: Text('$name ${details.index}'),
  ),
  child: GestureDetector(
    onTap: () => log.add('$name content'),
    child: SizedBox(
      width: double.infinity,
      height: 44,
      child: Text(name),
    ),
  ),
);

Widget _app(
  Widget child, {
  TextDirection direction = TextDirection.ltr,
}) => WidgetsApp(
  color: const Color(0xFF000000),
  builder: (context, _) => Directionality(
    textDirection: direction,
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: _width, height: 400, child: child),
    ),
  ),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(_frame);
  }
}

Future<void> _swipe(WidgetTester tester, String name, double dx) async {
  await tester.drag(find.text(name), Offset(dx, 0), touchSlopX: 0);
  await _settle(tester);
}

double _left(WidgetTester tester, String name) =>
    tester.getTopLeft(find.text(name)).dx;

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('a drag reveals the actions against the trailing edge', (
    tester,
  ) async {
    final log = <String>[];
    await tester.pumpWidget(_app(_row('row', log)));
    expect(find.text('row 0'), findsNothing);

    await _swipe(tester, 'row', -120);
    expect(_left(tester, 'row'), closeTo(-2 * _actionWidth, 0.5));
    expect(_left(tester, 'row 0'), closeTo(_width - _actionWidth, 0.5));
    expect(_left(tester, 'row 1'), closeTo(_width - 2 * _actionWidth, 0.5));
    expect(log, isEmpty);
  });

  testWidgets('a full swipe performs the first action', (tester) async {
    final log = <String>[];
    await tester.pumpWidget(_app(_row('row', log)));
    await _swipe(tester, 'row', -350);
    expect(log, ['row action 0']);
  });

  testWidgets('a tap on the open row closes it and the content does not '
      'hear it; a tap on an action presses it', (tester) async {
    final log = <String>[];
    await tester.pumpWidget(_app(_row('row', log)));
    await _swipe(tester, 'row', -120);

    await tester.tapAt(const Offset(40, 22));
    await _settle(tester);
    expect(_left(tester, 'row'), closeTo(0, 0.5));
    expect(log, isEmpty);

    await tester.tap(find.text('row'));
    await _settle(tester);
    expect(log, ['row content']);

    log.clear();
    await _swipe(tester, 'row', -120);
    await tester.tap(find.text('row 1'));
    await _settle(tester);
    expect(log, ['row action 1']);
    expect(_left(tester, 'row'), closeTo(0, 0.5));
  });

  testWidgets('a row of a group that starts to open closes the open one', (
    tester,
  ) async {
    final log = <String>[];
    await tester.pumpWidget(
      _app(
        SwipeGroup(
          child: Column(children: [_row('first', log), _row('second', log)]),
        ),
      ),
    );
    await _swipe(tester, 'first', -120);
    expect(_left(tester, 'first'), closeTo(-2 * _actionWidth, 0.5));

    await _swipe(tester, 'second', -120);
    expect(_left(tester, 'second'), closeTo(-2 * _actionWidth, 0.5));
    expect(_left(tester, 'first'), closeTo(0, 0.5));
  });

  testWidgets('a scroll closes the open row', (tester) async {
    final log = <String>[];
    await tester.pumpWidget(
      _app(
        ListView(
          children: [
            _row('row', log),
            for (var i = 0; i < 20; i++)
              SizedBox(height: 44, child: Text('$i')),
          ],
        ),
      ),
    );
    await _swipe(tester, 'row', -120);
    expect(_left(tester, 'row'), closeTo(-2 * _actionWidth, 0.5));

    await tester.drag(find.text('3'), const Offset(0, -30));
    await _settle(tester);
    expect(_left(tester, 'row'), closeTo(0, 0.5));
  });

  testWidgets('right to left, the row swipes the other way and the actions '
      'open on the left', (tester) async {
    final log = <String>[];
    await tester.pumpWidget(
      _app(_row('row', log), direction: TextDirection.rtl),
    );
    final closed = tester.getTopRight(find.text('row')).dx;
    await _swipe(tester, 'row', 120);
    expect(
      tester.getTopRight(find.text('row')).dx,
      closeTo(closed + 2 * _actionWidth, 0.5),
    );
    expect(tester.getTopLeft(find.text('row 0')).dx, closeTo(0, 0.5));
    expect(
      tester.getTopLeft(find.text('row 1')).dx,
      closeTo(_actionWidth, 0.5),
    );

    await tester.tap(find.text('row 0'));
    await _settle(tester);
    expect(log, ['row action 0']);
  });
}

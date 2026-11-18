import 'package:apple_liquid_glass/raw.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/motion.dart';

const double _row = 40;

Widget _app(Widget child) => WidgetsApp(
  color: const Color(0xFF000000),
  builder: (context, _) => Center(
    child: SizedBox(width: 100, height: 200, child: child),
  ),
);

/// A wheel of ten rows whose app takes each value it reports, or keeps
/// [start] when [follows] is false.
class _Host extends StatefulWidget {
  const _Host({
    required this.reports,
    this.start = 0,
    this.follows = true,
    this.focusNode,
  });

  final List<int> reports;
  final int start;
  final bool follows;
  final FocusNode? focusNode;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late int _value = widget.start;

  @override
  Widget build(BuildContext context) => RawGlassWheel(
    count: 10,
    value: _value,
    looping: false,
    itemExtent: _row,
    focusNode: widget.focusNode,
    semanticLabel: 'Hour',
    rowLabel: (row) => '$row',
    onChanged: (row) {
      widget.reports.add(row);
      if (widget.follows) setState(() => _value = row);
    },
    rowBuilder: (context, row) => Text('$row'),
  );
}

int _shownRow(WidgetTester tester) {
  final view = tester.widget<ListWheelScrollView>(
    find.byType(ListWheelScrollView),
  );
  return (view.controller! as FixedExtentScrollController).selectedItem;
}

List<String> _recordHaptics(WidgetTester tester) {
  final haptics = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        haptics.add('${call.arguments}');
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
  return haptics;
}

Future<void> _drag(WidgetTester tester, int rows) async {
  await tester.timedDragFrom(
    tester.getCenter(find.byType(RawGlassWheel)),
    Offset(0, -rows * _row),
    const Duration(seconds: 1),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('a drag settles on a row and reports each row once', (
    tester,
  ) async {
    final reports = <int>[];
    await tester.pumpWidget(_app(_Host(reports: reports)));
    await _drag(tester, 2);
    expect(reports, [1, 2]);
    expect(_shownRow(tester), 2);
  });

  testWidgets('each row crossed asks for a selection haptic', (tester) async {
    final haptics = _recordHaptics(tester);
    final reports = <int>[];
    await tester.pumpWidget(_app(_Host(reports: reports)));
    await _drag(tester, 3);
    expect(reports, [1, 2, 3]);
    expect(haptics, List.filled(3, 'HapticFeedbackType.selectionClick'));
  });

  testWidgets('keys step the value', (tester) async {
    final reports = <int>[];
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      _app(_Host(reports: reports, start: 5, focusNode: focus)),
    );
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(reports, [6]);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(reports, [6, 5]);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pumpAndSettle();
    expect(reports.last, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();
    expect(reports.last, 9);
    expect(_shownRow(tester), 9);
  });

  testWidgets('screen readers increase and decrease the value', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final reports = <int>[];
    await tester.pumpWidget(_app(_Host(reports: reports, start: 3)));
    final wheel = find.bySemanticsLabel('Hour');
    final data = tester.getSemantics(wheel).getSemanticsData();
    expect(data.value, '3');
    expect(data.increasedValue, '4');
    expect(data.decreasedValue, '2');
    expect(data.hasAction(SemanticsAction.increase), isTrue);
    expect(data.hasAction(SemanticsAction.decrease), isTrue);
    tester.semantics.increase(find.semantics.byLabel('Hour'));
    await tester.pumpAndSettle();
    expect(reports, [4]);
    tester.semantics.decrease(find.semantics.byLabel('Hour'));
    await tester.pumpAndSettle();
    expect(reports, [4, 3]);
    expect(tester.getSemantics(wheel).value, '3');
    handle.dispose();
  });

  testWidgets('a wheel whose app keeps its value turns back to it', (
    tester,
  ) async {
    final reports = <int>[];
    await tester.pumpWidget(_app(_Host(reports: reports, follows: false)));
    await _drag(tester, 2);
    expect(reports, [1, 2]);
    expect(_shownRow(tester), 0);
  });
}

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

const _spring = Spring.response(0.4);
const _frame = Duration(milliseconds: 16);

Widget _row(String id, {VoidCallback? onTap}) => GestureDetector(
  key: ValueKey(id),
  behavior: HitTestBehavior.opaque,
  onTap: onTap,
  child: const SizedBox(width: 100, height: 20),
);

class _Rows extends StatefulWidget {
  const _Rows({required this.ids});

  final List<String> ids;

  @override
  State<_Rows> createState() => _RowsState();
}

class _RowsState extends State<_Rows> {
  late List<String> ids = widget.ids;
  final List<String> taps = [];

  void change(List<String> next) => setState(() => ids = next);

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: MotionLayout(
        layoutBuilder: (context, children) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
        children: [for (final id in ids) _row(id, onTap: () => taps.add(id))],
      ),
    ),
  );
}

double _top(WidgetTester tester, String id) =>
    tester.getTopLeft(find.byKey(ValueKey(id))).dy;

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('a removal under withSpring starts where the rows were drawn '
      'and slides without building', (tester) async {
    await tester.pumpWidget(
      const _Rows(ids: ['a', 'b', 'c']),
    );
    final rows = tester.state<_RowsState>(find.byType(_Rows));
    expect(_top(tester, 'c'), 40);

    withSpring(_spring, () => rows.change(['a', 'c']));
    await tester.pump(_frame);
    expect(_top(tester, 'c'), 40);
    expect(find.byKey(const ValueKey('b')), findsOneWidget);

    final rebuilt = <Widget>[];
    debugOnRebuildDirtyWidget = (element, _) => rebuilt.add(element.widget);
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    final tops = <double>[];
    for (var i = 0; i < 8; i++) {
      await tester.pump(_frame);
      tops.add(_top(tester, 'c'));
    }
    debugOnRebuildDirtyWidget = null;
    expect(rebuilt, isEmpty);
    expect(tops.first, lessThan(40));
    expect(tops.last, lessThan(tops.first));
    expect(tops.last, greaterThan(20));

    await tester.pumpAndSettle();
    expect(_top(tester, 'c'), 20);
    expect(find.byKey(const ValueKey('b')), findsNothing);
  });

  testWidgets('withoutAnimation stops a slide in flight', (tester) async {
    await tester.pumpWidget(const _Rows(ids: ['a', 'b', 'c']));
    final rows = tester.state<_RowsState>(find.byType(_Rows));
    withSpring(_spring, () => rows.change(['c', 'b', 'a']));
    await tester.pump(_frame);
    await tester.pump(_frame);
    expect(_top(tester, 'c'), greaterThan(0));
    withoutAnimation(() => rows.change(['b', 'c', 'a']));
    await tester.pump(_frame);
    expect(_top(tester, 'c'), 20);
    expect(_top(tester, 'b'), 0);
  });

  testWidgets('a child brought back while it leaves comes back', (
    tester,
  ) async {
    await tester.pumpWidget(const _Rows(ids: ['a', 'b', 'c']));
    final rows = tester.state<_RowsState>(find.byType(_Rows));
    withSpring(_spring, () => rows.change(['a', 'c']));
    await tester.pump(_frame);
    await tester.pump(const Duration(milliseconds: 80));
    withSpring(_spring, () => rows.change(['a', 'b', 'c']));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('b')), findsOneWidget);
    expect(_top(tester, 'b'), 20);
    final item = MotionLayout.itemOf(
      tester.element(find.byKey(const ValueKey('b'))),
    )!;
    expect(item.value.opacity, 1);
  });

  testWidgets('a builder on itemOf rebuilds in the frame after a change', (
    tester,
  ) async {
    final heard = <double>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: MotionLayout(
            layoutBuilder: (context, children) => Column(children: children),
            children: [
              Builder(
                key: const ValueKey('a'),
                builder: (context) => ValueListenableBuilder<LayoutItem>(
                  valueListenable: MotionLayout.itemOf(context)!,
                  builder: (context, item, _) {
                    heard.add(item.rect.top);
                    return const SizedBox(width: 10, height: 20);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(_frame);
    expect(tester.takeException(), isNull);
    expect(heard.last, 0);
  });

  testWidgets('accessibility reads a slid child where it rests', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: _LabeledRows(ids: ['a', 'b']),
        ),
      ),
    );
    final rows = tester.state<_LabeledRowsState>(find.byType(_LabeledRows));
    withSpring(_spring, () => rows.change(['b', 'a']));
    await tester.pumpAndSettle();
    // The root semantics node is in physical pixels.
    SemanticsNode? node = tester.getSemantics(find.bySemanticsLabel('a'));
    var rect = node.rect;
    while (node != null) {
      final transform = node.transform;
      if (transform != null) rect = MatrixUtils.transformRect(transform, rect);
      node = node.parent;
    }
    expect(rect.top / tester.view.devicePixelRatio, 20);
    semantics.dispose();
  });

  testWidgets('a child that leaves without a spring goes in the next '
      'frame', (tester) async {
    await tester.pumpWidget(const _Rows(ids: ['a', 'b']));
    final rows = tester.state<_RowsState>(find.byType(_Rows));
    final layout = tester.widget<MotionLayout>(find.byType(MotionLayout));
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MotionLayout(
          planner: const _Snapping(),
          layoutBuilder: layout.layoutBuilder,
          children: [_row('a'), _row('b')],
        ),
      ),
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MotionLayout(
          planner: const _Snapping(),
          layoutBuilder: layout.layoutBuilder,
          children: [_row('a')],
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.pump(_frame);
    expect(find.byKey(const ValueKey('b')), findsNothing);
    expect(rows.mounted, isFalse);
  });

  testWidgets('outside a transaction a change jumps', (tester) async {
    await tester.pumpWidget(const _Rows(ids: ['a', 'b', 'c']));
    final rows = tester.state<_RowsState>(find.byType(_Rows));
    rows.change(['a', 'c']);
    await tester.pump(_frame);
    expect(_top(tester, 'c'), 20);
    expect(find.byKey(const ValueKey('b')), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a reordered row is hit where layout put it', (tester) async {
    await tester.pumpWidget(const _Rows(ids: ['a', 'b', 'c']));
    final rows = tester.state<_RowsState>(find.byType(_Rows));
    withSpring(_spring, () => rows.change(['c', 'b', 'a']));
    await tester.pump(_frame);
    await tester.pump(_frame);
    expect(_top(tester, 'c'), greaterThan(0));
    await tester.tapAt(const Offset(50, 10));
    expect(rows.taps, ['c']);
    await tester.pumpAndSettle();
    expect(_top(tester, 'c'), 0);
    expect(_top(tester, 'a'), 40);
  });

  testWidgets('parent data works through the wrapping', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            height: 100,
            child: MotionLayout(
              layoutBuilder: (context, children) => Column(children: children),
              children: const [
                Expanded(child: SizedBox(key: ValueKey('grow'), width: 10)),
                SizedBox(key: ValueKey('fixed'), width: 10, height: 20),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byKey(const ValueKey('grow'))).height, 80);
    expect(tester.getTopLeft(find.byKey(const ValueKey('fixed'))).dy, 80);
  });

  testWidgets('itemOf follows where the child is drawn', (tester) async {
    final items = <String, ValueListenable<LayoutItem>?>{};
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: MotionLayout(
            layoutBuilder: (context, children) => Column(children: children),
            children: [
              for (final id in ['a', 'b'])
                Builder(
                  key: ValueKey(id),
                  builder: (context) {
                    items[id] = MotionLayout.itemOf(context);
                    return const SizedBox(width: 10, height: 20);
                  },
                ),
            ],
          ),
        ),
      ),
    );
    expect(items['b']!.value.rect, const Rect.fromLTWH(0, 20, 10, 20));
  });

  testWidgets('a child that adopts its item is drawn where layout put it', (
    tester,
  ) async {
    ValueListenable<LayoutItem>? adopted;
    final ids = ValueNotifier(['a', 'b', 'c', 'd']);
    addTearDown(ids.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: ValueListenableBuilder(
            valueListenable: ids,
            builder: (context, ids, _) => MotionLayout(
              layoutBuilder: (context, children) => Column(
                mainAxisSize: MainAxisSize.min,
                children: children,
              ),
              children: [
                for (final id in ids)
                  if (id == 'c')
                    Builder(
                      key: const ValueKey('c'),
                      builder: (context) {
                        adopted = MotionLayout.adoptItem(context);
                        return const SizedBox(width: 100, height: 20);
                      },
                    )
                  else
                    _row(id),
              ],
            ),
          ),
        ),
      ),
    );
    withSpring(_spring, () => ids.value = ['a', 'c', 'd']);
    await tester.pump(_frame);
    await tester.pump(_frame);
    await tester.pump(_frame);
    expect(_top(tester, 'c'), 20);
    expect(adopted!.value.rect.top, inExclusiveRange(20, 40));
    expect(_top(tester, 'd'), inExclusiveRange(40, 60));
  });

  test('flip plans the transaction spring and the effects per phase', () {
    const planner = LayoutPlanner.flip(remove: MotionEffect(scale: (0.5, 1)));
    final plans = planner.plan(
      const LayoutChange(
        time: 1,
        spring: _spring,
        entries: {
          'in': LayoutEntry(phase: LayoutPhase.entering, to: Rect.zero),
          'stay': LayoutEntry(
            phase: LayoutPhase.staying,
            from: Rect.zero,
            to: Rect.fromLTWH(0, 10, 1, 1),
          ),
          'out': LayoutEntry(phase: LayoutPhase.leaving, from: Rect.zero),
        },
      ),
    );
    expect(plans['in']!.effect, MotionEffect.fade);
    expect(plans['stay']!.effect, isNull);
    expect(plans['out']!.effect, const MotionEffect(scale: (0.5, 1)));
    expect(plans['stay']!.spring, _spring);
  });
}

class _LabeledRows extends StatefulWidget {
  const _LabeledRows({required this.ids});

  final List<String> ids;

  @override
  State<_LabeledRows> createState() => _LabeledRowsState();
}

class _LabeledRowsState extends State<_LabeledRows> {
  late List<String> ids = widget.ids;

  void change(List<String> next) => setState(() => ids = next);

  @override
  Widget build(BuildContext context) => MotionLayout(
    layoutBuilder: (context, children) => Column(
      mainAxisSize: MainAxisSize.min,
      children: children,
    ),
    children: [
      for (final id in ids)
        Semantics(
          key: ValueKey(id),
          label: id,
          container: true,
          child: const SizedBox(width: 100, height: 20),
        ),
    ],
  );
}

class _Snapping extends LayoutPlanner {
  const _Snapping();

  @override
  Spring? get spring => const Spring.response(0.3);

  @override
  Map<Object, LayoutPlan> plan(LayoutChange change) => {
    for (final key in change.entries.keys) key: const LayoutPlan(),
  };
}

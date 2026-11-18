import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = Duration(milliseconds: 16);

class _Shell extends StatefulWidget {
  const _Shell(this.search, {this.tabs = 2});

  final GlassSearchController search;
  final int tabs;

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  int index = 0;

  @override
  Widget build(BuildContext context) => GlassTabScaffold(
    tabBar: GlassTabBar(
      destinations: [
        for (final name in ['Home', 'Library', 'Radio', 'New'].take(
          widget.tabs,
        ))
          GlassTabDestination(
            icon: const SizedBox.square(dimension: 24),
            label: Text(name),
          ),
      ],
      selectedIndex: index,
      onDestinationSelected: (next) => setState(() => index = next),
      searchController: widget.search,
    ),
    tabBuilder: (context, i) => Center(child: Text('Page $i')),
    searchBuilder: (context) => const Center(child: Text('Results')),
  );
}

Widget _app(
  GlassSearchController search, {
  double keyboard = 0,
  int tabs = 2,
}) => MediaQuery(
  data: MediaQueryData(
    size: const Size(402, 874),
    devicePixelRatio: 3,
    padding: const EdgeInsets.only(top: 62, bottom: 34),
    viewInsets: EdgeInsets.only(bottom: keyboard),
  ),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: GlassScope(
      renderer: const FlatGlassRenderer(),
      child: _Shell(search, tabs: tabs),
    ),
  ),
);

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(402 * 3, 874 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 90; i++) {
    await tester.pump(_frame);
  }
}

Rect _field(WidgetTester tester) =>
    tester.getRect(find.byType(GlassSearchField));

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('at rest the bar and the search circle stand 21 points from '
      'the sides and the bottom', (tester) async {
    await _phone(tester);
    final search = GlassSearchController();
    addTearDown(search.dispose);
    await tester.pumpWidget(_app(search));
    final bar = tester.getRect(find.byType(RawGlassSelector));
    expect(bar.left, 21);
    expect(bar.bottom, 874 - 21);
    final circle = tester.getRect(find.bySemanticsLabel('Search'));
    expect(circle, const Rect.fromLTWH(402 - 21 - 62, 874 - 83, 62, 62));
    expect(find.byType(GlassSearchField), findsNothing);
    expect(find.text('Results'), findsNothing);
  });

  testWidgets('the search circle lifts under a finger as a glass button '
      'does', (tester) async {
    await _phone(tester);
    final search = GlassSearchController();
    addTearDown(search.dispose);
    await tester.pumpWidget(_app(search));
    final gesture = await tester.startGesture(
      tester.getCenter(find.bySemanticsLabel('Search')),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(_frame);
    }
    final lifted = tester
        .widgetList<GlassSurface>(
          find.descendant(
            of: find.bySemanticsLabel('Search'),
            matching: find.byType(GlassSurface),
          ),
        )
        .single
        .frame!
        .value;
    expect(lifted.scaleX, greaterThan(1.01));
    await gesture.up();
    await tester.pump();
    expect(search.isOpen, isTrue);
    await _settle(tester);
  });

  testWidgets('four tabs narrow to fit beside the search circle', (
    tester,
  ) async {
    await _phone(tester);
    final search = GlassSearchController();
    addTearDown(search.dispose);
    await tester.pumpWidget(_app(search, tabs: 4));
    final bar = tester.getRect(find.byType(RawGlassSelector));
    final circle = tester.getRect(find.bySemanticsLabel('Search'));
    expect(bar.left, 21);
    expect(bar.right, closeTo(circle.left - 12, 0.01));
    expect(
      tester.getRect(find.text('New')).right,
      lessThanOrEqualTo(bar.right),
    );
  });

  testWidgets('the circle opens the search: the bar turns into the tab '
      'circle and the field takes the focus and rises over the keyboard', (
    tester,
  ) async {
    await _phone(tester);
    final search = GlassSearchController();
    addTearDown(search.dispose);
    await tester.pumpWidget(_app(search));
    await tester.tap(find.bySemanticsLabel('Search'));
    await tester.pump();
    expect(search.isOpen, isTrue);
    expect(find.text('Results'), findsOneWidget);
    expect(find.text('Page 0'), findsNothing);
    for (var i = 0; i < 12; i++) {
      await tester.pump(_frame);
    }
    final focus = tester
        .widget<GlassSearchField>(find.byType(GlassSearchField))
        .focusNode!;
    expect(focus.hasFocus, isTrue);
    await tester.pumpWidget(_app(search, keyboard: 336));
    await _settle(tester);
    final field = _field(tester);
    expect(field.left, 8);
    expect(field.bottom, 874 - 336 - 8);
    expect(find.bySemanticsLabel('Close'), findsOneWidget);

    search.text = 'tea';
    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pump();
    expect(search.text, isEmpty);
    expect(focus.hasFocus, isFalse);
    await tester.pumpWidget(_app(search));
    await _settle(tester);
    expect(
      _field(tester),
      const Rect.fromLTRB(88, 874 - 28 - 48, 374, 874 - 28),
    );
    expect(search.isOpen, isTrue);
  });

  testWidgets('the tab circle closes the search and clears the query', (
    tester,
  ) async {
    await _phone(tester);
    final search = GlassSearchController();
    addTearDown(search.dispose);
    await tester.pumpWidget(_app(search));
    await tester.tap(find.bySemanticsLabel('Search'));
    await _settle(tester);
    FocusManager.instance.primaryFocus?.unfocus();
    search.text = 'tea';
    await _settle(tester);
    await tester.tapAt(const Offset(28 + 24, 874 - 28 - 24));
    await tester.pump();
    expect(search.isOpen, isFalse);
    await tester.pump(_frame);
    expect(search.text, isEmpty);
    await _settle(tester);
    expect(find.byType(GlassSearchField), findsNothing);
    expect(find.text('Page 0'), findsOneWidget);
    final bar = tester.getRect(find.byType(RawGlassSelector));
    expect(bar.left, 21);
    await tester.tap(find.text('Library'));
    await _settle(tester);
    expect(find.text('Page 1'), findsOneWidget);
  });
}

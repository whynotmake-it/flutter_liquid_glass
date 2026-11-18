import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/chrome.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'conformance/harness.dart' show globalRect;

const _frame = Duration(milliseconds: 16);

Widget _app(Widget child, {TextDirection direction = TextDirection.ltr}) =>
    MediaQuery(
      data: const MediaQueryData(
        size: Size(402, 874),
        devicePixelRatio: 3,
        padding: EdgeInsets.only(top: 62, bottom: 34),
      ),
      child: Directionality(
        textDirection: direction,
        child: GlassScope(renderer: const FlatGlassRenderer(), child: child),
      ),
    );

Widget _page({
  Widget? title,
  Widget? largeTitle,
  Widget? leading,
  Widget? trailing,
  ScrollController? controller,
}) => GlassPageScaffold(
  navigationBar: GlassNavigationBar(
    title: title,
    largeTitle: largeTitle,
    leading: [if (leading != null) GlassBarItem.custom(child: leading)],
    trailing: [if (trailing != null) GlassBarItem.custom(child: trailing)],
  ),
  child: GlassContentScroll(
    child: ListView(
      controller: controller,
      children: [
        for (var i = 0; i < 40; i++)
          SizedBox(height: 50, child: Text('Row $i')),
      ],
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

double _titleOpacity(WidgetTester tester) => tester
    .widgetList<MotionTransition>(find.byType(MotionTransition))
    .firstWhere((transition) => transition.blur != null)
    .opacity!
    .value;

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('the inline title sits on the center when it fits, else from '
      'the leading side, level with the capsules', (tester) async {
    await _phone(tester);
    const side = SizedBox(width: 36, height: 36);
    await tester.pumpWidget(
      _app(_page(title: const Text('Title'), leading: side, trailing: side)),
    );
    await tester.pump();
    expect(tester.getCenter(find.text('Title')).dx, 201);
    expect(tester.getCenter(find.text('Title')).dy, 62 + 22);
    await tester.pumpWidget(
      _app(
        _page(
          title: const Text('A title much too long to stand centered'),
          leading: const SizedBox(width: 120, height: 36),
          trailing: side,
        ),
      ),
    );
    await tester.pump();
    final title = tester.getRect(
      find.text('A title much too long to stand centered'),
    );
    expect(title.left, 16 + 128 + 12);
    expect(title.right, lessThanOrEqualTo(402 - 16 - 44 - 12));
  });

  testWidgets('a finger on a bar button lifts its capsule at once, and the '
      'tap presses the button', (tester) async {
    await _phone(tester);
    var pressed = 0;
    await tester.pumpWidget(
      _app(
        GlassPageScaffold(
          navigationBar: GlassNavigationBar(
            title: const Text('Title'),
            trailing: [
              GlassBarItem(
                icon: const SizedBox.square(dimension: 22),
                semanticLabel: 'Edit',
                onPressed: () => pressed++,
              ),
            ],
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pump();
    double widest() => tester
        .widgetList<GlassSurface>(find.byType(GlassSurface))
        .map((surface) => surface.frame?.value.scaleX ?? 1)
        .fold(1, (a, b) => a > b ? a : b);
    expect(widest(), 1);
    final gesture = await tester.startGesture(
      globalRect(
        tester,
        tester.getSemantics(find.bySemanticsLabel('Edit')),
      ).center,
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(_frame);
    }
    expect(widest(), greaterThan(1.05));
    await gesture.up();
    await _settle(tester);
    expect(pressed, 1);
    expect(widest(), 1);
  });

  testWidgets('right to left, the leading capsule stands at the right', (
    tester,
  ) async {
    await _phone(tester);
    await tester.pumpWidget(
      _app(
        _page(
          title: const Text('Title'),
          leading: const SizedBox(key: Key('leading'), width: 36, height: 36),
        ),
        direction: TextDirection.rtl,
      ),
    );
    await tester.pump();
    expect(
      tester.getTopRight(find.byKey(const Key('leading'))).dx,
      402 - 16 - 4,
    );
  });

  testWidgets('a large title scrolls away with the content, then the '
      'inline title rises in', (tester) async {
    await _phone(tester);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(_page(largeTitle: const Text('Notes'), controller: controller)),
    );
    await tester.pump();
    expect(tester.getTopLeft(find.text('Row 0')).dy, 62 + 54 + 52);
    final large = find.text('Notes').last;
    final rest = tester.getTopLeft(large).dy;
    expect(_titleOpacity(tester), 0);
    controller.jumpTo(20);
    await tester.pump();
    expect(tester.getTopLeft(large).dy, rest - 20);
    await _settle(tester);
    expect(controller.offset, 20);
    expect(_titleOpacity(tester), 0);
    controller.jumpTo(60);
    await tester.pump(_frame);
    expect(_titleOpacity(tester), 1);
    controller.jumpTo(0);
    await tester.pump(_frame);
    await tester.timedDrag(
      find.byType(ListView),
      const Offset(0, -120),
      const Duration(milliseconds: 600),
    );
    await tester.pump(_frame);
    expect(_titleOpacity(tester), inExclusiveRange(0, 1));
    await _settle(tester);
    expect(_titleOpacity(tester), 1);
  });

  testWidgets('under Reduce Motion from the tree the inline title switches '
      'in the frame the content passes it, without a rise', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(
      MotionTraitsOverride(
        traits: const MotionTraits(reduceMotion: true),
        child: _app(_page(largeTitle: const Text('Notes'))),
      ),
    );
    await tester.pump();
    expect(_titleOpacity(tester), 0);
    await tester.timedDrag(
      find.byType(ListView),
      const Offset(0, -120),
      const Duration(milliseconds: 600),
    );
    await tester.pump(_frame);
    expect(_titleOpacity(tester), 1);
    final rise = tester
        .widgetList<MotionTransition>(find.byType(MotionTransition))
        .firstWhere((transition) => transition.blur != null);
    expect(rise.blur!.value, 0);
  });

  testWidgets('a scroll left with the large title partly away springs to '
      'the nearer end', (tester) async {
    await _phone(tester);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(_page(largeTitle: const Text('Notes'), controller: controller)),
    );
    await tester.pump();
    await tester.timedDrag(
      find.byType(ListView),
      const Offset(0, -20),
      const Duration(milliseconds: 600),
    );
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
    await tester.timedDrag(
      find.byType(ListView),
      const Offset(0, -36),
      const Duration(milliseconds: 600),
    );
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(52, 0.5));
  });

  testWidgets('the edge under a large title bar is hard and covers only the '
      'row, once the title has gone', (tester) async {
    await _phone(tester);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(_page(largeTitle: const Text('Notes'), controller: controller)),
    );
    await tester.pump();
    final top = tester
        .widgetList<ScrollEdgeBand>(find.byType(ScrollEdgeBand))
        .map((edge) => edge.details)
        .firstWhere((details) => details.edge == AxisDirection.up);
    expect(top.hard, isTrue);
    expect(top.extent, 62 + 54);
    controller.jumpTo(40);
    await _settle(tester);
    expect(top.presence.value, 0);
    controller.jumpTo(100);
    await _settle(tester);
    expect(top.presence.value, 1);
  });

  testWidgets('the theme colors the titles', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(
      _app(
        GlassTheme(
          data: const GlassThemeData(
            styles: [
              GlassNavigationBarStyle(
                foregroundColor: Color(0xFF123456),
              ),
            ],
          ),
          child: _page(title: const Text('Title')),
        ),
      ),
    );
    final style = DefaultTextStyle.of(tester.element(find.text('Title'))).style;
    expect(style.color, isSameColorAs(const Color(0xFF123456)));
    expect(style.fontSize, 17);
  });

  testWidgets('a tab scaffold that rebuilds leaves the page its scroll view: '
      'the large title stays away', (tester) async {
    await _phone(tester);
    late StateSetter rebuild;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return GlassTabScaffold(
              tabBar: GlassTabBar(
                destinations: const [
                  GlassTabDestination(icon: SizedBox(), label: Text('One')),
                  GlassTabDestination(icon: SizedBox(), label: Text('Two')),
                ],
                selectedIndex: 0,
                onDestinationSelected: (_) {},
              ),
              tabBuilder: (context, index) =>
                  _page(largeTitle: const Text('Big')),
            );
          },
        ),
      ),
    );
    await _settle(tester);
    final context = tester.element(find.byType(GlassContentScroll));
    final chrome = context.getInheritedWidgetOfExactType<GlassChrome>()!;
    final scroll = chrome.active.value;
    expect(scroll, isNotNull);
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await _settle(tester);
    final followed = <MotionScroll?>[];
    chrome.active.addListener(() => followed.add(chrome.active.value));

    rebuild(() {});
    await tester.pump(_frame);
    await tester.pump(_frame);

    expect(followed, isEmpty);
    expect(chrome.active.value, same(scroll));
  });

  testWidgets('the title takes the bar style, then the theme style, then '
      'label', (tester) async {
    await _phone(tester);
    Color? title() =>
        DefaultTextStyle.of(tester.element(find.text('Title'))).style.color;
    Widget page({GlassNavigationBarStyle? style}) => GlassPageScaffold(
      navigationBar: GlassNavigationBar(
        title: const Text('Title'),
        style: style,
      ),
      child: const SizedBox.expand(),
    );
    const themed = GlassThemeData(
      styles: [GlassNavigationBarStyle(foregroundColor: Color(0xFF123456))],
    );
    await tester.pumpWidget(_app(page()));
    expect(
      title(),
      isSameColorAs(GlassColors.label.resolvedWith(const GlassTraits())),
    );

    await tester.pumpWidget(_app(GlassTheme(data: themed, child: page())));
    expect(title(), isSameColorAs(const Color(0xFF123456)));

    await tester.pumpWidget(
      _app(
        GlassTheme(
          data: themed,
          child: page(
            style: const GlassNavigationBarStyle(
              foregroundColor: Color(0xFF654321),
            ),
          ),
        ),
      ),
    );
    expect(title(), isSameColorAs(const Color(0xFF654321)));
  });
}

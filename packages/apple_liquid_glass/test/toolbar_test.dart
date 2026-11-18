import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child, {double keyboard = 0}) => MediaQuery(
  data: MediaQueryData(
    size: const Size(402, 874),
    devicePixelRatio: 3,
    padding: const EdgeInsets.only(top: 62, bottom: 34),
    viewInsets: EdgeInsets.only(bottom: keyboard),
  ),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: GlassScope(renderer: const FlatGlassRenderer(), child: child),
  ),
);

Widget _page({ScrollController? controller}) => GlassPageScaffold(
  toolbar: GlassToolbar(
    items: [
      GlassBarItem(
        label: const Text('Edit', key: Key('first')),
        onPressed: () {},
      ),
      const GlassBarSpacer.flexible(),
      GlassBarItem(
        label: const Text('Done', key: Key('last')),
        onPressed: () {},
      ),
    ],
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

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('the items float 28 points from the sides and the bottom of '
      'the screen', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(_app(_page()));
    await tester.pump();
    final first = tester.getRect(find.byKey(const Key('first')));
    final last = tester.getRect(find.byKey(const Key('last')));
    expect(first.left, 28 + 5 + 11);
    expect(last.right, 402 - 28 - 5 - 11);
    expect(first.center.dy, 874 - 28 - 24);
  });

  testWidgets('above a keyboard the items keep 8 points from it', (
    tester,
  ) async {
    await _phone(tester);
    await tester.pumpWidget(_app(_page(), keyboard: 336));
    await tester.pump();
    final first = tester.getRect(find.byKey(const Key('first')));
    expect(first.center.dy, 874 - 336 - 8 - 24);
  });

  testWidgets('the content scrolls clear of the toolbar, and no automatic '
      'edge effect lies under it', (tester) async {
    await _phone(tester);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(_page(controller: controller)));
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    expect(tester.getBottomLeft(find.text('Row 39')).dy, 874 - 76);
    final edges = tester
        .widgetList<ScrollEdgeBand>(find.byType(ScrollEdgeBand))
        .map((edge) => edge.details.edge);
    expect(edges, isNot(contains(AxisDirection.down)));
  });

  group('a search field in the toolbar', () {
    Widget search(
      TextEditingController controller, {
      double keyboard = 0,
      FocusNode? focus,
    }) => _app(
      GlassPageScaffold(
        toolbar: GlassToolbar(
          items: [
            GlassBarItem.custom(
              child: GlassButton(
                key: const Key('first'),
                onPressed: () {},
                child: const SizedBox.square(dimension: 24),
              ),
            ),
            GlassBarItem.custom(
              child: GlassSearchField(
                key: const Key('field'),
                controller: controller,
                focusNode: focus,
              ),
            ),
            GlassBarItem.custom(
              child: GlassButton(
                key: const Key('last'),
                onPressed: () {},
                child: const SizedBox.square(dimension: 24),
              ),
            ),
          ],
        ),
        child: const SizedBox.expand(),
      ),
      keyboard: keyboard,
    );

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    Rect field(WidgetTester tester) =>
        tester.getRect(find.byKey(const Key('field')));

    testWidgets('fills the room between the items at rest', (tester) async {
      await _phone(tester);
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(search(controller));
      final first = tester.getRect(find.byKey(const Key('first')));
      final last = tester.getRect(find.byKey(const Key('last')));
      expect(first.left, 28);
      expect(first.height, 48);
      expect(last.right, 402 - 28);
      expect(
        field(tester),
        Rect.fromLTRB(
          first.right + 12,
          874 - 28 - 48,
          last.left - 12,
          874 - 28,
        ),
      );
    });

    testWidgets('focused, it widens and rises above the keyboard; the close '
        'button ends the search', (tester) async {
      await _phone(tester);
      final controller = TextEditingController(text: 'glass');
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(search(controller, focus: focus));
      focus.requestFocus();
      await tester.pump();
      final rest = field(tester).left;
      await tester.pump(const Duration(milliseconds: 100));
      expect(field(tester).left, rest);
      await tester.pumpWidget(search(controller, focus: focus, keyboard: 336));
      await settle(tester);
      expect(
        field(tester),
        const Rect.fromLTRB(
          8,
          874 - 336 - 10 - 48,
          402 - 8 - 48 - 12,
          874 - 336 - 10,
        ),
      );
      final close = find.bySemanticsLabel('Close');
      expect(tester.getCenter(close).dx, closeTo(402 - 8 - 24, 0.5));
      await tester.tap(close);
      await tester.pumpWidget(search(controller, focus: focus));
      await tester.pump(const Duration(milliseconds: 100));
      expect(field(tester).bottom, lessThan(874 - 200));
      await settle(tester);
      expect(focus.hasFocus, isFalse);
      expect(controller.text, isEmpty);
      expect(field(tester).left, rest);
    });

    testWidgets('without a keyboard the search starts after 0.3 s anyway', (
      tester,
    ) async {
      await _phone(tester);
      final controller = TextEditingController();
      final focus = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(search(controller, focus: focus));
      focus.requestFocus();
      await tester.pump();
      await settle(tester);
      expect(field(tester).left, 8);
      expect(field(tester).bottom, 874 - 10);
    });
  });

  testWidgets('a toolbar style on the theme colors the items by state and '
      'tints a prominent capsule', (tester) async {
    await _phone(tester);
    const style = GlassToolbarStyle(
      itemStyle: GlassBarItemStyle(
        foregroundColor: WidgetStateMapper({
          WidgetState.disabled: Color(0xFFAA0000),
          WidgetState.any: Color(0xFF00AA00),
        }),
        prominentColor: Color(0xFF0000AA),
      ),
    );
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(402, 874),
          devicePixelRatio: 3,
          padding: EdgeInsets.only(top: 62, bottom: 34),
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: GlassScope(
            renderer: const FlatGlassRenderer(),
            data: const GlassThemeData(
              styles: [style],
            ),
            child: GlassPageScaffold(
              toolbar: GlassToolbar(
                items: [
                  GlassBarItem(label: const Text('Edit'), onPressed: () {}),
                  const GlassBarSpacer.flexible(),
                  const GlassBarItem(label: Text('Off')),
                  const GlassBarSpacer.flexible(),
                  GlassBarItem.prominent(
                    label: const Text('Go'),
                    onPressed: () {},
                  ),
                ],
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    Color? color(String text) =>
        DefaultTextStyle.of(tester.element(find.text(text))).style.color;
    expect(color('Edit'), const Color(0xFF00AA00));
    expect(color('Off'), const Color(0xFFAA0000));
    final tints = [
      for (final surface in tester.widgetList<GlassSurface>(
        find.byType(GlassSurface),
      ))
        surface.frame?.value.tint,
    ];
    expect(tints, contains(const Color(0xFF0000AA)));
  });
}

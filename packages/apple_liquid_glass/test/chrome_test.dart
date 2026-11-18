import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass/src/liquid/scroll_edge.dart';
import 'package:apple_liquid_glass/src/surfaces/scroll_edge.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = Duration(milliseconds: 16);

Widget _app(
  Widget child, {
  GlassRenderer renderer = const FlatGlassRenderer(),
  bool reduceTransparency = false,
}) => MediaQuery(
  data: const MediaQueryData(
    size: Size(402, 874),
    devicePixelRatio: 3,
    padding: EdgeInsets.only(top: 62, bottom: 34),
  ),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: GlassScope(
      renderer: renderer,
      child: GlassTraitsOverride(
        reduceTransparency: reduceTransparency,
        child: child,
      ),
    ),
  ),
);

PreferredSizeWidget _bar(double height) => PreferredSize(
  preferredSize: Size.fromHeight(height),
  child: SizedBox(height: height),
);

Widget _page({
  GlassScrollEdgeEffects edgeEffects = const GlassScrollEdgeEffects(),
  ScrollController? controller,
}) => GlassPageScaffold(
  navigationBar: _bar(54),
  toolbar: _bar(48),
  child: GlassContentScroll(
    edgeEffects: edgeEffects,
    child: ListView(
      controller: controller,
      children: [
        for (var i = 0; i < 40; i++)
          SizedBox(height: 50, child: Text('Row $i')),
      ],
    ),
  ),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(_frame);
  }
}

List<GlassScrollEdgeDetails> _edges(WidgetTester tester) => [
  for (final edge in tester.widgetList<ScrollEdgeBand>(
    find.byType(ScrollEdgeBand),
  ))
    edge.details,
];

void main() {
  setUp(MotionClock.debugReset);

  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('the content starts under the navigation bar and scrolls '
      'clear of the toolbar', (tester) async {
    await phone(tester);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(_page(controller: controller)));
    expect(tester.getTopLeft(find.text('Row 0')).dy, 62 + 54);
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    expect(tester.getBottomLeft(find.text('Row 39')).dy, 874 - 34 - 48);
  });

  testWidgets('an edge effect fades in once content lies under its bar and '
      'out when it leaves', (tester) async {
    await phone(tester);
    await tester.pumpWidget(_app(_page()));
    await tester.pump();
    final edges = _edges(tester);
    expect(edges, hasLength(2));
    final top = edges.firstWhere((edge) => edge.edge == AxisDirection.up);
    final bottom = edges.firstWhere((edge) => edge.edge == AxisDirection.down);
    expect(top.extent, 62 + 54);
    expect(top.hard, isFalse);
    expect(bottom.extent, 34 + 48);
    expect(top.presence.value, 0);
    expect(bottom.presence.value, 1);
    await tester.drag(find.byType(ListView), const Offset(0, -100));
    await _settle(tester);
    expect(top.presence.value, 1);
    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await _settle(tester);
    expect(top.presence.value, 0);
  });

  testWidgets('under Reduce Motion from the tree an edge switches in the '
      'frame content reaches its bar', (tester) async {
    await phone(tester);
    await tester.pumpWidget(
      MotionTraitsOverride(
        traits: const MotionTraits(reduceMotion: true),
        child: _app(_page()),
      ),
    );
    await tester.pump();
    final top = _edges(
      tester,
    ).firstWhere((edge) => edge.edge == AxisDirection.up);
    expect(top.presence.value, 0);
    final finger = await tester.startGesture(
      tester.getCenter(find.byType(ListView)),
    );
    await finger.moveBy(const Offset(0, -40));
    await finger.moveBy(const Offset(0, -60));
    await tester.pump(_frame);
    expect(top.presence.value, 1);
    await finger.up();
  });

  testWidgets('a hidden edge draws nothing', (tester) async {
    await tester.pumpWidget(
      _app(
        _page(
          edgeEffects: const GlassScrollEdgeEffects(
            bottom: GlassScrollEdgeEffect.hidden,
          ),
        ),
      ),
    );
    expect(_edges(tester).map((edge) => edge.edge), [AxisDirection.up]);
  });

  testWidgets('liquid glass blurs under the edge; flat and Reduce '
      'Transparency only dissolve', (tester) async {
    bool blurs() {
      final blurred = find.byType(ScrollEdge).evaluate().length;
      final flat = find.byType(FlatScrollEdge).evaluate().length;
      expect(blurred + flat, greaterThan(0));
      return blurred > 0 && flat == 0;
    }

    await tester.pumpWidget(_app(_page()));
    expect(blurs(), isFalse);
    await tester.pumpWidget(
      _app(_page(), renderer: const LiquidGlassRenderer()),
    );
    expect(blurs(), isTrue);
    await tester.pumpWidget(
      _app(
        _page(),
        renderer: const LiquidGlassRenderer(),
        reduceTransparency: true,
      ),
    );
    expect(blurs(), isFalse);
  });

  testWidgets('a tap on the status bar scrolls the content to its start', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_app(_page(controller: controller)));
    await tester.pump();
    controller.jumpTo(600);
    await tester.pump();
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.statusBar.name,
      SystemChannels.statusBar.codec.encodeMethodCall(
        const MethodCall('handleScrollToTop'),
      ),
      (_) {},
    );
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
  });

  testWidgets('the bars follow the scroll view shown last', (tester) async {
    final first = ScrollController();
    final second = ScrollController();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    Widget page(int shown) => _app(
      GlassPageScaffold(
        navigationBar: _bar(54),
        child: IndexedStack(
          index: shown,
          children: [
            for (final controller in [first, second])
              TickerMode(
                enabled: controller == (shown == 0 ? first : second),
                child: GlassContentScroll(
                  child: ListView(
                    controller: controller,
                    children: [
                      for (var i = 0; i < 40; i++) const SizedBox(height: 50),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(page(0));
    await tester.pump();
    await tester.pumpWidget(page(1));
    await tester.pump();
    second.jumpTo(300);
    await tester.pump();
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      SystemChannels.statusBar.name,
      SystemChannels.statusBar.codec.encodeMethodCall(
        const MethodCall('handleScrollToTop'),
      ),
      (_) {},
    );
    await tester.pumpAndSettle();
    expect(second.offset, 0);
  });
}

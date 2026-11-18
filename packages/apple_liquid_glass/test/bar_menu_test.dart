import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass/src/widgets/navigation/bar.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = Duration(milliseconds: 16);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 90; i++) {
    await tester.pump(_frame);
  }
}

Widget _app(Widget page) => MediaQuery(
  data: const MediaQueryData(
    size: Size(402, 874),
    devicePixelRatio: 3,
    padding: EdgeInsets.only(top: 62, bottom: 34),
  ),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: GlassScope(
      renderer: const FlatGlassRenderer(),
      child: WidgetsApp(
        color: const Color(0xFFFFFFFF),
        pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
          settings: settings,
          pageBuilder: (context, _, _) => builder(context),
        ),
        home: page,
      ),
    ),
  ),
);

var _paintsInBar = 0;

class _Probe extends CustomPainter {
  const _Probe();

  @override
  void paint(Canvas canvas, Size size) => _paintsInBar++;

  @override
  bool shouldRepaint(_Probe oldDelegate) => false;
}

class _Page extends StatefulWidget {
  const _Page();

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  var _on = false;

  @override
  Widget build(BuildContext context) => GlassPageScaffold(
    navigationBar: GlassNavigationBar(
      title: const Text('Page'),
      trailing: [
        GlassBarItem(
          icon: const SizedBox.square(key: Key('menu'), dimension: 22),
          semanticLabel: 'Look',
          menuChildren: [
            GlassMenuItem(
              title: _on ? 'On' : 'Off',
              keepsMenuOpen: true,
              onPressed: () => setState(() => _on = !_on),
            ),
            const GlassMenuItem(title: 'Other'),
          ],
        ),
        GlassBarItem(
          icon: Builder(
            builder: (context) => SizedBox.square(
              key: const Key('plain'),
              dimension: 22,
              child: _inMenu(context as Element)
                  ? null
                  : const CustomPaint(painter: _Probe()),
            ),
          ),
          onPressed: () {},
        ),
      ],
    ),
    child: const SizedBox.expand(),
  );
}

// The menu's overlay stays below its source in the element tree.
bool _inMenu(Element element) =>
    element.findAncestorWidgetOfExactType<GlassMenuAnchor>() != null;

List<double> _capsules(WidgetTester tester) => [
  for (final element
      in find
          .descendant(
            of: find.byType(GlassBarView),
            matching: find.byType(GlassSurface),
          )
          .evaluate())
    if (!_inMenu(element))
      if ((element.widget as GlassSurface).frame!.value case final frame
          when frame.rect != Rect.zero)
        frame.opacity,
];

void main() {
  setUp(MotionClock.debugReset);

  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(const _Page()));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('a bar item with a menu shares a capsule with its neighbours', (
    tester,
  ) async {
    await phone(tester);
    expect(_capsules(tester), [1]);
    final menu = tester.getCenter(find.byKey(const Key('menu')));
    final plain = tester.getCenter(find.byKey(const Key('plain')));
    expect(plain.dx - menu.dx, lessThan(60));
  });

  testWidgets('the menu takes the whole capsule, glyphs included, until it has '
      'closed', (tester) async {
    await phone(tester);
    final bar = find.byType(GlassBarView);
    final plain = tester.getCenter(find.byKey(const Key('plain')));
    final probe = tester.renderObject<RenderCustomPaint>(
      find.descendant(of: bar, matching: find.byType(CustomPaint)).first,
    );

    await tester.tapAt(tester.getCenter(find.byKey(const Key('menu'))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pump(_frame);
    final copy = find.byKey(const Key('plain')).evaluate().where(_inMenu);
    expect(copy, hasLength(1));
    final near = (copy.single.renderObject! as RenderBox).localToGlobal(
      const Offset(11, 11),
    );
    expect((near - plain).distance, lessThan(12));

    await _settle(tester);
    expect(find.text('Off'), findsOneWidget);
    expect(_capsules(tester), [0]);
    _paintsInBar = 0;
    probe.markNeedsPaint();
    await tester.pump();
    expect(_paintsInBar, 0);

    await tester.tapAt(const Offset(40, 700));
    await _settle(tester);
    expect(find.text('Off'), findsNothing);
    expect(_capsules(tester), [1]);
    expect(find.byKey(const Key('plain')), findsOneWidget);
    probe.markNeedsPaint();
    await tester.pump();
    expect(_paintsInBar, greaterThan(0));
  });

  testWidgets('the plain neighbour still takes its own tap', (tester) async {
    var taps = 0;
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        GlassPageScaffold(
          navigationBar: GlassNavigationBar(
            title: const Text('Page'),
            trailing: [
              const GlassBarItem(
                icon: SizedBox.square(key: Key('menu'), dimension: 22),
                semanticLabel: 'Look',
                menuChildren: [GlassMenuItem(title: 'Other')],
              ),
              GlassBarItem(
                icon: const SizedBox.square(key: Key('plain'), dimension: 22),
                onPressed: () => taps++,
              ),
            ],
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tapAt(tester.getCenter(find.byKey(const Key('plain'))));
    await _settle(tester);
    expect(taps, 1);
    expect(find.text('Other'), findsNothing);
  });

  group('while the menu closes', () {
    var plain = 0;
    var below = 0;

    Future<void> closing(WidgetTester tester) async {
      plain = 0;
      below = 0;
      tester.view.physicalSize = const Size(402 * 3, 874 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          GlassPageScaffold(
            navigationBar: GlassNavigationBar(
              title: const Text('Page'),
              trailing: [
                const GlassBarItem(
                  icon: SizedBox.square(key: Key('menu'), dimension: 22),
                  semanticLabel: 'Look',
                  menuChildren: [GlassMenuItem(title: 'Other')],
                ),
                GlassBarItem(
                  icon: const SizedBox.square(key: Key('plain'), dimension: 22),
                  onPressed: () => plain++,
                ),
              ],
            ),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => below++,
                child: const SizedBox(
                  key: Key('below'),
                  width: 200,
                  height: 60,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.tapAt(tester.getCenter(find.byKey(const Key('menu'))));
      await _settle(tester);
      await tester.tapAt(const Offset(40, 500));
      for (var i = 0; i < 20; i++) {
        await tester.pump(_frame);
      }
      expect(find.text('Other'), findsOneWidget);
    }

    testWidgets('a neighbour in the capsule takes its tap, and the menu goes '
        'on closing', (tester) async {
      await closing(tester);
      final at = tester.getCenter(find.byKey(const Key('plain')).first);
      await tester.tapAt(at);
      await _settle(tester);
      expect(plain, 1);
      expect(find.text('Other'), findsNothing);
    });

    testWidgets('what is below the menu takes its tap', (tester) async {
      await closing(tester);
      await tester.tapAt(tester.getCenter(find.byKey(const Key('below'))));
      await _settle(tester);
      expect(below, 1);
      expect(find.text('Other'), findsNothing);
    });

    testWidgets('the capsule is back before the springs stop ringing', (
      tester,
    ) async {
      await closing(tester);
      for (var i = 0; i < 25; i++) {
        await tester.pump(_frame);
      }
      expect(find.text('Other'), findsNothing);
      expect(_capsules(tester), [1]);
    });

    testWidgets('a tap on the item that opened it opens it again', (
      tester,
    ) async {
      await closing(tester);
      await tester.tapAt(tester.getCenter(find.byKey(const Key('menu')).first));
      await _settle(tester);
      expect(find.text('Other'), findsOneWidget);
      expect(plain, 0);
    });
  });

  testWidgets('the open menu follows the entries the page declares', (
    tester,
  ) async {
    await phone(tester);
    await tester.tapAt(tester.getCenter(find.byKey(const Key('menu'))));
    await tester.pump();
    await _settle(tester);
    await tester.tap(find.text('Off'));
    await _settle(tester);
    expect(find.text('On'), findsOneWidget);
    expect(find.text('Off'), findsNothing);
  });
}

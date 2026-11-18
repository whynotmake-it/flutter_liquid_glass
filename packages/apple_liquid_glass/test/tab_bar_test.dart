import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = Duration(milliseconds: 16);

Widget _app(
  Widget child, {
  GlassRenderer renderer = const FlatGlassRenderer(),
  GlassThemeData theme = const GlassThemeData(),
  TextDirection direction = TextDirection.ltr,
}) => MediaQuery(
  data: const MediaQueryData(),
  child: Directionality(
    textDirection: direction,
    child: GlassScope(
      renderer: renderer,
      data: theme,
      child: Center(child: child),
    ),
  ),
);

Widget _keys(Widget child, {TextDirection direction = TextDirection.ltr}) =>
    WidgetsApp(
      color: const Color(0xFF000000),
      builder: (context, _) => _app(child, direction: direction),
    );

List<GlassTabDestination> _tabs(int count) => [
  for (var i = 0; i < count; i++)
    GlassTabDestination(
      icon: const SizedBox.square(dimension: 24),
      label: Text('Tab $i'),
    ),
];

class _Controlled extends StatefulWidget {
  const _Controlled({this.count = 4, this.onSelected, this.style});

  final int count;
  final ValueChanged<int>? onSelected;
  final GlassTabBarStyle? style;

  @override
  State<_Controlled> createState() => _ControlledState();
}

class _ControlledState extends State<_Controlled> {
  int index = 0;

  @override
  Widget build(BuildContext context) => GlassTabBar(
    destinations: _tabs(widget.count),
    selectedIndex: index,
    style: widget.style,
    onDestinationSelected: (next) {
      widget.onSelected?.call(next);
      setState(() => index = next);
    },
  );
}

class _Probe {
  int builds = 0;
  GlassSelectorDetails? details;

  Widget build(BuildContext context, GlassSelectorDetails details) {
    builds++;
    this.details = details;
    return details.items();
  }

  GlassFrame get lens => details!.lens.value;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(_frame);
  }
}

Offset _at(WidgetTester tester, int tab) =>
    tester.getCenter(find.text('Tab $tab'));

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('the bar is 62 tall and as wide as its tabs', (tester) async {
    final probe = _Probe();
    await tester.pumpWidget(
      _app(
        GlassTabBar(
          destinations: _tabs(4),
          selectedIndex: 0,
          onDestinationSelected: (_) {},
          style: GlassTabBarStyle(builder: probe.build),
        ),
      ),
    );
    expect(tester.getSize(find.byType(RawGlassSelector)), const Size(360, 62));
    expect(
      probe.lens.rect,
      Rect.fromCenter(
        center: const Offset(51.5, 31),
        width: 95,
        height: 54,
      ),
    );
    await tester.pumpWidget(
      _app(
        GlassTabBar(
          destinations: [
            for (var i = 0; i < 5; i++)
              GlassTabDestination(
                icon: const SizedBox.square(dimension: 24),
                label: Text('$i'),
              ),
          ],
          selectedIndex: 0,
          onDestinationSelected: (_) {},
        ),
      ),
    );
    expect(tester.getSize(find.byType(RawGlassSelector)), const Size(360, 62));
    await tester.pumpWidget(_app(const _Controlled(count: 5)));
    expect(tester.getSize(find.byType(RawGlassSelector)), const Size(360, 62));
  });

  testWidgets('long titles leave a bar of four tabs as it is and end in an '
      'ellipsis', (tester) async {
    await tester.pumpWidget(
      _app(
        GlassTabBar(
          destinations: [
            for (var i = 0; i < 4; i++)
              GlassTabDestination(
                icon: const SizedBox.square(key: Key('icon'), dimension: 24),
                label: Text('A very long title $i'),
              ),
          ],
          selectedIndex: 0,
          onDestinationSelected: (_) {},
        ),
      ),
    );
    expect(tester.getSize(find.byType(RawGlassSelector)), const Size(360, 62));
    expect(tester.takeException(), isNull);
    final title = find.text('A very long title 1').first;
    expect(tester.getSize(title).height, lessThan(30));
    expect(
      tester
          .widget<RichText>(
            find.descendant(of: title, matching: find.byType(RichText)),
          )
          .overflow,
      TextOverflow.ellipsis,
    );
  });

  testWidgets('a bar of two or three tabs hugs its widest title, up to what '
      'it is given', (tester) async {
    Widget two(String title) => SizedBox(
      width: 360,
      child: Center(
        child: GlassTabBar(
          destinations: [
            GlassTabDestination(
              icon: const SizedBox.square(dimension: 24),
              label: Text(title),
            ),
            const GlassTabDestination(
              icon: SizedBox.square(dimension: 24),
              label: Text('B'),
            ),
          ],
          selectedIndex: 0,
          onDestinationSelected: (_) {},
        ),
      ),
    );
    await tester.pumpWidget(_app(two('A')));
    expect(tester.getSize(find.byType(RawGlassSelector)), const Size(188, 62));
    await tester.pumpWidget(_app(two('A title of some length')));
    final wide = tester.getSize(find.byType(RawGlassSelector));
    expect(wide.width, greaterThan(188));
    expect(wide.height, 62);
    await tester.pumpWidget(_app(two('A title of some length ' * 20)));
    expect(tester.getSize(find.byType(RawGlassSelector)), const Size(360, 62));
  });

  testWidgets('the glyph stands at 24 and a title grows upward from 51', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        GlassTabBar(
          destinations: [
            for (final (i, size) in [11.0, 20.0, 11.0, 11.0].indexed)
              GlassTabDestination(
                icon: SizedBox.square(key: ValueKey(i), dimension: 24),
                label: Text('T$i', style: TextStyle(fontSize: size)),
              ),
          ],
          selectedIndex: 3,
          onDestinationSelected: (_) {},
        ),
      ),
    );
    final bar = tester.getTopLeft(find.byType(RawGlassSelector)).dy;
    for (var i = 0; i < 3; i++) {
      final glyph = find.byKey(ValueKey(i)).first;
      expect(tester.getCenter(glyph).dy - bar, closeTo(24, 0.01));
      expect(
        tester.getBottomLeft(find.text('T$i').first).dy - bar,
        closeTo(51, 0.01),
      );
    }
  });

  testWidgets('a tap selects; a tap on the selected tab reselects it', (
    tester,
  ) async {
    final selected = <int>[];
    await tester.pumpWidget(_app(_Controlled(onSelected: selected.add)));
    await tester.tapAt(_at(tester, 2));
    await _settle(tester);
    expect(selected, [2]);
    await tester.tapAt(_at(tester, 2));
    await _settle(tester);
    expect(selected, [2, 2]);
  });

  testWidgets('a drag lifts the lens, swells the bar and lights it, without '
      'building the look', (tester) async {
    final probe = _Probe();
    final selected = <int>[];
    await tester.pumpWidget(
      _app(
        _Controlled(
          onSelected: selected.add,
          style: GlassTabBarStyle(builder: probe.build),
        ),
      ),
    );
    final resting = tester.getRect(find.text('Tab 3')).width;
    final gesture = await tester.startGesture(_at(tester, 0));
    await tester.pump(_frame);
    final built = probe.builds;
    for (var i = 0; i < 30; i++) {
      await gesture.moveBy(const Offset(6, 0));
      await tester.pump(_frame);
    }
    expect(probe.lens.lift, greaterThan(0.9));
    expect(probe.details!.body.value.glow, isNotNull);
    final swell = tester.getRect(find.text('Tab 3')).width / resting;
    expect(swell, greaterThan(1.001));
    expect(probe.builds - built, lessThanOrEqualTo(1));
    await gesture.up();
    await _settle(tester);
    expect(selected, [2]);
    expect(probe.lens.lift, 0);
  });

  testWidgets('each tab reads as a tab of a tab bar; one copy of each '
      'is found', (tester) async {
    final semantics = tester.ensureSemantics();
    final selected = <int>[];
    await tester.pumpWidget(_app(_Controlled(onSelected: selected.add)));
    expect(find.text('Tab 1'), findsOneWidget);
    expect(
      find.semantics.byLabel('Tab 0').evaluate().single,
      matchesSemantics(
        label: 'Tab 0',
        role: SemanticsRole.tab,
        hasSelectedState: true,
        isSelected: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
        isFocusable: true,
        hasFocusAction: true,
        textDirection: TextDirection.ltr,
        rect: const Rect.fromLTRB(0, 0, 95, 62),
      ),
    );
    // The zones take their box sizes in the frame after they appear.
    await tester.pump();
    expect(
      tester
          .getRect(find.bySemanticsLabel('Tab 0'))
          .shift(-tester.getTopLeft(find.byType(GlassTabBar))),
      const Rect.fromLTRB(4, 0, 99, 62),
    );
    expect(
      find.semantics.byLabel('Tab 1').evaluate().single,
      matchesSemantics(
        label: 'Tab 1',
        role: SemanticsRole.tab,
        hasSelectedState: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
        isFocusable: true,
        hasFocusAction: true,
        textDirection: TextDirection.ltr,
      ),
    );
    tester.semantics.tap(find.semantics.byLabel('Tab 3'));
    await _settle(tester);
    expect(selected, [3]);
    semantics.dispose();
  });

  testWidgets('arrow keys move between the tabs from the right in a '
      'right-to-left bar and select the tab they reach; Enter and Space '
      'reselect it', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final selected = <int>[];
    var index = 1;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => _keys(
          GlassTabBar(
            destinations: _tabs(3),
            selectedIndex: index,
            focusNode: focus,
            onDestinationSelected: (next) {
              selected.add(next);
              setState(() => index = next);
            },
          ),
          direction: TextDirection.rtl,
        ),
      ),
    );
    expect(_at(tester, 0).dx, greaterThan(_at(tester, 2).dx));
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await _settle(tester);
    expect(selected, [2]);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(selected, [2, 2]);
    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await _settle(tester);
    expect(selected, [2, 2, 0]);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(selected, [2, 2, 0, 0]);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await _settle(tester);
    expect(selected, [2, 2, 0, 0]);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      isNot(contains('(2, null)')),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await _settle(tester);
    expect(selected, [2, 2, 0, 0, 2]);
  });

  testWidgets('without a callback a tap does nothing', (tester) async {
    await tester.pumpWidget(
      _app(
        GlassTabBar(
          destinations: _tabs(3),
          selectedIndex: 0,
          onDestinationSelected: null,
        ),
      ),
    );
    await tester.tapAt(_at(tester, 2));
    await _settle(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the selected tabs take the primary color; the theme styles '
      'the lens', (tester) async {
    Color colorOf(String text, {required bool lens}) {
      final elements = find.text(text, skipOffstage: false).evaluate().toList();
      final paragraph = elements[lens ? 1 : 0].renderObject! as RenderParagraph;
      return paragraph.text.style!.color!;
    }

    await tester.pumpWidget(
      _app(
        const _Controlled(),
        theme: GlassThemeData(
          primaryColor: const Color(0xFF123456),
          styles: [
            GlassTabBar.styleFrom(
              thumbColor: const Color(0xFF654321),
            ),
          ],
        ),
      ),
    );
    expect(
      colorOf('Tab 0', lens: true),
      isSameColorAs(const Color(0xFF123456)),
    );
    expect(
      colorOf('Tab 0', lens: false),
      isSameColorAs(const Color(0xFF0D0D0D)),
    );
    final surfaces = tester.widgetList<GlassSurface>(
      find.byType(GlassSurface),
    );
    expect(surfaces.last.glass.tint, isSameColorAs(const Color(0xFF654321)));
  });

  testWidgets('a disabled tab takes no tap', (tester) async {
    final selected = <int>[];
    await tester.pumpWidget(
      _app(
        GlassTabBar(
          destinations: [
            ..._tabs(2),
            const GlassTabDestination(
              icon: SizedBox.square(dimension: 24),
              label: Text('Off'),
              enabled: false,
            ),
          ],
          selectedIndex: 0,
          onDestinationSelected: selected.add,
        ),
      ),
    );
    await tester.tap(find.text('Off'));
    await _settle(tester);
    expect(selected, isEmpty);
  });

  testWidgets('a badge sits at the top trailing corner of the glyph', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        GlassTabBar(
          destinations: const [
            GlassTabDestination(
              icon: SizedBox.square(dimension: 24),
              label: Text('Mail'),
              badge: SizedBox(key: Key('badge'), width: 18, height: 18),
            ),
            GlassTabDestination(
              icon: SizedBox.square(dimension: 24),
              label: Text('Other'),
            ),
          ],
          selectedIndex: 1,
          onDestinationSelected: (_) {},
        ),
      ),
    );
    final badge = tester.getTopLeft(find.byKey(const Key('badge')));
    final title = tester.getCenter(find.text('Mail'));
    expect(badge.dx, closeTo(title.dx - 12 + 19, 0.5));
  });
}

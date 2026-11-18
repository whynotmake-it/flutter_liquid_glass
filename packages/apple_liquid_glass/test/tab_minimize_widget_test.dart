import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = Duration(milliseconds: 16);

class _Placement extends StatelessWidget {
  const _Placement();

  @override
  Widget build(BuildContext context) =>
      Text(GlassTabBar.accessoryPlacementOf(context).name);
}

Widget _app({
  required GlassTabBarMinimizeBehavior behavior,
  ScrollController? controller,
  int rows = 60,
  Widget? accessory,
  ValueChanged<int>? onSelected,
  TextDirection direction = TextDirection.ltr,
  bool reduceMotion = false,
}) => MediaQuery(
  data: const MediaQueryData(
    size: Size(402, 874),
    devicePixelRatio: 3,
    padding: EdgeInsets.only(top: 62, bottom: 34),
  ),
  child: Directionality(
    textDirection: direction,
    child: GlassScope(
      renderer: const FlatGlassRenderer(),
      child: MotionTraitsOverride(
        traits: MotionTraits(reduceMotion: reduceMotion),
        child: GlassTabScaffold(
          tabBar: GlassTabBar(
            minimizeBehavior: behavior,
            bottomAccessory: accessory,
            destinations: const [
              GlassTabDestination(
                icon: SizedBox.square(key: Key('glyph 0'), dimension: 24),
                label: Text('One'),
              ),
              GlassTabDestination(
                icon: SizedBox.square(dimension: 24),
                label: Text('Two'),
              ),
              GlassTabDestination(
                icon: SizedBox.square(dimension: 24),
                label: Text('Three'),
              ),
            ],
            selectedIndex: 0,
            onDestinationSelected: onSelected ?? (_) {},
          ),
          tabBuilder: (context, i) => GlassPageScaffold(
            child: GlassContentScroll(
              child: ListView(
                controller: controller,
                children: [
                  for (var r = 0; r < rows; r++)
                    SizedBox(key: ValueKey(r), height: 50),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(402 * 3, 874 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(_frame);
  }
}

Future<void> _dragUp(WidgetTester tester, double distance) async {
  final gesture = await tester.startGesture(const Offset(201, 400));
  for (var i = 0; i < 20; i++) {
    await gesture.moveBy(Offset(0, -distance / 20));
    await tester.pump(_frame);
  }
  await tester.pump(const Duration(milliseconds: 200));
  await gesture.up();
  await _settle(tester);
}

// The bar's own glass, in screen coordinates.
Rect _body(WidgetTester tester) {
  final body = find
      .descendant(
        of: find.byType(RawGlassSelector),
        matching: find.byType(GlassSurface),
      )
      .first;
  final rect =
      tester.widget<GlassSurface>(body).frame!.value.rect ??
      Offset.zero & tester.getSize(body);
  return rect.shift(tester.getTopLeft(body));
}

bool _expanded(WidgetTester tester) => _body(tester).width > 100;

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('a bar that does not opt in never minimizes', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(
      _app(behavior: GlassTabBarMinimizeBehavior.automatic),
    );
    await tester.pump();
    await _dragUp(tester, 300);
    expect(_expanded(tester), isTrue);
  });

  testWidgets('a user scroll shrinks the bar into a circle 28 points from '
      'the screen corner; a tap on it expands the bar', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(
      _app(behavior: GlassTabBarMinimizeBehavior.onScrollDown),
    );
    await tester.pump();
    expect(_expanded(tester), isTrue);
    await _dragUp(tester, 200);
    expect(_expanded(tester), isFalse);
    final circle = _body(tester);
    expect(circle.left, closeTo(28, 0.5));
    expect(circle.bottom, closeTo(874 - 28, 0.5));
    expect(circle.width, closeTo(48, 0.5));
    await tester.tapAt(circle.center);
    await _settle(tester);
    expect(_expanded(tester), isTrue);
  });

  testWidgets('a scroll the app drives never minimizes the bar', (
    tester,
  ) async {
    await _phone(tester);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        behavior: GlassTabBarMinimizeBehavior.onScrollDown,
        controller: controller,
      ),
    );
    await tester.pump();
    controller.jumpTo(800);
    await _settle(tester);
    expect(_expanded(tester), isTrue);
  });

  testWidgets('content with less than 96 points to scroll never minimizes '
      'the bar', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(
      _app(behavior: GlassTabBarMinimizeBehavior.onScrollDown, rows: 16),
    );
    await tester.pump();
    await _dragUp(tester, 200);
    expect(_expanded(tester), isTrue);
  });

  testWidgets('scrolling back to the top expands the bar', (tester) async {
    await _phone(tester);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        behavior: GlassTabBarMinimizeBehavior.onScrollDown,
        controller: controller,
      ),
    );
    await tester.pump();
    await _dragUp(tester, 200);
    expect(_expanded(tester), isFalse);
    controller.jumpTo(0);
    await _settle(tester);
    expect(_expanded(tester), isTrue);
  });

  testWidgets('an accessory stands above the bar and beside the circle '
      'once the bar has minimized', (tester) async {
    await _phone(tester);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _app(
        behavior: GlassTabBarMinimizeBehavior.onScrollDown,
        controller: controller,
        accessory: const SizedBox.expand(
          key: Key('accessory'),
          child: _Placement(),
        ),
      ),
    );
    await tester.pump();
    final expanded = tester.getRect(find.byKey(const Key('accessory')));
    expect(
      expanded,
      const Rect.fromLTWH(21 + 16, 874 - 21 - 62 - 8 - 48 + 8, 360 - 32, 32),
    );
    expect(find.text('expanded'), findsOneWidget);
    for (var i = 0; i < 3; i++) {
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();
    }
    final bottom = tester.getBottomLeft(find.byKey(const ValueKey(59))).dy;
    expect(bottom, closeTo(874 - 21 - 62 - 8 - 48, 0.5));
    controller.jumpTo(0);
    await tester.pump();
    await _dragUp(tester, 200);
    expect(find.text('inline'), findsOneWidget);
    final inline = tester.getRect(find.byKey(const Key('accessory')));
    expect(inline.left, closeTo(21 + 7 + 48 + 14 + 16, 0.5));
    expect(inline.right, closeTo(402 - 28 - 16, 0.5));
    expect(inline.top, closeTo(874 - 21 - 62 + 7 + 8, 0.5));
  });

  group('a finger on the circle', () {
    Future<Rect> minimized(
      WidgetTester tester, {
      List<int>? selected,
      bool reduceMotion = false,
    }) async {
      await _phone(tester);
      await tester.pumpWidget(
        _app(
          behavior: GlassTabBarMinimizeBehavior.onScrollDown,
          onSelected: selected?.add,
          reduceMotion: reduceMotion,
        ),
      );
      await tester.pump();
      await _dragUp(tester, 200);
      return _body(tester);
    }

    testWidgets('lifts it to 64 points, and however long it stays, the lift '
        'expands the bar and selects nothing', (tester) async {
      final selected = <int>[];
      final circle = await minimized(tester, selected: selected);
      final gesture = await tester.startGesture(circle.center);
      await _settle(tester);
      await tester.pump(const Duration(seconds: 2));
      await _settle(tester);
      expect(_body(tester).width, closeTo(64, 0.5));
      await gesture.up();
      await _settle(tester);
      expect(_expanded(tester), isTrue);
      expect(selected, isEmpty);
    });

    testWidgets('under Reduce Motion lifts nothing and still expands the '
        'bar', (tester) async {
      final circle = await minimized(tester, reduceMotion: true);
      final gesture = await tester.startGesture(circle.center);
      await _settle(tester);
      expect(_body(tester).width, closeTo(circle.width, 0.5));
      await gesture.up();
      await _settle(tester);
      expect(_expanded(tester), isTrue);
    });

    testWidgets('a quick tap expands the bar and selects nothing', (
      tester,
    ) async {
      final selected = <int>[];
      final circle = await minimized(tester, selected: selected);
      await tester.tapAt(circle.center);
      await _settle(tester);
      expect(_expanded(tester), isTrue);
      expect(selected, isEmpty);
    });

    testWidgets('moved along the bar, expands it under the finger and selects '
        'the tab it lifts over', (tester) async {
      final selected = <int>[];
      final circle = await minimized(tester, selected: selected);
      final gesture = await tester.startGesture(circle.center);
      await tester.pump(_frame);
      await gesture.moveBy(const Offset(4, 0));
      await tester.pump(_frame);
      await tester.pump(_frame);
      final early = _body(tester).width;
      expect(early, lessThan(200));
      for (var i = 0; i < 20; i++) {
        await gesture.moveBy(const Offset(7, 0));
        await tester.pump(_frame);
      }
      await _settle(tester);
      expect(_body(tester).width, closeTo(274, 8));
      expect(selected, isEmpty);
      await gesture.up();
      await _settle(tester);
      expect(selected, [1]);
      expect(_expanded(tester), isTrue);
    });

    testWidgets('in a right-to-left bar stands at the right', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(
        _app(
          behavior: GlassTabBarMinimizeBehavior.onScrollDown,
          direction: TextDirection.rtl,
        ),
      );
      await tester.pump();
      await _dragUp(tester, 200);
      final circle = _body(tester);
      expect(circle.right, closeTo(402 - 28, 0.5));
      expect(circle.width, closeTo(48, 0.5));
    });

    testWidgets('leaves what is beside the circle to its owner', (
      tester,
    ) async {
      final circle = await minimized(tester);
      final beside = circle.center + const Offset(120, 0);
      final at = tester.hitTestOnBinding(beside);
      expect(
        at.path.any(
          (entry) => entry.target.runtimeType.toString().contains('Selector'),
        ),
        isFalse,
      );
    });
  });

  group('the morph', () {
    Future<void> scrolled(WidgetTester tester) async {
      await _phone(tester);
      await tester.pumpWidget(
        _app(behavior: GlassTabBarMinimizeBehavior.onScrollDown),
      );
      await tester.pump();
      final gesture = await tester.startGesture(const Offset(201, 400));
      for (var i = 0; i < 20; i++) {
        await gesture.moveBy(const Offset(0, -10));
        await tester.pump(_frame);
      }
      await gesture.up();
    }

    testWidgets('keeps the selector and its state from start to end', (
      tester,
    ) async {
      await _phone(tester);
      await tester.pumpWidget(
        _app(behavior: GlassTabBarMinimizeBehavior.onScrollDown),
      );
      await tester.pump();
      final before = tester.state(find.byType(RawGlassSelector));
      await _dragUp(tester, 200);
      expect(tester.state(find.byType(RawGlassSelector)), same(before));
      await tester.tapAt(_body(tester).center);
      await _settle(tester);
      expect(tester.state(find.byType(RawGlassSelector)), same(before));
    });

    testWidgets('moves the bar without a jump and centers the glyph in the '
        'circle', (tester) async {
      await scrolled(tester);
      final glyph = find.byKey(const Key('glyph 0'), skipOffstage: false).last;
      var last = tester.getCenter(glyph);
      for (var i = 0; i < 120; i++) {
        await tester.pump(_frame);
        final now = tester.getCenter(glyph);
        expect((now - last).distance, lessThan(30));
        last = now;
      }
      final circle = _body(tester);
      expect((last - circle.center).distance, lessThan(0.5));
    });

    testWidgets('carries the accessory content with its glass, and a touch '
        'beside the circle reaches the accessory', (tester) async {
      var taps = 0;
      await _phone(tester);
      await tester.pumpWidget(
        _app(
          behavior: GlassTabBarMinimizeBehavior.onScrollDown,
          accessory: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
            child: const SizedBox.expand(key: Key('accessory')),
          ),
        ),
      );
      await tester.pump();
      final accessory = find.byKey(const Key('accessory'));
      final top = tester.getRect(accessory);
      final gesture = await tester.startGesture(const Offset(201, 400));
      for (var i = 0; i < 20; i++) {
        await gesture.moveBy(const Offset(0, -10));
        await tester.pump(_frame);
      }
      await gesture.up();
      var last = tester.getCenter(accessory);
      for (var i = 0; i < 120; i++) {
        await tester.pump(_frame);
        final now = tester.getCenter(accessory);
        expect((now - last).distance, lessThan(30));
        last = now;
      }
      expect(last.dy, greaterThan(top.center.dy + 40));
      await tester.tapAt(last);
      await _settle(tester);
      expect(taps, 1);
    });

    testWidgets('brings the lens back as the bar rests', (tester) async {
      await _phone(tester);
      await tester.pumpWidget(
        _app(behavior: GlassTabBarMinimizeBehavior.onScrollDown),
      );
      await tester.pump();
      GlassFrame lens() => tester
          .widget<GlassSurface>(
            find
                .descendant(
                  of: find.byType(RawGlassSelector),
                  matching: find.byType(GlassSurface),
                )
                .last,
          )
          .frame!
          .value;
      expect(lens().opacity, 1);
      await _dragUp(tester, 200);
      expect(lens().opacity, 0);
      await tester.tapAt(_body(tester).center);
      await _settle(tester);
      expect(lens().opacity, 1);
    });
  });
}

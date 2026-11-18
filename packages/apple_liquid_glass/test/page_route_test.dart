import 'dart:async';

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = Duration(milliseconds: 16);

Widget _app(
  GlobalKey<NavigatorState> navigator, {
  bool reduceMotion = false,
  TextDirection direction = TextDirection.ltr,
}) => WidgetsApp(
  navigatorKey: navigator,
  color: const Color(0xFF000000),
  pageRouteBuilder: <T>(settings, builder) =>
      GlassPageRoute<T>(builder: builder, settings: settings),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
    child: Directionality(
      textDirection: direction,
      child: GlassScope(renderer: const FlatGlassRenderer(), child: child!),
    ),
  ),
  home: const ColoredBox(
    color: Color(0xFFFFFFFF),
    child: Center(child: Text('Home')),
  ),
);

Widget _page(String text) => ColoredBox(
  color: const Color(0xFFEEEEEE),
  child: Center(child: Text(text)),
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

// The test's frames run on a fake clock the engine clock does not follow;
// pinning both to it lets pointer time stamps space a drag as on a device.
Duration Function() _deviceTime(WidgetTester tester) {
  Duration now() =>
      Duration(microseconds: tester.binding.clock.now().microsecondsSinceEpoch);
  MotionClock.debugEngineNow = now;
  MotionClock.debugPointerClockOffset = () => Duration.zero;
  addTearDown(() {
    MotionClock.debugEngineNow = null;
    MotionClock.debugPointerClockOffset = null;
  });
  return now;
}

Future<void> _swipe(
  WidgetTester tester,
  Duration Function() now,
  Offset from,
  Offset by,
) async {
  const steps = 12;
  final gesture = await tester.createGesture();
  await gesture.down(from, timeStamp: now());
  for (var i = 0; i < steps; i++) {
    await tester.pump(_frame);
    await gesture.moveBy(by / steps.toDouble(), timeStamp: now());
  }
  await gesture.up(timeStamp: now());
}

double _x(WidgetTester tester, String text) =>
    tester.getCenter(find.text(text)).dx;

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('a push slides the page in over the page below, which moves '
      'aside by the width less 0.7 of it', (tester) async {
    await _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigator));
    var pushed = false;
    unawaited(
      navigator.currentState!
          .push(GlassPageRoute<void>(builder: (_) => _page('Next')))
          .then((_) => pushed = true),
    );
    await tester.pump();
    await tester.pump(_frame);
    await tester.pump(_frame);
    expect(_x(tester, 'Next'), greaterThan(201));
    expect(_x(tester, 'Home'), lessThan(201));
    await _settle(tester);
    expect(_x(tester, 'Next'), 201);
    expect(find.text('Home'), findsNothing);
    final route = ModalRoute.of(tester.element(find.text('Next')))!;
    expect(route.animation!.status, AnimationStatus.completed);
    expect(pushed, isFalse);
  });

  testWidgets('the page below sits 121 points aside under a page that '
      'covers it', (tester) async {
    await _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigator));
    final route = GlassPageRoute<void>(builder: (_) => _page('Next'));
    unawaited(navigator.currentState!.push(route));
    await _settle(tester);
    route.beginInteraction();
    await tester.pump();
    expect(_x(tester, 'Home'), 201 - 121);
    route.endInteraction();
    await tester.pump();
  });

  testWidgets('the page below keeps its state under a pushed page and '
      'after the pop', (tester) async {
    await _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigator));
    final home = tester.element(find.text('Home'));
    unawaited(
      navigator.currentState!.push(
        GlassPageRoute<void>(builder: (_) => _page('Next')),
      ),
    );
    await _settle(tester);
    expect(tester.element(find.text('Home', skipOffstage: false)), home);
    navigator.currentState!.pop();
    await _settle(tester);
    expect(tester.element(find.text('Home')), home);
  });

  testWidgets('a pop without a finger slides the page out, then it goes', (
    tester,
  ) async {
    await _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigator));
    String? result;
    unawaited(
      navigator.currentState!
          .push(GlassPageRoute<String>(builder: (_) => _page('Next')))
          .then((value) => result = value),
    );
    await _settle(tester);
    navigator.currentState!.pop('done');
    await tester.pump();
    await tester.pump(_frame);
    await tester.pump(_frame);
    expect(_x(tester, 'Next'), greaterThan(201));
    expect(find.text('Home'), findsOneWidget);
    await _settle(tester);
    expect(find.text('Next'), findsNothing);
    expect(_x(tester, 'Home'), 201);
    expect(result, 'done');
  });

  testWidgets('a flick from the leading edge pops the page; held still '
      'before the release it returns', (tester) async {
    await _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigator));
    unawaited(
      navigator.currentState!.push(
        GlassPageRoute<void>(builder: (_) => _page('Next')),
      ),
    );
    await _settle(tester);
    final now = _deviceTime(tester);

    Future<TestGesture> flick() async {
      final gesture = await tester.createGesture();
      await gesture.down(const Offset(10, 400), timeStamp: now());
      for (var i = 0; i < 5; i++) {
        await tester.pump(_frame);
        await gesture.moveBy(const Offset(20, 0), timeStamp: now());
      }
      await tester.pump(_frame);
      return gesture;
    }

    final held = await flick();
    expect(find.text('Home'), findsOneWidget);
    expect(_x(tester, 'Next'), greaterThan(201 + 60));
    // A finger held still on glass still reports where it is.
    for (var i = 0; i < 25; i++) {
      await tester.pump(_frame);
      await held.moveBy(Offset.zero, timeStamp: now());
    }
    await held.up(timeStamp: now());
    await _settle(tester);
    expect(_x(tester, 'Next'), 201);
    expect(find.text('Home'), findsNothing);

    final flung = await flick();
    await flung.up(timeStamp: now());
    await _settle(tester);
    expect(find.text('Next'), findsNothing);
    expect(_x(tester, 'Home'), 201);
  });

  testWidgets('a pop asked for under a finger or while the page returns '
      'takes the page out', (tester) async {
    await _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigator));
    unawaited(
      navigator.currentState!.push(
        GlassPageRoute<void>(builder: (_) => _page('Next')),
      ),
    );
    await _settle(tester);
    final now = _deviceTime(tester);

    final gesture = await tester.createGesture();
    await gesture.down(const Offset(10, 400), timeStamp: now());
    for (var i = 0; i < 4; i++) {
      await tester.pump(_frame);
      await gesture.moveBy(const Offset(10, 0), timeStamp: now());
    }
    await tester.pump(_frame);
    navigator.currentState!.pop();
    await tester.pump(_frame);
    expect(find.text('Next'), findsOneWidget);
    await gesture.up(timeStamp: now());
    await _settle(tester);
    expect(find.text('Next'), findsNothing);

    unawaited(
      navigator.currentState!.push(
        GlassPageRoute<void>(builder: (_) => _page('Again')),
      ),
    );
    await _settle(tester);
    final again = await tester.createGesture();
    await again.down(const Offset(10, 400), timeStamp: now());
    for (var i = 0; i < 10; i++) {
      await tester.pump(_frame);
      await again.moveBy(const Offset(3, 0), timeStamp: now());
    }
    await again.up(timeStamp: now());
    await tester.pump(_frame);
    await tester.pump(_frame);
    expect(_x(tester, 'Again'), greaterThan(201));
    navigator.currentState!.pop();
    await _settle(tester);
    expect(find.text('Again'), findsNothing);
    expect(_x(tester, 'Home'), 201);
  });

  testWidgets('a swipe along the page pops it from anywhere; a steep or '
      'backward one does not', (tester) async {
    await _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigator));
    unawaited(
      navigator.currentState!.push(
        GlassPageRoute<void>(builder: (_) => _page('Next')),
      ),
    );
    await _settle(tester);
    final now = _deviceTime(tester);
    await _swipe(tester, now, const Offset(200, 400), const Offset(-150, 0));
    await _swipe(tester, now, const Offset(200, 400), const Offset(100, 100));
    await _settle(tester);
    expect(_x(tester, 'Next'), 201);
    expect(find.text('Home'), findsNothing);
    await _swipe(tester, now, const Offset(200, 400), const Offset(150, 30));
    await _settle(tester);
    expect(find.text('Next'), findsNothing);
  });

  testWidgets('the page keeps its taps, and its vertical list keeps drags '
      'steeper than its slop allows', (tester) async {
    await _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigator));
    var taps = 0;
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    unawaited(
      navigator.currentState!.push(
        GlassPageRoute<void>(
          builder: (_) => ColoredBox(
            color: const Color(0xFFEEEEEE),
            child: ListView(
              controller: scroll,
              children: [
                GestureDetector(
                  onTap: () => taps++,
                  child: const SizedBox(height: 100, child: Text('Row')),
                ),
                const SizedBox(height: 2000),
              ],
            ),
          ),
        ),
      ),
    );
    await _settle(tester);
    final now = _deviceTime(tester);
    await tester.tap(find.text('Row'));
    await tester.pump();
    expect(taps, 1);
    await _swipe(tester, now, const Offset(200, 600), const Offset(150, -150));
    await _settle(tester);
    expect(scroll.offset, greaterThan(0));
    expect(find.text('Home'), findsNothing);
    await _swipe(tester, now, const Offset(200, 600), const Offset(200, -40));
    await _settle(tester);
    expect(find.text('Row', skipOffstage: false), findsNothing);
  });

  testWidgets('under Reduce Motion a push cross-fades instead of sliding', (
    tester,
  ) async {
    await _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigator, reduceMotion: true));
    unawaited(
      navigator.currentState!.push(
        GlassPageRoute<void>(builder: (_) => _page('Next')),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(_x(tester, 'Next'), 201);
    expect(_x(tester, 'Home'), 201);
    final fades = tester.layers.whereType<OpacityLayer>().map(
      (layer) => layer.alpha!,
    );
    expect(fades.where((alpha) => alpha > 0 && alpha < 255), hasLength(2));
    await _settle(tester);
    expect(find.text('Home'), findsNothing);
  });

  testWidgets('the page builds in the build phase, outside any layout', (
    tester,
  ) async {
    await _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigator));
    var underLayout = true;
    unawaited(
      navigator.currentState!.push(
        GlassPageRoute<void>(
          builder: (context) {
            underLayout =
                context.findAncestorWidgetOfExactType<LayoutBuilder>() != null;
            return _page('Next');
          },
        ),
      ),
    );
    await tester.pump();
    expect(underLayout, isFalse);
  });

  test('a transition counts from the call, or a period before a late first '
      'frame', () {
    expect(
      PageMotion.transitionOrigin(
        call: 1,
        firstFrame: 1.016,
        framePeriod: 1 / 60,
      ),
      1,
    );
    expect(
      PageMotion.transitionOrigin(
        call: 1,
        firstFrame: 1.1,
        framePeriod: 1 / 60,
      ),
      closeTo(1.1 - 1 / 60, 1e-12),
    );
    expect(
      PageMotion.transitionOrigin(call: 1, firstFrame: 1.1, framePeriod: null),
      1,
    );
  });

  testWidgets('right to left, the page slides in from the left', (
    tester,
  ) async {
    await _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigator, direction: TextDirection.rtl));
    unawaited(
      navigator.currentState!.push(
        GlassPageRoute<void>(builder: (_) => _page('Next')),
      ),
    );
    await tester.pump();
    await tester.pump(_frame);
    await tester.pump(_frame);
    expect(_x(tester, 'Next'), lessThan(201));
    expect(_x(tester, 'Home'), greaterThan(201));
    await _settle(tester);
    expect(_x(tester, 'Next'), 201);
  });
}

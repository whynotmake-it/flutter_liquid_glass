import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _card = Key('card');
const _page = Key('page');

Widget _app(GlobalKey<NavigatorState> navigator, MotionSource link) =>
    WidgetsApp(
      navigatorKey: navigator,
      color: const Color(0xFF000000),
      pageRouteBuilder: <T>(settings, builder) =>
          GlassPageRoute<T>(builder: builder, settings: settings),
      builder: (context, child) =>
          GlassScope(renderer: const FlatGlassRenderer(), child: child!),
      home: ColoredBox(
        color: const Color(0xFFF2F2F7),
        child: Align(
          alignment: const Alignment(0, -0.3),
          child: GlassZoomSource(
            source: link,
            borderRadius: 16,
            child: const SizedBox(
              key: _card,
              width: 160,
              height: 100,
              child: ColoredBox(color: Color(0xFF3478F6)),
            ),
          ),
        ),
      ),
    );

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(402, 874) * 3;
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
}

Future<void> _frames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Route<void> _route(MotionSource link) => GlassPageRoute<void>(
  source: link,
  builder: (context) => const ColoredBox(
    key: _page,
    color: Color(0xFFFFFFFF),
    child: Center(child: Text('Detail')),
  ),
);

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('the page grows out of the card and fills the screen; the card '
      'hides meanwhile', (tester) async {
    _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    final link = MotionSource();
    await tester.pumpWidget(_app(navigator, link));
    final card = tester.getRect(find.byKey(_card));
    navigator.currentState!.push(_route(link));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final early = tester.getRect(find.byKey(_page));
    expect(early.width, lessThan(402));
    expect(early.width, greaterThan(card.width - 1));
    await _frames(tester, 90);
    expect(
      tester.getRect(find.byKey(_page)),
      const Rect.fromLTWH(0, 0, 402, 874),
    );
    expect(link.isHidden, isTrue);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a pop zooms back into the card, which shows again', (
    tester,
  ) async {
    _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    final link = MotionSource();
    await tester.pumpWidget(_app(navigator, link));
    final card = tester.getRect(find.byKey(_card));
    navigator.currentState!.push(_route(link));
    await _frames(tester, 90);
    navigator.currentState!.pop();
    await _frames(tester, 10);
    final shrinking = tester.getRect(find.byKey(_page));
    expect(shrinking.width, lessThan(402));
    await _frames(tester, 90);
    expect(find.byKey(_page), findsNothing);
    expect(link.isHidden, isFalse);
    expect(tester.getRect(find.byKey(_card)), card);
  });

  testWidgets('a drag down past the threshold dismisses, a short one '
      'returns', (tester) async {
    _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    final link = MotionSource();
    await tester.pumpWidget(_app(navigator, link));
    navigator.currentState!.push(_route(link));
    await _frames(tester, 90);
    final gesture = await tester.startGesture(const Offset(200, 400));
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(0, 8));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.getRect(find.byKey(_page)).width, lessThan(402));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await _frames(tester, 90);
    expect(find.byKey(_page), findsOneWidget, reason: 'a short drag returns');
    expect(
      tester.getRect(find.byKey(_page)),
      const Rect.fromLTWH(0, 0, 402, 874),
    );
    await tester.flingFrom(const Offset(200, 300), const Offset(0, 300), 1500);
    await _frames(tester, 90);
    expect(find.byKey(_page), findsNothing);
  });

  testWidgets('without an attached source the page slides', (tester) async {
    _phone(tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(navigator, MotionSource()));
    navigator.currentState!.push(_route(MotionSource()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final rect = tester.getRect(find.byKey(_page));
    expect(rect.width, closeTo(402, 1e-9), reason: 'a slide keeps the width');
    expect(rect.left, greaterThan(0));
    await _frames(tester, 90);
  });
}

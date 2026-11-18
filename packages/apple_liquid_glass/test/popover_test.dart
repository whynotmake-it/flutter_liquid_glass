import 'dart:async';

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

const _frame = Duration(milliseconds: 16);
const _source = Key('source');

Widget _app({
  required void Function(BuildContext context) onPresent,
  GlassRenderer renderer = const FlatGlassRenderer(),
  Alignment at = Alignment.bottomCenter,
}) => WidgetsApp(
  color: const Color(0xFF000000),
  pageRouteBuilder: <T>(settings, builder) =>
      GlassPageRoute<T>(builder: builder, settings: settings),
  builder: (context, child) => GlassScope(renderer: renderer, child: child!),
  home: ColoredBox(
    color: const Color(0xFFF2F2F7),
    child: Align(
      alignment: at,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 120),
        child: Builder(
          builder: (context) => GestureDetector(
            key: _source,
            behavior: HitTestBehavior.opaque,
            onTap: () => onPresent(context),
            child: const SizedBox(width: 120, height: 48),
          ),
        ),
      ),
    ),
  ),
);

void _screen(WidgetTester tester, Size size) {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(_frame);
  }
}

void main() {
  setUp(MotionClock.debugReset);

  group('an action sheet from a source', () {
    testWidgets('is a popover 240 wide above its source without the cancel '
        'action, which a tap outside chooses', (tester) async {
      _screen(tester, const Size(402, 874));
      GlassAlertAction? result;
      const cancel = GlassAlertAction.cancel(child: Text('Cancel'));
      await tester.pumpWidget(
        _app(
          onPresent: (context) => unawaited(
            showGlassActionSheet(
              context,
              title: const Text('Share'),
              anchor: context,
              actions: const [
                cancel,
                GlassAlertAction(child: Text('Copy')),
                GlassAlertAction(child: Text('Mail')),
              ],
            ).then((value) => result = value),
          ),
        ),
      );
      await tester.tap(find.byKey(_source));
      await _settle(tester);
      expect(find.text('Cancel'), findsNothing);
      final source = tester.getRect(find.byKey(_source));
      final copy = tester.getRect(find.text('Copy'));
      final mail = tester.getRect(find.text('Mail'));
      expect(mail.bottom, lessThan(source.top));
      expect(copy.top, lessThan(mail.top));
      final card = tester.getRect(
        find.ancestor(
          of: find.text('Copy'),
          matching: find.byType(ClipRSuperellipse),
        ),
      );
      expect(card.width, 240);
      expect(card.center.dx, closeTo(source.center.dx, 0.5));
      expect(source.top - card.bottom, closeTo(13, 0.5));
      await tester.tapAt(const Offset(20, 100));
      await _settle(tester);
      expect(result, same(cancel));
      expect(find.text('Copy'), findsNothing);
    });

    testWidgets('a tap chooses an action; the popover does not lift under '
        'the finger', (tester) async {
      _screen(tester, const Size(402, 874));
      GlassAlertAction? result;
      await tester.pumpWidget(
        _app(
          onPresent: (context) => unawaited(
            showGlassActionSheet(
              context,
              anchor: context,
              actions: const [
                GlassAlertAction(child: Text('Copy')),
                GlassAlertAction(child: Text('Mail')),
              ],
            ).then((value) => result = value),
          ),
        ),
      );
      await tester.tap(find.byKey(_source));
      await _settle(tester);
      final rest = tester.getRect(find.text('Copy'));
      final gesture = await tester.startGesture(rest.center);
      await _settle(tester);
      expect(tester.getRect(find.text('Copy')), rest);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await gesture.up();
      await _settle(tester);
      expect((result?.child as Text?)?.data, 'Copy');
    });

    testWidgets('an anchor that is gone is refused', (tester) async {
      _screen(tester, const Size(402, 874));
      final navigator = GlobalKey<NavigatorState>();
      late BuildContext stale;
      Widget app({required bool shown}) => WidgetsApp(
        navigatorKey: navigator,
        color: const Color(0xFF000000),
        pageRouteBuilder: <T>(settings, builder) =>
            GlassPageRoute<T>(builder: builder, settings: settings),
        home: shown
            ? Builder(
                builder: (context) {
                  stale = context;
                  return const SizedBox();
                },
              )
            : const SizedBox(),
      );
      await tester.pumpWidget(app(shown: true));
      await tester.pumpWidget(app(shown: false));
      expect(
        () => showGlassActionSheet(
          navigator.currentContext!,
          anchor: stale,
          actions: const [GlassAlertAction(child: Text('Copy'))],
        ),
        throwsFlutterError,
      );
    });
  });

  group('showGlassPopover', () {
    testWidgets('on a wide screen points its content at the source and '
        'closes on a tap outside and on Escape', (tester) async {
      _screen(tester, const Size(1024, 1366));
      Object? result = 'pending';
      await tester.pumpWidget(
        _app(
          at: Alignment.topCenter,
          onPresent: (context) => unawaited(
            showGlassPopover<String>(
              context,
              anchor: context,
              builder: (context) => const SizedBox(
                width: 300,
                height: 200,
                child: Center(child: Text('Details')),
              ),
            ).then((value) => result = value),
          ),
        ),
      );
      await tester.tap(find.byKey(_source));
      await _settle(tester);
      final source = tester.getRect(find.byKey(_source));
      final content = tester.getRect(
        find.ancestor(
          of: find.text('Details'),
          matching: find.byType(ClipRSuperellipse),
        ),
      );
      expect(content.size, const Size(300, 200));
      expect(content.top - source.bottom, closeTo(13, 0.5));
      expect(content.center.dx, closeTo(source.center.dx, 0.5));
      await tester.tapAt(const Offset(40, 1200));
      await _settle(tester);
      expect(find.text('Details'), findsNothing);
      expect(result, isNull);

      await tester.tap(find.byKey(_source));
      await _settle(tester);
      expect(find.text('Details'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(tester);
      expect(find.text('Details'), findsNothing);
    });

    testWidgets('in a navigator away from the corner of the screen it points '
        'at the source in its first frame', (tester) async {
      _screen(tester, const Size(1024, 1366));
      await tester.pumpWidget(
        WidgetsApp(
          color: const Color(0xFF000000),
          builder: (context, child) => GlassScope(
            renderer: const FlatGlassRenderer(),
            child: Padding(
              padding: const EdgeInsets.only(left: 240, top: 160),
              child: Navigator(
                onGenerateRoute: (settings) => GlassPageRoute<void>(
                  builder: (context) => Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(100),
                      child: Builder(
                        builder: (context) => GestureDetector(
                          key: _source,
                          behavior: HitTestBehavior.opaque,
                          onTap: () => unawaited(
                            showGlassPopover<void>(
                              context,
                              anchor: context,
                              level: PresentationLevel.page,
                              builder: (context) => const SizedBox(
                                width: 300,
                                height: 200,
                                child: Center(child: Text('Details')),
                              ),
                            ),
                          ),
                          child: const SizedBox(width: 120, height: 48),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(_source));
      await tester.pump();
      final source = tester.getRect(find.byKey(_source));
      Rect content() => tester.getRect(
        find.ancestor(
          of: find.text('Details'),
          matching: find.byType(ClipRSuperellipse),
        ),
      );
      final first = content();
      await _settle(tester);
      final settled = content();
      expect(settled.top - source.bottom, closeTo(13, 0.5));
      expect(settled.center.dx, closeTo(source.center.dx, 0.5));
      // It grows out of the arrow's tip under the source's center.
      expect(first.center.dx, closeTo(source.center.dx, 0.5));
      expect(first.top, greaterThanOrEqualTo(source.bottom));
    });

    testWidgets('on a phone presents a sheet unless it is told not to', (
      tester,
    ) async {
      _screen(tester, const Size(402, 874));
      var adapts = true;
      await tester.pumpWidget(
        _app(
          at: Alignment.topCenter,
          onPresent: (context) => unawaited(
            showGlassPopover<void>(
              context,
              anchor: context,
              adaptsToSheet: adapts,
              builder: (context) =>
                  const SizedBox(width: 200, height: 100, child: Text('Hi')),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(_source));
      await _settle(tester);
      expect(GlassSheet.maybeOf(tester.element(find.text('Hi'))), isNotNull);
      Navigator.of(tester.element(find.text('Hi'))).pop();
      await _settle(tester);
      adapts = false;
      await tester.tap(find.byKey(_source));
      await _settle(tester);
      expect(GlassSheet.maybeOf(tester.element(find.text('Hi'))), isNull);
      expect(tester.getSize(find.text('Hi')).width, 200);
    });

    testWidgets('on the liquid renderer the glass is shaded from the '
        "popover's outline, arrow included", (tester) async {
      _screen(tester, const Size(1024, 1366));
      await tester.pumpWidget(
        _app(
          at: Alignment.topCenter,
          renderer: const LiquidGlassRenderer(),
          onPresent: (context) => unawaited(
            showGlassPopover<void>(
              context,
              anchor: context,
              builder: (context) => const SizedBox(width: 300, height: 200),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(_source));
      await _settle(tester);
      final layer = tester
          .widgetList<LiquidGlassLayer>(find.byType(LiquidGlassLayer))
          .last
          .frame!
          .value;
      expect(layer.field, isNotNull);
      final shape = tester
          .widgetList<LiquidGlass>(find.byType(LiquidGlass))
          .last
          .frame!
          .value;
      expect(shape.rect!.size, const Size(300, 213));
    });
  });
}

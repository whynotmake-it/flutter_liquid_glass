import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

Widget _list(
  MotionScroll scroll, {
  ScrollController? controller,
  int count = 50,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: NotificationListener<Notification>(
    onNotification: scroll.handle,
    child: ListView(
      controller: controller,
      children: [
        for (var i = 0; i < count; i++) SizedBox(height: 50, child: Text('$i')),
      ],
    ),
  ),
);

void main() {
  testWidgets('a drag reads as dragging, its fling as decelerating, then '
      'idle, and a selection hears each frame', (tester) async {
    final scroll = MotionScroll();
    await tester.pumpWidget(_list(scroll));
    await tester.pump();
    expect(scroll.phase, MotionScrollPhase.idle);
    expect(scroll.metrics!.pixels, 0);
    final phase = scroll.select((s) => s.phase);
    final phases = <MotionScrollPhase>[];
    void heard() => phases.add(phase.value);
    phase.addListener(heard);
    addTearDown(() => phase.removeListener(heard));
    await tester.timedDrag(
      find.byType(ListView),
      const Offset(0, -300),
      const Duration(milliseconds: 100),
    );
    await tester.pumpAndSettle();
    expect(phases, [
      MotionScrollPhase.dragging,
      MotionScrollPhase.decelerating,
      MotionScrollPhase.idle,
    ]);
    expect(scroll.metrics!.pixels, greaterThan(200));
    expect(scroll.metrics!.hasContentDimensions, isTrue);
  });

  testWidgets('a render listener hears a scroll before the frame paints', (
    tester,
  ) async {
    final scroll = MotionScroll();
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_list(scroll, controller: controller));
    final pixels = scroll.select((s) => s.metrics?.pixels ?? 0);
    final heard = <double>[];
    void listener() => heard.add(pixels.value);
    pixels.addRenderListener(listener);
    addTearDown(() => pixels.removeRenderListener(listener));
    controller.jumpTo(120);
    await tester.pump();
    expect(heard, [120]);
  });

  testWidgets('a drag released without a fling goes idle', (tester) async {
    final scroll = MotionScroll();
    await tester.pumpWidget(_list(scroll));
    final gesture = await tester.startGesture(const Offset(400, 300));
    await gesture.moveBy(const Offset(0, -40));
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    expect(scroll.phase, MotionScrollPhase.dragging);
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(scroll.phase, MotionScrollPhase.idle);
  });

  testWidgets('the app moving the content reads as programmatic', (
    tester,
  ) async {
    final scroll = MotionScroll();
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(_list(scroll, controller: controller));
    controller
        .animateTo(
          300,
          duration: const Duration(milliseconds: 200),
          curve: Curves.linear,
        )
        .ignore();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(scroll.phase, MotionScrollPhase.programmatic);
    await tester.pumpAndSettle();
    expect(scroll.phase, MotionScrollPhase.idle);
    expect(scroll.metrics!.pixels, 300);
    expect(scroll.position, same(controller.position));
  });

  testWidgets('only depth 0 is heard unless the predicate says otherwise', (
    tester,
  ) async {
    final outer = MotionScroll();
    final inner = MotionScroll(
      predicate: (notification) => notification.depth == 1,
    );
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: NotificationListener<Notification>(
          onNotification: (n) => outer.handle(n) || inner.handle(n),
          child: SingleChildScrollView(
            child: SizedBox(
              height: 300,
              child: ListView(
                controller: controller,
                children: [
                  for (var i = 0; i < 50; i++) const SizedBox(height: 50),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final before = outer.metrics;
    controller.jumpTo(120);
    await tester.pump();
    expect(inner.metrics!.pixels, 120);
    expect(outer.metrics, same(before));
  });

  testWidgets('new content reports its extents without a scroll', (
    tester,
  ) async {
    final scroll = MotionScroll();
    Widget page(double height) => Directionality(
      textDirection: TextDirection.ltr,
      child: NotificationListener<Notification>(
        onNotification: scroll.handle,
        child: SingleChildScrollView(child: SizedBox(height: height)),
      ),
    );
    await tester.pumpWidget(page(1000));
    await tester.pump();
    expect(scroll.metrics!.maxScrollExtent, 400);
    await tester.pumpWidget(page(1400));
    await tester.pump();
    expect(scroll.metrics!.maxScrollExtent, 800);
    expect(scroll.phase, MotionScrollPhase.idle);
  });
}

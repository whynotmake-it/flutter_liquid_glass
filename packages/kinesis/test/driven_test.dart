import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

Widget _app(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(alignment: Alignment.topLeft, child: child),
);

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('drives a chain of render-object widgets without building', (
    tester,
  ) async {
    final padding = MotionValue<double>(0);
    final opacity = MotionValue<double>(1);
    await tester.pumpWidget(
      _app(
        MotionDriven(
          template: () => Padding(
            padding: EdgeInsets.all(padding.value),
            child: Opacity(opacity: opacity.value),
          ),
          child: const SizedBox(key: ValueKey('child'), width: 20, height: 20),
        ),
      ),
    );
    final renderPadding = tester.renderObject<RenderPadding>(
      find.byType(MotionDriven),
    );
    final renderOpacity = renderPadding.child! as RenderOpacity;
    final rebuilt = <Widget>[];
    debugOnRebuildDirtyWidget = (element, _) => rebuilt.add(element.widget);
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    withSpring(const Spring.response(0.3), () {
      padding.target = 10;
      opacity.target = 0.5;
    });
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 50));
    final inset = tester.getTopLeft(find.byKey(const ValueKey('child'))).dx;
    expect(inset, closeTo(padding.value, 1e-9));
    expect(inset, greaterThan(0));
    expect(renderOpacity.opacity, closeTo(opacity.value, 1e-9));
    await tester.pumpAndSettle();
    debugOnRebuildDirtyWidget = null;
    expect(rebuilt, isEmpty);
    expect(tester.getTopLeft(find.byKey(const ValueKey('child'))).dx, 10);
    expect(renderOpacity.opacity, 0.5);
    expect(
      tester.renderObject(find.byType(MotionDriven)),
      same(renderPadding),
    );
  });

  testWidgets('a rebuilt MotionDriven follows its new template', (
    tester,
  ) async {
    final first = MotionValue<double>(4);
    final second = MotionValue<double>(12);
    Widget driven(MotionValue<double> value) => _app(
      MotionDriven(
        template: () => Padding(padding: EdgeInsets.all(value.value)),
        child: const SizedBox(key: ValueKey('child'), width: 20, height: 20),
      ),
    );
    await tester.pumpWidget(driven(first));
    expect(tester.getTopLeft(find.byKey(const ValueKey('child'))).dx, 4);
    await tester.pumpWidget(driven(second));
    expect(tester.getTopLeft(find.byKey(const ValueKey('child'))).dx, 12);
    second.snap(second.clock.now, 6);
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.getTopLeft(find.byKey(const ValueKey('child'))).dx, 6);
  });

  testWidgets('a template that changes its depth asserts', (tester) async {
    final deep = MotionValue<double>(0);
    await tester.pumpWidget(
      _app(
        MotionDriven(
          template: () => deep.value > 0
              ? const Padding(
                  padding: EdgeInsets.zero,
                  child: Opacity(opacity: 1),
                )
              : const Padding(padding: EdgeInsets.zero),
          child: const SizedBox(width: 20, height: 20),
        ),
      ),
    );
    deep.snap(deep.clock.now, 1);
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isAssertionError);
  });

  testWidgets('under a muted TickerMode it stops following', (tester) async {
    final padding = MotionValue<double>(0);
    Widget driven({required bool enabled}) => _app(
      TickerMode(
        enabled: enabled,
        child: MotionDriven(
          template: () => Padding(padding: EdgeInsets.all(padding.value)),
          child: const SizedBox(key: ValueKey('child'), width: 20, height: 20),
        ),
      ),
    );
    await tester.pumpWidget(driven(enabled: false));
    padding.snap(padding.clock.now, 8);
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.getTopLeft(find.byKey(const ValueKey('child'))).dx, 0);
    await tester.pumpWidget(driven(enabled: true));
    expect(tester.getTopLeft(find.byKey(const ValueKey('child'))).dx, 8);
  });

  testWidgets('a layout property changed in the resolve phase reaches '
      'the layout of the same frame', (tester) async {
    final width = MotionValue<double>(10);
    Widget tree(double measured) => _app(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MotionMeasure(
            onSize: (t, size) => width.snap(t, size.width),
            child: SizedBox(width: measured, height: 10),
          ),
          MotionDriven(
            template: () => SizedBox(width: width.value, height: 10),
            child: const SizedBox(key: ValueKey('follower')),
          ),
        ],
      ),
    );
    await tester.pumpWidget(tree(40));
    expect(tester.getSize(find.byKey(const ValueKey('follower'))).width, 40);
    await tester.pumpWidget(tree(70));
    expect(tester.getSize(find.byKey(const ValueKey('follower'))).width, 70);
  });
}

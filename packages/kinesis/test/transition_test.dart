import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

class _Counted extends LeafRenderObjectWidget {
  const _Counted();

  @override
  _RenderCounted createRenderObject(BuildContext context) => _RenderCounted();
}

class _RenderCounted extends RenderBox {
  int layouts = 0;
  int paints = 0;

  @override
  void performLayout() {
    layouts++;
    size = constraints.biggest.isFinite
        ? constraints.biggest
        : constraints.constrain(const Size(50, 50));
  }

  @override
  void paint(PaintingContext context, Offset offset) => paints++;
}

Widget _app(Widget child) =>
    Directionality(textDirection: TextDirection.ltr, child: child);

MotionTransitionLayer _layer(WidgetTester tester) =>
    tester.renderObject(find.byType(MotionTransition)).debugLayer!
        as MotionTransitionLayer;

List<String> _labels(WidgetTester tester) {
  final labels = <String>[];
  bool visit(SemanticsNode node) {
    labels.add(node.label);
    node.visitChildren(visit);
    return true;
  }

  final owner = tester.renderObject(find.byType(MotionTransition)).owner;
  final root = owner?.semanticsOwner?.rootSemanticsNode;
  if (root != null) visit(root);
  return labels;
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('moving values reach the layer without building, laying out '
      'or repainting the child', (tester) async {
    final offset = MotionValue(Offset.zero);
    final opacity = MotionValue<double>(1);
    final scale = MotionValue<double>(1);
    await tester.pumpWidget(
      _app(
        Center(
          child: SizedBox.square(
            dimension: 100,
            child: MotionTransition(
              offset: offset,
              opacity: opacity,
              scale: scale,
              child: const _Counted(),
            ),
          ),
        ),
      ),
    );
    final child = tester.renderObject<_RenderCounted>(find.byType(_Counted));
    expect(child.paints, 1);
    final rebuilt = <Widget>[];
    debugOnRebuildDirtyWidget = (element, _) => rebuilt.add(element.widget);
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    withSpring(const Spring.response(0.4), () {
      offset.target = const Offset(80, 0);
      opacity.target = 0.2;
      scale.target = 1.5;
    });
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(_layer(tester).addsOpacity, isTrue);
    withSpring(const Spring.response(0.4), () {
      offset.target = Offset.zero;
      opacity.target = 1;
      scale.target = 1;
    });
    await tester.pumpAndSettle();
    debugOnRebuildDirtyWidget = null;
    expect(rebuilt, isEmpty);
    expect(child.layouts, 1);
    expect(child.paints, 1);
    expect(_layer(tester).addsOpacity, isFalse);
    expect(_layer(tester).addsTransform, isFalse);
  });

  testWidgets('a transparent child is left out of the scene, blur and '
      'all', (tester) async {
    final opacity = MotionValue<double>(0);
    await tester.pumpWidget(
      _app(
        Center(
          child: SizedBox.square(
            dimension: 100,
            child: MotionTransition(
              opacity: opacity,
              blur: const AlwaysStoppedAnimation(6),
              child: const _Counted(),
            ),
          ),
        ),
      ),
    );
    // ignore: invalid_use_of_protected_member
    expect(_layer(tester).engineLayer, isNull);
    opacity.target = 0.5;
    await tester.pump();
    // ignore: invalid_use_of_protected_member
    expect(_layer(tester).engineLayer, isNotNull);
  });

  testWidgets('a height takes part in the layout at its presented value '
      'while the child keeps the model', (tester) async {
    final height = MotionValue<double>(100);
    await tester.pumpWidget(
      _app(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MotionTransition(height: height, child: const _Counted()),
            const SizedBox(key: ValueKey('below'), width: 10, height: 10),
          ],
        ),
      ),
    );
    withSpring(const Spring.response(0.4), () => height.target = 200);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 50));
    final presented = height.value;
    expect(presented, greaterThan(100));
    expect(presented, lessThan(200));
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('below'))).dy,
      closeTo(presented, 1e-6),
    );
    expect(tester.getSize(find.byType(_Counted)).height, 200);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byKey(const ValueKey('below'))).dy, 200);
  });

  testWidgets('a moved child is hit where it is drawn', (tester) async {
    final offset = MotionValue(const Offset(200, 0));
    var taps = 0;
    await tester.pumpWidget(
      _app(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            height: 50,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  width: 50,
                  height: 50,
                  child: MotionTransition(
                    offset: offset,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => taps++,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(225, 25));
    expect(taps, 1);
    await tester.tapAt(const Offset(25, 25));
    expect(taps, 1);
  });

  testWidgets('under a muted TickerMode it stops following', (tester) async {
    final offset = MotionValue(Offset.zero);
    await tester.pumpWidget(
      _app(
        TickerMode(
          enabled: false,
          child: MotionTransition(offset: offset, child: const _Counted()),
        ),
      ),
    );
    offset.snap(offset.clock.now, const Offset(30, 0));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_layer(tester).addsTransform, isFalse);
    await tester.pumpWidget(
      _app(MotionTransition(offset: offset, child: const _Counted())),
    );
    expect(_layer(tester).addsTransform, isTrue);
  });

  testWidgets('at opacity 0 the child has no semantics and takes no hits, '
      'with no build', (tester) async {
    final opacity = MotionValue<double>(1);
    var taps = 0;
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox.square(
            dimension: 50,
            child: MotionTransition(
              opacity: opacity,
              child: Semantics(
                label: 'faded',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => taps++,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(_labels(tester), contains('faded'));
    await tester.tapAt(const Offset(25, 25));
    expect(taps, 1);

    final rebuilt = <Widget>[];
    debugOnRebuildDirtyWidget = (element, _) => rebuilt.add(element.widget);
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    withSpring(const Spring.response(0.3), () => opacity.target = 0);
    await tester.pump(const Duration(milliseconds: 16));
    expect(opacity.value, greaterThan(0));
    expect(_labels(tester), contains('faded'));
    await tester.pumpAndSettle();
    expect(_labels(tester), isNot(contains('faded')));
    await tester.tapAt(const Offset(25, 25));
    expect(taps, 1);

    withSpring(const Spring.response(0.3), () => opacity.target = 1);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(opacity.value, lessThan(1));
    expect(_labels(tester), contains('faded'));
    await tester.tapAt(const Offset(25, 25));
    expect(taps, 2);
    debugOnRebuildDirtyWidget = null;
    expect(rebuilt, isEmpty);
    semantics.dispose();
  });
}

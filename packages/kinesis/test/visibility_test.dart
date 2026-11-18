import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinesis/kinesis.dart';

class _Counted extends LeafRenderObjectWidget {
  const _Counted(this.name);

  final String name;

  @override
  _RenderCounted createRenderObject(BuildContext context) => _RenderCounted();
}

class _RenderCounted extends RenderBox {
  int paints = 0;

  @override
  void performLayout() => size = constraints.biggest;

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void paint(PaintingContext context, Offset offset) => paints++;
}

List<String> _labels(WidgetTester tester) {
  final labels = <String>[];
  bool visit(SemanticsNode node) {
    if (node.label.isNotEmpty) labels.add(node.label);
    node.visitChildren(visit);
    return true;
  }

  final owner = tester.renderObject(find.byType(Stack)).owner;
  final root = owner?.semanticsOwner?.rootSemanticsNode;
  if (root != null) visit(root);
  return labels;
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('switches between two subtrees without building: the hidden '
      'one is not painted, hit or read', (tester) async {
    final semantics = tester.ensureSemantics();
    final docked = MotionValue<double>(0);
    final glass = MotionSelection(() => docked.value < 1);
    final opaque = MotionSelection(() => docked.value >= 1);
    final taps = <String>[];
    Widget part(String name, ValueListenable<bool> visible) => MotionVisibility(
      visible: visible,
      child: Semantics(
        label: name,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => taps.add(name),
          child: _Counted(name),
        ),
      ),
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          fit: StackFit.expand,
          children: [part('opaque', opaque), part('glass', glass)],
        ),
      ),
    );
    final glassBox = tester.renderObject<_RenderCounted>(
      find.byWidgetPredicate((w) => w is _Counted && w.name == 'glass'),
    );
    final opaqueBox = tester.renderObject<_RenderCounted>(
      find.byWidgetPredicate((w) => w is _Counted && w.name == 'opaque'),
    );
    expect(glassBox.paints, 1);
    expect(opaqueBox.paints, 0);
    expect(_labels(tester), ['glass']);
    await tester.tapAt(const Offset(10, 10));
    expect(taps, ['glass']);

    final rebuilt = <Widget>[];
    debugOnRebuildDirtyWidget = (element, _) => rebuilt.add(element.widget);
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    docked.snap(docked.clock.now, 1);
    await tester.pump();
    expect(opaqueBox.paints, 1);
    expect(_labels(tester), ['opaque']);
    await tester.tapAt(const Offset(10, 10));
    expect(taps, ['glass', 'opaque']);
    debugOnRebuildDirtyWidget = null;
    expect(rebuilt, isEmpty);
    semantics.dispose();
  });

  testWidgets('a hidden child that keeps its paint and semantics takes no '
      'hits and offers no actions', (tester) async {
    final semantics = tester.ensureSemantics();
    final active = ValueNotifier<bool>(true);
    addTearDown(active.dispose);
    var taps = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          fit: StackFit.expand,
          children: [
            MotionVisibility(
              visible: active,
              maintainPaint: true,
              maintainSemantics: true,
              child: Semantics(
                label: 'close',
                button: true,
                onTap: () => taps++,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => taps++,
                  child: const _Counted('close'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    final box = tester.renderObject<_RenderCounted>(find.byType(_Counted));
    await tester.tapAt(const Offset(10, 10));
    expect(taps, 1);
    expect(
      tester.getSemantics(find.bySemanticsLabel('close')),
      matchesSemantics(label: 'close', isButton: true, hasTapAction: true),
    );
    active.value = false;
    await tester.pump();
    expect(box.paints, 1);
    await tester.tapAt(const Offset(10, 10));
    expect(taps, 1);
    expect(_labels(tester), ['close']);
    expect(
      tester.getSemantics(find.bySemanticsLabel('close')),
      isNot(matchesSemantics(hasTapAction: true)),
    );
    semantics.dispose();
  });
}

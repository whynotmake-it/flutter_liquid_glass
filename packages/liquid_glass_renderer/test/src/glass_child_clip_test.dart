import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

const _childKey = Key('child');

Widget _scene({required bool fake, Clip? clipBehavior}) => Directionality(
  textDirection: TextDirection.ltr,
  child: LiquidGlassLayer(
    fake: fake,
    child: Center(
      child: SizedBox(
        width: 200,
        height: 120,
        child: clipBehavior == null
            ? const LiquidGlass(
                shape: LiquidRoundedSuperellipse(radius: 12),
                child: SizedBox.expand(key: _childKey),
              )
            : LiquidGlass(
                shape: const LiquidRoundedSuperellipse(radius: 12),
                clipBehavior: clipBehavior,
                child: const SizedBox.expand(key: _childKey),
              ),
      ),
    ),
  ),
);

List<Clip> _clipsAbove(WidgetTester tester) {
  final clips = <Clip>[];
  RenderObject? node = tester.renderObject(find.byKey(_childKey));
  while (node != null) {
    if (node case RenderClipRSuperellipse(:final clipBehavior)) {
      clips.add(clipBehavior);
    }
    node = node.parent;
  }
  return clips;
}

void main() {
  for (final fake in [false, true]) {
    final layer = fake ? 'a fake layer' : 'a real layer';

    testWidgets('glass on $layer clips its child hard by default', (
      tester,
    ) async {
      await tester.pumpWidget(_scene(fake: fake));

      expect(_clipsAbove(tester), [Clip.hardEdge]);
    });

    testWidgets('glass on $layer leaves its child unclipped with Clip.none', (
      tester,
    ) async {
      await tester.pumpWidget(_scene(fake: fake, clipBehavior: Clip.none));

      expect(_clipsAbove(tester), isEmpty);
    });
  }
}

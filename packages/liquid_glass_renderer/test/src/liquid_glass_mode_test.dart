import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass.dart';

void main() {
  const shape = LiquidRoundedSuperellipse(radius: 20);
  final frame = ValueNotifier(
    const LiquidGlassShapeFrame(
      shape: shape,
      rect: Rect.fromLTWH(0, 0, 100, 60),
    ),
  );
  tearDownAll(frame.dispose);

  LiquidGlass fixed(Widget child) => LiquidGlass(shape: shape, child: child);
  LiquidGlass live(Widget child) =>
      LiquidGlass.live(frame: frame, child: child);

  for (final fake in [false, true]) {
    testWidgets(
      'a shape that turns live and back keeps its child and render object '
      '(fake: $fake)',
      (tester) async {
        Future<void> pump(LiquidGlass Function(Widget child) build) =>
            tester.pumpWidget(
              Directionality(
                textDirection: TextDirection.ltr,
                child: Center(
                  child: LiquidGlassLayer(
                    fake: fake,
                    child: LiquidGlassBlendGroup(
                      child: SizedBox(
                        width: 100,
                        height: 60,
                        child: build(const _Counter()),
                      ),
                    ),
                  ),
                ),
              ),
            );

        RenderLiquidGlass raw() => tester.allRenderObjects
            .whereType<RenderLiquidGlass>()
            .toSet()
            .single;

        await pump(fixed);
        final child = tester.state(find.byType(_Counter));
        final glass = raw();

        for (final (name, build) in [('live', live), ('fixed', fixed)]) {
          await pump(build);
          expect(
            tester.state(find.byType(_Counter)),
            same(child),
            reason: 'child state after $name',
          );
          expect(raw(), same(glass), reason: 'render object after $name');
        }
      },
    );
  }
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

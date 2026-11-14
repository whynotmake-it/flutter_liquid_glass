import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/rendering.dart';

void main() {
  const shape = LiquidRoundedSuperellipse(borderRadius: 20);
  final frame = ValueNotifier(
    const LiquidGlassShapeFrame(
      shape: shape,
      rect: Rect.fromLTWH(0, 0, 100, 60),
    ),
  );
  tearDownAll(frame.dispose);

  final modes = <String, LiquidGlass Function(Widget child)>{
    'default': (child) => LiquidGlass(shape: shape, child: child),
    'grouped': (child) => LiquidGlass.grouped(shape: shape, child: child),
    'withOwnLayer': (child) =>
        LiquidGlass.withOwnLayer(shape: shape, child: child),
    'auto': (child) => LiquidGlass.auto(shape: shape, child: child),
    'live': (child) => LiquidGlass.live(frame: frame, child: child),
    'live grouped': (child) =>
        LiquidGlass.live(frame: frame, grouped: true, child: child),
  };

  for (final fake in [false, true]) {
    testWidgets(
      'a shape that changes constructor keeps its child and render object '
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

        await pump(modes['default']!);
        final child = tester.state(find.byType(_Counter));
        final glass = raw();

        for (final MapEntry(:key, :value) in modes.entries.skip(1).followedBy([
          modes.entries.first,
        ])) {
          await pump(value);
          expect(
            tester.state(find.byType(_Counter)),
            same(child),
            reason: 'child state after $key',
          );
          expect(raw(), same(glass), reason: 'render object after $key');
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

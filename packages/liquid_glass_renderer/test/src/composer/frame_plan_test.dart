import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_composer.dart';
import 'package:liquid_glass_renderer/src/rendering/read.dart';
import 'package:material_ui/material_ui.dart';

import '../shared.dart';

Widget _button(double left, double top) => Positioned(
  left: left,
  top: top,
  width: 80,
  height: 40,
  child: LiquidGlassLayer(
    settings: LiquidGlassSettings.ios27RegularLight(),
    child: const LiquidGlass(
      shape: LiquidRoundedSuperellipse(borderRadius: 20),
      child: SizedBox.expand(),
    ),
  ),
);

void main() {
  setUp(() {
    debugGlassCopies = true;
  });

  tearDown(() {
    debugGlassCopies = null;
  });

  testWidgets('joins three disjoint buttons on a real frame', (tester) async {
    if (skipProperGlassTests) return;
    var sites = 0;
    var reads = 0;
    GlassComposer.debugOnPlan = (form, plan) {
      sites = form.sites.length;
      reads = plan.reads.length;
    };
    addTearDown(() => GlassComposer.debugOnPlan = null);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            const ColoredBox(
              color: Color(0xFF204060),
              child: SizedBox.expand(),
            ),
            _button(10, 10),
            _button(10, 80),
            _button(10, 150),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(sites, greaterThanOrEqualTo(3));
    expect(reads, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('glass rests until something around it changes', (tester) async {
    if (skipProperGlassTests) return;
    final beside = ValueNotifier<int>(0);
    final glassAt = ValueNotifier<double>(10);
    addTearDown(beside.dispose);
    addTearDown(glassAt.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            ValueListenableBuilder<double>(
              valueListenable: glassAt,
              builder: (_, left, _) => _button(left, 10),
            ),
            Positioned(
              left: 10,
              top: 100,
              width: 40,
              height: 40,
              child: RepaintBoundary(
                child: ValueListenableBuilder<int>(
                  valueListenable: beside,
                  builder: (_, value, _) => ColoredBox(
                    color: Color(0xFF000000 + value),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    Future<int> restsOfAFrame() async {
      GlassComposer.debugRests = 0;
      tester.binding.scheduleFrame();
      await tester.pump();
      return GlassComposer.debugRests;
    }

    await restsOfAFrame();
    expect(await restsOfAFrame(), 1, reason: 'an empty frame');
    beside.value = 1;
    expect(await restsOfAFrame(), 1, reason: 'a repaint beside it');
    glassAt.value = 30;
    expect(await restsOfAFrame(), 0, reason: 'it moved');
  });

  testWidgets('sees no sites once the glass is gone', (tester) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(children: [_button(10, 10)]),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

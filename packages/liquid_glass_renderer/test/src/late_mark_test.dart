// Run with `flutter test --enable-impeller --enable-flutter-gpu`: glass is
// drawn as on a device, and fake glass otherwise.
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/composer.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';
import 'package:material_ui/material_ui.dart';

import 'shared.dart';

const _solid = LiquidGlassBackdrop.solid(Color(0xFF7A8290));

Widget _layer({required Widget child, LiquidGlassBackdrop? backdrop}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFF7A8290),
        child: LiquidGlassLayer(
          settings: LiquidGlassSettings.ios27RegularLight(),
          backdrop: backdrop ?? const LiquidGlassBackdrop.read(),
          child: child,
        ),
      ),
    );

const _glass = LiquidGlass(
  shape: LiquidRoundedSuperellipse(borderRadius: 20),
  child: SizedBox(width: 100, height: 60),
);

RenderLiquidGlassLayer _glassOf(WidgetTester tester) =>
    tester.allRenderObjects.whereType<RenderLiquidGlassLayer>().toSet().single;

void main() {
  testWidgets('glass over a solid backdrop paints a shape scaling under its '
      'own boundary in the frame it scales', (tester) async {
    tester.view
      ..physicalSize = const Size(400, 400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final scale = ValueNotifier<double>(1);
    addTearDown(scale.dispose);
    await tester.pumpWidget(
      _layer(
        backdrop: _solid,
        child: Stack(
          children: [
            Positioned(
              left: 100,
              top: 100,
              child: RepaintBoundary(
                child: ValueListenableBuilder<double>(
                  valueListenable: scale,
                  builder: (_, value, child) =>
                      Transform.scale(scale: value, child: child),
                  child: _glass,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    final glass = _glassOf(tester);
    for (var i = 1; i <= 8; i++) {
      GlassWork.lateMarks = 0;
      final painted = glass.debugPaintCount;
      scale.value = 1 + i * .05;
      await tester.pump(const Duration(milliseconds: 16));
      expect(glass.debugPaintCount, painted + 1, reason: 'frame $i');
      expect(GlassWork.lateMarks, 0, reason: 'frame $i');
    }
  }, skip: skipProperGlassTests);

  testWidgets('glass does not paint for a shape that repaints only what it '
      'holds under a boundary of its own', (tester) async {
    tester.view
      ..physicalSize = const Size(400, 400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final color = ValueNotifier(const Color(0xFF204060));
    addTearDown(color.dispose);
    await tester.pumpWidget(
      _layer(
        child: Stack(
          children: [
            Positioned(
              left: 100,
              top: 100,
              child: LiquidGlass(
                shape: const LiquidRoundedSuperellipse(borderRadius: 20),
                child: RepaintBoundary(
                  child: ValueListenableBuilder<Color>(
                    valueListenable: color,
                    builder: (_, value, _) => SizedBox(
                      width: 100,
                      height: 60,
                      child: ColoredBox(color: value),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    final glass = _glassOf(tester);
    final painted = glass.debugPaintCount;
    GlassWork.marks = 0;
    color.value = const Color(0xFF406080);
    await tester.pump(const Duration(milliseconds: 16));
    expect(glass.debugPaintCount, painted);
    expect(GlassWork.marks, 0);
  }, skip: skipProperGlassTests);

  testWidgets('a shape under a follower whose leader moves is the one late '
      'mark, over a solid backdrop', (tester) async {
    tester.view
      ..physicalSize = const Size(400, 400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final link = LayerLink();
    final left = ValueNotifier<double>(40);
    addTearDown(left.dispose);
    await tester.pumpWidget(
      _layer(
        backdrop: _solid,
        child: Stack(
          children: [
            const Positioned(left: 200, top: 250, child: _glass),
            RepaintBoundary(
              child: Stack(
                children: [
                  ValueListenableBuilder<double>(
                    valueListenable: left,
                    builder: (_, value, _) => Positioned(
                      left: value,
                      top: 40,
                      child: CompositedTransformTarget(
                        link: link,
                        child: const SizedBox(width: 10, height: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            CompositedTransformFollower(
              link: link,
              offset: const Offset(0, 40),
              child: _glass,
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    GlassWork.lateMarks = 0;
    left.value = 90;
    await tester.pump(const Duration(milliseconds: 16));
    expect(GlassWork.lateMarks, 1);
  }, skip: skipProperGlassTests);
}

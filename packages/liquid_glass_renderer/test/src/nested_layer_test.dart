import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_render_scope.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

import 'shared.dart';

void main() {
  testWidgets('Layer -> Glass -> Glass paints shapes in tree order', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(500, 500)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final captureKey = GlobalKey();

    await tester.pumpWidget(
      _buildScene(
        offset: Offset.zero,
        captureKey: captureKey,
      ),
    );
    await _pumpUntilAllGlassReady(tester);
    await tester.pump();

    final layers = tester.allRenderObjects
        .whereType<RenderLiquidGlassLayer>()
        .toSet()
        .toList();
    expect(layers, hasLength(1));
    expect(
      layers.single.link.shapes.map((shape) => shape.size),
      containsAllInOrder(const [Size(260, 180), Size(180, 120)]),
      reason: 'The layer paints the less nested glass before the nested glass.',
    );

    await tester.pumpWidget(
      _buildScene(
        offset: const Offset(80, 42),
        captureKey: captureKey,
      ),
    );
    tester.binding.scheduleFrame();
    await tester.pump();

    final moved = await _capture(captureKey);
    addTearDown(moved.dispose);
    await expectLater(
      moved,
      matchesGoldenFile('goldens/nested_layer_moved.png'),
    );
  }, skip: skipProperGlassTests);

  testWidgets('nested layer static destination matches the moved frame', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(500, 500)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final captureKey = GlobalKey();
    await tester.pumpWidget(
      _buildScene(
        offset: const Offset(80, 42),
        captureKey: captureKey,
      ),
    );
    await _pumpUntilAllGlassReady(tester);
    await tester.pump();

    final image = await _capture(captureKey);
    addTearDown(image.dispose);
    await expectLater(
      image,
      matchesGoldenFile('goldens/nested_layer_moved.png'),
    );
  }, skip: skipProperGlassTests);

  testWidgets('inner layer follows a moving outer layer', (tester) async {
    tester.view
      ..physicalSize = const Size(500, 500)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final captureKey = GlobalKey();
    await tester.pumpWidget(
      _buildLayerInLayerScene(
        offset: Offset.zero,
        captureKey: captureKey,
      ),
    );
    await _pumpUntilAllGlassReady(tester);
    await tester.pump();
    expect(
      tester.allRenderObjects.whereType<RenderLiquidGlassLayer>().toSet(),
      hasLength(2),
    );
    final initialInnerPaints = _nestedLayerPaintCount(tester);

    await tester.pumpWidget(
      _buildLayerInLayerScene(
        offset: const Offset(80, 42),
        captureKey: captureKey,
      ),
    );
    tester.binding.scheduleFrame();
    await tester.pump();

    expect(
      _nestedLayerPaintCount(tester),
      greaterThan(initialInnerPaints),
      reason:
          'Nested layers must refresh their local retained filter after '
          'an outer layer moves.',
    );

    final moved = await _capture(captureKey);
    addTearDown(moved.dispose);
    await expectLater(
      moved,
      matchesGoldenFile('goldens/layer_in_layer_moved.png'),
    );
  }, skip: skipProperGlassTests);

  testWidgets('layer-in-layer static destination golden', (tester) async {
    tester.view
      ..physicalSize = const Size(500, 500)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final captureKey = GlobalKey();
    await tester.pumpWidget(
      _buildLayerInLayerScene(
        offset: const Offset(80, 42),
        captureKey: captureKey,
      ),
    );
    await _pumpUntilAllGlassReady(tester);
    await tester.pump();

    final image = await _capture(captureKey);
    addTearDown(image.dispose);
    await expectLater(
      image,
      matchesGoldenFile('goldens/layer_in_layer_moved.png'),
    );
  }, skip: skipProperGlassTests);

  testWidgets('nested scrolling layer follows its retained ancestor', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(500, 500)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = ScrollController();
    addTearDown(controller.dispose);
    final captureKey = GlobalKey();
    await tester.pumpWidget(
      _buildScrollingScene(
        controller: controller,
        captureKey: captureKey,
        fake: true,
      ),
    );
    await tester.pump();
    await tester.pump();

    controller.jumpTo(220);
    await tester.pump();
    tester.binding.scheduleFrame();
    await tester.pump();

    final moved = await _capture(captureKey);
    addTearDown(moved.dispose);
    await expectLater(
      moved,
      matchesGoldenFile('goldens/nested_scrolling_layer.png'),
    );
  });

  testWidgets('nested scrolling layer static destination golden', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(500, 500)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = ScrollController(initialScrollOffset: 220);
    addTearDown(controller.dispose);
    final captureKey = GlobalKey();
    await tester.pumpWidget(
      _buildScrollingScene(
        controller: controller,
        captureKey: captureKey,
        fake: true,
      ),
    );
    await tester.pump();
    await tester.pump();

    final image = await _capture(captureKey);
    addTearDown(image.dispose);
    await expectLater(
      image,
      matchesGoldenFile('goldens/nested_scrolling_layer.png'),
    );
  });
}

Widget _buildScene({required Offset offset, required GlobalKey captureKey}) {
  return MaterialApp(
    home: RepaintBoundary(
      key: captureKey,
      child: Stack(
        children: [
          const Positioned.fill(child: _GridBackground()),
          LiquidGlassLayer(
            settings: settingsWithoutLighting.copyWith(
              thickness: 24,
              edgeRefraction: 52,
              refractionSpread: 1,
            ),
            defaultAppearance: const LiquidGlassAppearance(
              tint: Color(0x4020A0FF),
            ),
            child: Center(
              child: Transform.translate(
                offset: offset,
                child: const LiquidGlass(
                  shape: LiquidRoundedSuperellipse(borderRadius: 48),
                  child: SizedBox(
                    width: 260,
                    height: 180,
                    child: Center(
                      child: LiquidGlass(
                        appearance: LiquidGlassAppearance(
                          tint: Color(0xC0FF6048),
                        ),
                        shape: LiquidRoundedSuperellipse(
                          borderRadius: 28,
                        ),
                        glassContainsChild: true,
                        child: ColoredBox(
                          color: Color(0xC0FF6048),
                          child: SizedBox(width: 180, height: 120),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _buildLayerInLayerScene({
  required Offset offset,
  required GlobalKey captureKey,
}) {
  return MaterialApp(
    home: RepaintBoundary(
      key: captureKey,
      child: Stack(
        children: [
          const Positioned.fill(child: _GridBackground()),
          Transform.translate(
            offset: offset,
            child: LiquidGlassLayer(
              settings: settingsWithoutLighting.copyWith(
                thickness: 24,
                edgeRefraction: 52,
                refractionSpread: 1,
              ),
              defaultAppearance: const LiquidGlassAppearance(
                tint: Color(0x4020A0FF),
              ),
              child: Center(
                child: LiquidGlass(
                  shape: const LiquidRoundedSuperellipse(borderRadius: 48),
                  child: SizedBox(
                    width: 260,
                    height: 180,
                    child: Center(
                      child: LiquidGlassLayer(
                        settings: settingsWithoutLighting.copyWith(
                          thickness: 18,
                          edgeRefraction: 36,
                        ),
                        defaultAppearance: const LiquidGlassAppearance(
                          tint: Color(0xC0FF6048),
                        ),
                        child: const LiquidGlass(
                          shape: LiquidRoundedSuperellipse(
                            borderRadius: 28,
                          ),
                          glassContainsChild: true,
                          child: ColoredBox(
                            color: Color(0xC0FF6048),
                            child: SizedBox(width: 180, height: 120),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Widget _buildScrollingScene({
  required ScrollController controller,
  required GlobalKey captureKey,
  required bool fake,
}) {
  return MaterialApp(
    home: RepaintBoundary(
      key: captureKey,
      child: Stack(
        children: [
          const Positioned.fill(child: _GridBackground()),
          LiquidGlassLayer(
            fake: fake,
            settings: settingsWithoutLighting.copyWith(thickness: 18),
            child: SizedBox.expand(
              child: SingleChildScrollView(
                controller: controller,
                child: Column(
                  children: [
                    const SizedBox(height: 360),
                    LiquidGlass.withOwnLayer(
                      fake: fake,
                      settings: settingsWithoutLighting.copyWith(
                        thickness: 18,
                        edgeRefraction: 40,
                      ),
                      appearance: const LiquidGlassAppearance(
                        tint: Color(0x4020A0FF),
                      ),
                      shape: const LiquidRoundedSuperellipse(borderRadius: 32),
                      glassContainsChild: true,
                      child: Container(
                        width: 240,
                        height: 140,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xffff595e), Color(0xff1982c4)],
                          ),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'nested',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 500),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _GridBackground extends StatelessWidget {
  const _GridBackground();

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _GridPainter(),
    size: Size.infinite,
  );
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2;
    for (var x = 0.0; x <= size.width; x += 32) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y <= size.height; y += 32) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Future<ui.Image> _capture(GlobalKey key) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return boundary.toImage();
}

Future<void> _pumpUntilAllGlassReady(WidgetTester tester) async {
  for (var frame = 0; frame < 60; frame++) {
    final scopes = tester.widgetList<LiquidGlassRenderScope>(
      find.byType(LiquidGlassRenderScope),
    );
    final layers = tester.allRenderObjects
        .whereType<RenderLiquidGlassLayer>()
        .where((layer) => layer.attached)
        .where((layer) => layer.gpuGeometryRenderer != null);
    if (scopes.isNotEmpty &&
        scopes.every((scope) => !scope.useFake) &&
        layers.isNotEmpty) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 16));
  }
  fail('Nested Flutter GPU layers did not become ready within 60 frames.');
}

int _nestedLayerPaintCount(WidgetTester tester) {
  final counts = tester.allRenderObjects
      .whereType<RenderLiquidGlassLayer>()
      .where((layer) => layer.attached && layer.size == const Size(180, 120))
      .map((layer) => layer.debugPaintCount);
  return counts.fold(0, (highest, count) => count > highest ? count : highest);
}

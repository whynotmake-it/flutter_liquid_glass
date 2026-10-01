import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_render_scope.dart';
import 'package:liquid_glass_renderer/src/rendering/consolidated_fake_glass_layer.dart';
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
    expect(layers, hasLength(2));
    expect(
      layers.expand((layer) => layer.link.shapes.map((shape) => shape.size)),
      containsAllInOrder(const [Size(260, 180), Size(180, 120)]),
      reason:
          'Nested materials need ordered passes; siblings still share '
          'a pass. Combining nested shapes would erase the inner material.',
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
      initialInnerPaints,
      reason:
          'A nested layer moving with its retained ancestor must only refresh '
          'its frame-owned coordinates, not repaint its render object.',
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

  testWidgets('nested scrolling layer is correct on the first scroll frame', (
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

  testWidgets('uniform scroll does not repaint consolidated fake layers', (
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
      _buildNestedGlassScrollingScene(
        controller: controller,
        captureKey: captureKey,
        fake: true,
      ),
    );
    await tester.pump();
    await tester.pump();

    final layers = tester.allRenderObjects
        .whereType<RenderConsolidatedFakeGlassLayer>()
        .toSet()
        .where((layer) => layer.attached)
        .toList(growable: false);
    expect(layers, hasLength(2));
    final initialPaintCounts = [
      for (final layer in layers) layer.debugPaintCount,
    ];
    final scrollingLayer = layers.singleWhere(
      (layer) => layer.size == const Size(500, 500),
    );

    for (final offset in const [40.0, 90.0, 150.0, 220.0]) {
      controller.jumpTo(offset);
      await tester.pump();
      expect(
        scrollingLayer.debugCompositorTranslation,
        Offset(0, -offset),
        reason:
            "The retained fake effect must use this frame's sliver layout "
            'before any screenshot traversal.',
      );
      expect(
        [for (final layer in layers) layer.debugPaintCount],
        initialPaintCounts,
        reason: 'Scroll frame at offset $offset must stay compositor-only.',
      );
    }
  });

  testWidgets('nested glass scroll static destination golden', (tester) async {
    tester.view
      ..physicalSize = const Size(500, 500)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final controller = ScrollController(initialScrollOffset: 220);
    addTearDown(controller.dispose);
    final captureKey = GlobalKey();
    await tester.pumpWidget(
      _buildNestedGlassScrollingScene(
        controller: controller,
        captureKey: captureKey,
      ),
    );
    await _pumpUntilAllGlassReady(tester);
    await tester.pump();

    final image = await _capture(captureKey);
    addTearDown(image.dispose);
    await expectLater(
      image,
      matchesGoldenFile('goldens/nested_glass_scrolling_real.png'),
    );
  }, skip: skipProperGlassTests);

  testWidgets(
    'nested glass is aligned on the first scroll frame without repainting',
    (tester) async {
      tester.view
        ..physicalSize = const Size(500, 500)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final controller = ScrollController();
      addTearDown(controller.dispose);
      final captureKey = GlobalKey();
      await tester.pumpWidget(
        _buildNestedGlassScrollingScene(
          controller: controller,
          captureKey: captureKey,
        ),
      );
      await _pumpUntilAllGlassReady(tester);
      await tester.pump();

      final layers = tester.allRenderObjects
          .whereType<RenderLiquidGlassLayer>()
          .toSet()
          .where((layer) => layer.attached && layer.gpuGeometryRenderer != null)
          .toList(growable: false);
      expect(layers, hasLength(2));
      final initialPaintCounts = [
        for (final layer in layers) layer.debugPaintCount,
      ];
      final initialRenderCounts = [
        for (final layer in layers) layer.gpuGeometryRenderer!.debugRenderCount,
      ];
      final scrollingLayer = layers.singleWhere(
        (layer) => layer.size == const Size(500, 500),
      );

      for (final offset in const [40.0, 90.0, 150.0, 220.0]) {
        controller.jumpTo(offset);
        await tester.pump();
        expect(
          scrollingLayer.debugCompositorTranslation,
          Offset(0, -offset),
          reason:
              "The retained real effect must use this frame's sliver layout "
              'before any screenshot traversal.',
        );
        expect(
          [for (final layer in layers) layer.debugPaintCount],
          initialPaintCounts,
          reason: 'Scroll frame at offset $offset must stay compositor-only.',
        );
        expect(
          [
            for (final layer in layers)
              layer.gpuGeometryRenderer!.debugRenderCount,
          ],
          initialRenderCounts,
          reason: 'Scroll frame at offset $offset must reuse both mattes.',
        );
      }

      final moved = await _capture(captureKey);
      addTearDown(moved.dispose);
      await expectLater(
        moved,
        matchesGoldenFile(
          'goldens/nested_glass_scrolling_real.png',
        ),
      );
    },
    skip: skipProperGlassTests,
  );
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

Widget _buildNestedGlassScrollingScene({
  required ScrollController controller,
  required GlobalKey captureKey,
  bool fake = false,
}) {
  return MaterialApp(
    home: RepaintBoundary(
      key: captureKey,
      child: Stack(
        children: [
          const Positioned.fill(child: _GridBackground()),
          LiquidGlassLayer(
            fake: fake,
            settings: settingsWithoutLighting.copyWith(
              thickness: 22,
              edgeRefraction: 44,
            ),
            defaultAppearance: const LiquidGlassAppearance(
              tint: Color(0x4020A0FF),
            ),
            child: SizedBox.expand(
              child: CustomScrollView(
                controller: controller,
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      children: [
                        const SizedBox(height: 340),
                        LiquidGlass(
                          shape: const LiquidRoundedSuperellipse(
                            borderRadius: 36,
                          ),
                          child: SizedBox(
                            width: 300,
                            height: 180,
                            child: Center(
                              child: LiquidGlass.withOwnLayer(
                                fake: fake,
                                settings: settingsWithoutLighting.copyWith(
                                  thickness: 16,
                                  edgeRefraction: 32,
                                ),
                                appearance: const LiquidGlassAppearance(
                                  tint: Color(0x80FF6048),
                                ),
                                shape: const LiquidRoundedSuperellipse(
                                  borderRadius: 24,
                                ),
                                child: Container(
                                  width: 150,
                                  height: 90,
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Color(0xffffca3a),
                                        Color(0xff1982c4),
                                      ],
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: const Text(
                                    'nested',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 500),
                      ],
                    ),
                  ),
                ],
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

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/transform_tracking_repaint_boundary_mixin.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

import 'shared.dart';

/// Coverage for [TransformTrackingRenderObjectMixin]: the cases where a glass
/// shape's composited position can change while the owning layer's paint()
/// never runs. Without the tracking layer nothing schedules the matte update,
/// so these tests must fail if the sentinel in
/// updateSubtreeNeedsAddToScene stops polling.
void main() {
  RenderLiquidGlassLayer layerOf(WidgetTester tester) =>
      tester.allRenderObjects
          .whereType<RenderLiquidGlassLayer>()
          .where((renderObject) => renderObject.gpuGeometryRenderer != null)
          .last;

  testWidgets(
    'updates the matte when a repaint boundary retransforms a shape',
    (tester) async {
      tester.view
        ..physicalSize = const Size(500, 500)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final angle = ValueNotifier<double>(0);
      addTearDown(angle.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: LiquidGlassLayer(
            settings: settingsWithoutLighting,
            child: Center(
              child: ValueListenableBuilder<double>(
                valueListenable: angle,
                builder: (_, value, __) => RepaintBoundary(
                  child: Transform.rotate(
                    angle: value,
                    child: const LiquidGlass(
                      shape: LiquidRoundedRectangle(borderRadius: 20),
                      child: SizedBox(width: 100, height: 80),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final layer = layerOf(tester);
      final initialBounds = layer.debugGeometryMatteBounds;
      final initialPaints = layer.debugPaintCount;

      angle.value = 0.5;
      // One pump only: a second pump could mask a one-frame lag.
      await tester.pump();

      expect(
        layer.debugPaintCount,
        initialPaints,
        reason:
            'Precondition: the boundary contains the repaint, so the layer '
            'itself must not paint. If this grew, the test is not isolating '
            'compositor updates.',
      );
      expect(
        layer.debugGeometryMatteBounds,
        isNot(initialBounds),
        reason:
            'The matte must follow a compositor-only transform change. '
            'Without transform tracking nothing schedules the update and '
            'the matte stays stale forever.',
      );
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'updates the matte when only one of two shapes moves',
    (tester) async {
      tester.view
        ..physicalSize = const Size(500, 500)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final scale = ValueNotifier<double>(1);
      addTearDown(scale.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: LiquidGlassLayer(
            settings: settingsWithoutLighting,
            child: Stack(
              children: [
                Positioned(
                  top: 100,
                  left: 20,
                  child: ValueListenableBuilder<double>(
                    valueListenable: scale,
                    builder: (_, value, __) => RepaintBoundary(
                      child: Transform.scale(
                        scale: value,
                        child: const LiquidGlass(
                          shape: LiquidRoundedRectangle(borderRadius: 20),
                          child: SizedBox(width: 100, height: 80),
                        ),
                      ),
                    ),
                  ),
                ),
                const Positioned(
                  top: 100,
                  left: 300,
                  child: RepaintBoundary(
                    child: LiquidGlass(
                      shape: LiquidRoundedRectangle(borderRadius: 20),
                      child: SizedBox(width: 100, height: 80),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final layer = layerOf(tester);
      final initialBounds = layer.debugGeometryMatteBounds;
      final initialPaints = layer.debugPaintCount;

      scale.value = 1.5;
      await tester.pump();

      expect(layer.debugPaintCount, initialPaints);
      expect(
        layer.debugGeometryMatteBounds.width,
        greaterThan(initialBounds.width),
        reason:
            'Relative motion between shapes changes the matte contents; '
            'only the tracker can schedule the retained re-render.',
      );
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'follows scrolling content clipped inside the layer',
    (tester) async {
      tester.view
        ..physicalSize = const Size(500, 500)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            height: 300,
            child: LiquidGlassLayer(
              settings: settingsWithoutLighting,
              child: ListView(
                controller: controller,
                children: const [
                  SizedBox(height: 200),
                  LiquidGlass(
                    shape: LiquidRoundedRectangle(borderRadius: 20),
                    child: SizedBox(width: 100, height: 80),
                  ),
                  SizedBox(height: 400),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final layer = layerOf(tester);
      final initialPaints = layer.debugPaintCount;

      controller.jumpTo(150);
      await tester.pump();

      expect(
        layer.debugPaintCount,
        initialPaints,
        reason:
            'Scrolling a viewport updates layer offsets only; the layer '
            'paint() must not run.',
      );
      expect(
        layer.debugCompositorTranslation,
        const Offset(0, -150),
        reason:
            'The scroll moved the shape relative to the layer through layer '
            'offsets only. The tracker must patch the retained effect '
            'layer offset in the same frame — without it the matte is left '
            'behind while the content scrolls.',
      );
    },
    skip: skipProperGlassTests,
  );

  group('paint-time transforms', () {
    testWidgets(
      'matte ignores a paint-time pushTransform (documented gap)',
      (tester) async {
        tester.view
          ..physicalSize = const Size(500, 500)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        final angle = ValueNotifier<double>(0);
        addTearDown(angle.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: LiquidGlassLayer(
              settings: settingsWithoutLighting,
              child: Center(
                child: ValueListenableBuilder<double>(
                  valueListenable: angle,
                  builder: (_, value, __) => _PaintTimeTransform(
                    angle: value,
                    child: const LiquidGlass(
                      shape: LiquidRoundedRectangle(borderRadius: 20),
                      child: SizedBox(width: 100, height: 80),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        final layer = layerOf(tester);
        final initialBounds = layer.debugGeometryMatteBounds;

        angle.value = 0.5;
        await tester.pump();
        await tester.pump();

        // The child render object is rotated on screen, but the matte keeps
        // its unrotated bounds because getTransformTo cannot see the
        // paint-time TransformLayer. If this starts failing, the tracking
        // learned to read composited transforms — update the expectation.
        expect(
          layer.debugGeometryMatteBounds,
          initialBounds,
          reason:
              'Paint-time pushTransform is invisible to applyPaintTransform '
              'and therefore to the matte. This test documents the current '
              'gap; it must flip once transforms are read from the layer '
              'tree.',
        );
      },
      skip: skipProperGlassTests,
    );
  });
}

/// Applies a rotation inside paint() only — the classic pushTransform case
/// that applyPaintTransform-based transform polling cannot observe.
class _PaintTimeTransform extends SingleChildRenderObjectWidget {
  const _PaintTimeTransform({required this.angle, super.child});

  final double angle;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPaintTimeTransform(angle);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPaintTimeTransform renderObject,
  ) =>
      renderObject.angle = angle;
}

class _RenderPaintTimeTransform extends RenderProxyBox {
  _RenderPaintTimeTransform(this._angle);

  double get angle => _angle;
  double _angle;
  set angle(double value) {
    if (value == _angle) return;
    _angle = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, ui.Offset offset) {
    final transform = Matrix4.rotationZ(_angle);
    context.pushTransform(
      needsCompositing,
      offset,
      transform,
      (context, offset) => super.paint(context, offset),
    );
  }
}

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_blend_group.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';

import 'shared.dart';

void main() {
  group('LiquidGlassBlendGroup', () {
    const blendGroupKey = Key('blend-group');
    late GeometryRenderLink link;
    setUp(() {
      link = GeometryRenderLink();
    });

    tearDown(() {
      link.dispose();
    });

    Widget build(LiquidGlassSettings settings, double blend) {
      return CupertinoApp(
        // Inject the stuff that LiquidGlassBlendGroup needs.
        home: LiquidGlassLayer(
          settings: settings,
          child: LiquidGlassBlendGroup(
            blend: blend,
            key: blendGroupKey,
            child: const Row(
              children: [
                LiquidGlass.grouped(
                  shape: LiquidOval(),
                  child: SizedBox.square(dimension: 100),
                ),
                LiquidGlass.grouped(
                  shape: LiquidRoundedSuperellipse(
                    borderRadius: 20,
                  ),
                  child: SizedBox.square(dimension: 100),
                ),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('generates reusable GPU geometry metadata', (tester) async {
      await tester.pumpWidget(
        build(const LiquidGlassSettings(thickness: 30), 24),
      );
      await tester.pumpAndSettle();

      final renderObject = tester.allRenderObjects
          .whereType<RenderLiquidGlassBlendGroup>()
          .firstWhere((renderObject) => renderObject.geometryBlend == 24);
      final geometry = renderObject.geometry;

      expect(geometry, isA<GeometryCache>());
      expect(geometry!.shapes, hasLength(2));
      expect(geometry.blend, 24);
      expect(geometry.bounds, isNot(Rect.zero));
    }, skip: expectFlutterGpuFallback);

    testWidgets(
      'refreshes grouped shadows without rebuilding the geometry path',
      (tester) async {
        var shadows = const <BoxShadow>[];
        late StateSetter update;
        await tester.pumpWidget(
          CupertinoApp(
            home: LiquidGlassLayer(
              settings: const LiquidGlassSettings(thickness: 30),
              child: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return LiquidGlassBlendGroup(
                    child: LiquidGlass.grouped(
                      shadows: shadows,
                      shape: const LiquidOval(),
                      child: const SizedBox.square(dimension: 100),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final renderObject = tester.allRenderObjects
            .whereType<RenderLiquidGlassBlendGroup>()
            .firstWhere(
              (renderObject) => renderObject.geometry?.shapes.length == 1,
            );
        final originalPath = renderObject.geometry!.path;
        expect(renderObject.geometry!.shapes.single.shadows, isEmpty);

        update(() {
          shadows = const [
            BoxShadow(
              color: Color(0x20000000),
              offset: Offset(0, 4),
              blurRadius: 8,
            ),
          ];
        });
        await tester.pump();

        expect(renderObject.geometry!.path, same(originalPath));
        expect(renderObject.geometry!.shapes.single.shadows, shadows);
      },
      skip: expectFlutterGpuFallback,
    );

    testWidgets(
      'keeps transformed grouped shapes in local primitive space',
      (
        tester,
      ) async {
        await tester.pumpWidget(
          CupertinoApp(
            home: LiquidGlassLayer(
              settings: const LiquidGlassSettings(thickness: 30),
              child: LiquidGlassBlendGroup(
                key: blendGroupKey,
                child: Center(
                  child: RawLiquidStretch(
                    stretchPixels: const Offset(50, 0),
                    child: Transform.rotate(
                      angle: .35,
                      child: const LiquidGlass.grouped(
                        shape: LiquidRoundedRectangle(borderRadius: 18),
                        child: SizedBox(width: 100, height: 80),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final renderObject = tester.allRenderObjects
            .whereType<RenderLiquidGlassBlendGroup>()
            .firstWhere(
              (renderObject) => renderObject.geometry?.shapes.length == 1,
            );
        final shape = renderObject.geometry!.shapes.single;

        // Bounds are allowed to grow with the transform, but the SDF primitive
        // remains the child's local 100x80 shape. The transform is represented
        // exactly once by shapeToGeometry.
        expect(shape.renderObject.size, const Size(100, 80));
        expect(shape.shapeBounds.size.width, greaterThan(100));
        expect(shape.shapeToGeometry, isNotNull);
        expect(shape.shapeToGeometry!.getMaxScaleOnAxis(), greaterThan(1));
      },
      skip: expectFlutterGpuFallback,
    );
  });
}

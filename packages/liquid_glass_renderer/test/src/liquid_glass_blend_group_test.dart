import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_shadow.dart';
import 'package:liquid_glass_renderer/src/painting/shader_constants.dart';
import 'package:liquid_glass_renderer/src/rendering/geometry_render_link.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_blend_group.dart';
import 'package:liquid_glass_renderer/src/rendering/render_liquid_glass_geometry.dart';

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
                LiquidGlass(
                  shape: LiquidOval(),
                  child: SizedBox.square(dimension: 100),
                ),
                LiquidGlass(
                  shape: LiquidRoundedSuperellipse(
                    radius: 20,
                  ),
                  child: SizedBox.square(dimension: 100),
                ),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('a hidden shape leaves the group bounds to what shows', (
      tester,
    ) async {
      Widget group({required double hidden}) => CupertinoApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: LiquidGlassLayer(
            child: LiquidGlassBlendGroup(
              blend: 8,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LiquidGlassVisibility(
                    visibility: hidden,
                    child: const LiquidGlass(
                      shape: LiquidOval(),
                      child: SizedBox.square(dimension: 100),
                    ),
                  ),
                  const SizedBox(width: 200),
                  const LiquidGlass(
                    shape: LiquidOval(),
                    child: SizedBox.square(dimension: 40),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      Rect bounds() => tester.allRenderObjects
          .whereType<RenderLiquidGlassBlendGroup>()
          .firstWhere((group) => group.geometryBlend == 8)
          .maybeRebuildGeometry(const LiquidGlassAppearance())!
          .bounds;

      await tester.pumpWidget(group(hidden: 0));
      await tester.pump();
      expect(bounds().width, moreOrLessEquals(44, epsilon: 2));

      await tester.pumpWidget(group(hidden: 0.5));
      await tester.pump();
      expect(bounds().width, moreOrLessEquals(344, epsilon: 2));

      await tester.pumpWidget(group(hidden: 0));
      await tester.pump();
      expect(bounds().width, moreOrLessEquals(44, epsilon: 2));
    });

    testWidgets('generates reusable GPU geometry metadata', (tester) async {
      await tester.pumpWidget(
        build(const LiquidGlassSettings(refractionHeight: 30), 24),
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
    }, skip: skipProperGlassTests);

    testWidgets(
      'refreshes grouped shadows without rebuilding the geometry path',
      (tester) async {
        var shadows = const <LiquidGlassShadow>[];
        late StateSetter update;
        await tester.pumpWidget(
          CupertinoApp(
            home: LiquidGlassLayer(
              settings: const LiquidGlassSettings(refractionHeight: 30),
              child: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return LiquidGlassBlendGroup(
                    child: LiquidGlass(
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
        final originalRevision = renderObject.geometry!.revision;
        expect(renderObject.geometry!.shapes.single.shadows, isEmpty);

        update(() {
          shadows = const [
            LiquidGlassShadow(
              color: Color(0x20000000),
              offset: Offset(0, 4),
              blurRadius: 8,
            ),
          ];
        });
        await tester.pump();

        expect(renderObject.geometry!.revision, originalRevision);
        expect(
          renderObject.geometry!.shapes.single.shadows,
          castGlassShadows(shadows, Size.zero),
        );
      },
      skip: skipProperGlassTests,
    );

    testWidgets(
      'keeps transformed grouped shapes in local primitive space',
      (
        tester,
      ) async {
        await tester.pumpWidget(
          CupertinoApp(
            home: LiquidGlassLayer(
              settings: const LiquidGlassSettings(refractionHeight: 30),
              child: LiquidGlassBlendGroup(
                key: blendGroupKey,
                child: Center(
                  child: Transform(
                    alignment: Alignment.center,
                    transform: stretchedBy(
                      const Offset(50, 0),
                      const Size(100, 80),
                    ),
                    child: Transform.rotate(
                      angle: .35,
                      child: const LiquidGlass(
                        shape: LiquidRoundedRectangle(radius: 18),
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
      skip: skipProperGlassTests,
    );

    testWidgets(
      'warns once when a layer has more shapes than it renders',
      (tester) async {
        final messages = <String>[];
        final previousDebugPrint = debugPrint;
        debugPrint = (message, {wrapWidth}) {
          if (message != null) messages.add(message);
        };
        try {
          await tester.runAsync(precacheLiquidGlass);
          await tester.pumpWidget(
            CupertinoApp(
              home: LiquidGlassLayer(
                child: LiquidGlassBlendGroup(
                  child: Wrap(
                    children: [
                      for (var i = 0; i <= geometryMaxShapesPerDraw; i++)
                        const LiquidGlass(
                          shape: LiquidOval(),
                          child: SizedBox.square(dimension: 20),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.pump();

          expect(
            messages.where((message) => message.contains('are not drawn')),
            hasLength(1),
          );
        } finally {
          debugPrint = previousDebugPrint;
        }
      },
      skip: skipProperGlassTests,
    );
  });
}

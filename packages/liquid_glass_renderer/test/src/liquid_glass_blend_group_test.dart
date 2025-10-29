import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_blend_group.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_render_scope.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';

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
        home: InheritedGeometryRenderLink(
          link: link,
          child: LiquidGlassRenderScope(
            settings: settings,
            child: LiquidGlassBlendGroup(
              blend: blend,
              key: blendGroupKey,
              child: const Row(
                children: [
                  LiquidGlass.blended(
                    shape: LiquidOval(),
                    child: SizedBox.square(dimension: 100),
                  ),
                  LiquidGlass.blended(
                    shape: LiquidRoundedSuperellipse(
                      borderRadius: 20,
                    ),
                    child: SizedBox.square(dimension: 100),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('generates a geometry image', (tester) async {
      final thicknesses = [10, 20, 30];
      final refractiveIndices = [1.0, 1.1, 1.2, 1.3];
      final blendValues = [0.0, 10, 20, 30, 300];

      Future<void> verifySettings(
        LiquidGlassSettings settings,
        double blend,
      ) async {
        await tester.pumpWidget(build(settings, blend));
        await tester.pumpAndSettle();

        final blendGroupFinder = find.byKey(blendGroupKey);
        expect(blendGroupFinder, findsOneWidget);

        final blendGroup = tester.firstWidget<LiquidGlassBlendGroup>(
          blendGroupFinder,
        );
        final ro = tester.renderObject<RenderLiquidGlassBlendGroup>(
          find.byWidget(blendGroup),
        );
        final geo = ro.geometry;
        expect(geo, isNotNull);
        final matteImage = geo!.matte;

        await expectLater(
          matteImage,
          matchesGoldenFile(
            'goldens/geometry/liquid_glass_blend_group_geometry_'
            'thickness${settings.thickness}_'
            'refractiveIndex${settings.refractiveIndex}_'
            'blend$blend'
            '.png',
          ),
        );
      }

      await verifySettings(
        const LiquidGlassSettings(
          thickness: 0,
          refractiveIndex: 1.5,
        ),
        0,
      );

      for (final thickness in thicknesses) {
        for (final refractiveIndex in refractiveIndices) {
          for (final blend in blendValues) {
            final settings = LiquidGlassSettings(
              thickness: thickness.toDouble(),
              refractiveIndex: refractiveIndex,
            );
            await verifySettings(settings, blend.toDouble());
          }
        }
      }
    });
  });
}

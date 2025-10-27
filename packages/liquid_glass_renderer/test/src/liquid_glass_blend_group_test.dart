import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_blend_group.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_scope.dart';

void main() {
  group('LiquidGlassBlendGroup', () {
    const blendGroupKey = Key('blend-group');

    Widget build(LiquidGlassSettings settings) {
      return CupertinoApp(
        home: LiquidGlassScope(
          settings: settings,
          child: const LiquidGlassBlendGroup(
            key: blendGroupKey,
            child: Row(
              children: [
                LiquidGlass.blended(
                  shape: LiquidOval(),
                  child: SizedBox.square(dimension: 100),
                ),
                LiquidGlass.blended(
                  shape: LiquidRoundedSuperellipse(
                    borderRadius: Radius.circular(20),
                  ),
                  child: SizedBox.square(dimension: 100),
                ),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('generates a geometry image', (tester) async {
      final thicknesses = [10, 20, 30];
      final refractiveIndices = [1.0, 1.1, 1.2, 1.3];
      final blendValues = [0.0, 10, 20, 30, 300];

      Future<void> verifySettings(LiquidGlassSettings settings) async {
        await tester.pumpWidget(build(settings));
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
        final matteImage = geo!.matte.toImage(
          geo.matteBounds.width.ceil(),
          geo.matteBounds.height.ceil(),
        );

        await expectLater(
          matteImage,
          matchesGoldenFile(
            'goldens/geometry/liquid_glass_blend_group_geometry_'
            'thickness${settings.thickness}_'
            'refractiveIndex${settings.refractiveIndex}_'
            'blend${settings.blend}'
            '.png',
          ),
        );
      }

      await verifySettings(
        const LiquidGlassSettings(
          thickness: 0,
          refractiveIndex: 1.5,
          blend: 100,
        ),
      );

      for (final thickness in thicknesses) {
        for (final refractiveIndex in refractiveIndices) {
          for (final blend in blendValues) {
            final settings = LiquidGlassSettings(
              thickness: thickness.toDouble(),
              refractiveIndex: refractiveIndex,
              blend: blend.toDouble(),
            );
            await verifySettings(settings);
          }
        }
      }
    });
  });
}

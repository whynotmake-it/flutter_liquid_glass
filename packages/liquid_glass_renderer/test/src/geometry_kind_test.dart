// Run with `flutter test --enable-impeller --enable-flutter-gpu`: glass draws
// over its copy only where shader filters are supported.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/composer/plan_result.dart';
import 'package:liquid_glass_renderer/src/composer/plan_site.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/read.dart';
import 'package:liquid_glass_renderer/src/rendering/shading.dart';

import 'shared.dart';

Widget _scene({required double left, required int shapes}) => Directionality(
  textDirection: TextDirection.ltr,
  child: Stack(
    children: [
      const ColoredBox(color: Color(0xFF204060), child: SizedBox.expand()),
      Positioned.fill(
        child: LiquidGlassLayer(
          settings: LiquidGlassSettings.ios27RegularLight(),
          child: Stack(
            children: [
              for (var i = 0; i < shapes; i++)
                Positioned(
                  left: left,
                  top: 40.0 + i * 140,
                  width: 120,
                  height: 60,
                  child: const LiquidGlass(
                    shape: LiquidRoundedSuperellipse(borderRadius: 24),
                    child: SizedBox.expand(),
                  ),
                ),
            ],
          ),
        ),
      ),
    ],
  ),
);

void main() {
  setUp(() {
    debugGlassCopies = true;
  });

  tearDown(() {
    debugGlassCopies = null;
  });

  for (final (shapes, kind) in [(1, ComputedGeometry), (2, AtlasGeometry)]) {
    testWidgets('glass of $shapes shapes draws over its copy from the '
        'geometry its live filter draws, at rest and moving', (tester) async {
      var copies = 0;
      for (var step = 0; step < 6; step++) {
        await tester.pumpWidget(
          _scene(left: 20 + (step < 3 ? 0 : step * 7.0), shapes: shapes),
        );
        final layer = tester.allRenderObjects
            .whereType<RenderLiquidGlassLayer>()
            .toSet()
            .single;
        final fate = layer.debugFate;
        expect(fate, isA<LeadFate>(), reason: 'step $step');
        final read = (fate! as LeadFate).read;
        if (read.source is LiveRead) continue;
        copies++;
        expect(
          read.geometryKind,
          shapes == 1 ? const ComputedShape() : const OwnAtlas(),
          reason: 'step $step',
        );
        final live = layer.debugLiveDraw;
        final copy = layer.debugReadDraw!;
        expect(live.matte.geometry.runtimeType, kind, reason: 'step $step');
        expect(copy.matte.geometry.runtimeType, kind, reason: 'step $step');
        expect(copy.matte.geometry, live.matte.geometry, reason: 'step $step');
      }
      expect(copies, greaterThan(0));
      expect(tester.takeException(), isNull);
    }, skip: skipProperGlassTests);
  }
}

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_settings.dart';
import 'package:liquid_glass_renderer/src/rendering/frame_shapes.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';

import 'shared.dart';

Widget _scene(double scaleX, {double visibility = 1}) => Directionality(
  textDirection: TextDirection.ltr,
  child: LiquidGlassLayer(
    child: Center(
      child: Transform(
        transform: Matrix4.diagonal3Values(scaleX, 1, 1),
        alignment: Alignment.center,
        child: LiquidGlass(
          shape: const LiquidRoundedSuperellipse(radius: 20),
          appearance: LiquidGlassAppearance(visibility: visibility),
          child: const SizedBox(width: 80, height: 40),
        ),
      ),
    ),
  ),
);

RenderLiquidGlassLayer _layer(WidgetTester tester) =>
    tester.allRenderObjects.whereType<RenderLiquidGlassLayer>().toSet().single;

void main() {
  testWidgets(
    'a shape collapsed by its transform idles and keeps its geometry',
    (
      tester,
    ) async {
      await tester.pumpWidget(_scene(1));
      await tester.pump();
      final layer = _layer(tester);
      expect(layer.frameState, GlassFrameState.active);
      final geometry = layer.debugGeometry;
      expect(geometry, isNotNull);

      await tester.pumpWidget(_scene(0));
      await tester.pump();
      expect(layer.frameShapes.geometries, hasLength(1));
      expect(layer.frameShapes.drawn, isEmpty);
      expect(layer.frameState, GlassFrameState.idle);
      expect(layer.debugGeometry, same(geometry));

      await tester.pumpWidget(_scene(1));
      await tester.pump();
      expect(layer.frameState, GlassFrameState.active);
    },
    skip: skipProperGlassTests,
  );

  testWidgets('a hidden shape and a collapsed one count alike', (
    tester,
  ) async {
    for (final scene in [_scene(1, visibility: 0), _scene(0)]) {
      await tester.pumpWidget(scene);
      await tester.pump();
      final frame = _layer(tester).frameShapes;
      expect(frame.drawn, isEmpty);
      expect(frame.wornShortSide, frostFitShortSides.largest);
      expect(frame.state(encodesGeometry: true), GlassFrameState.idle);
      expect(frame.state(encodesGeometry: false), GlassFrameState.empty);
    }
  });
}

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/geometry_tiling.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';
import 'package:material_ui/material_ui.dart';

import 'gpu_test_helpers.dart';
import 'shared.dart';

/// Two drops of one blend group, the second [drift] logical pixels off its
/// place.
Widget _scene(Offset drift, {Key? key}) {
  return Directionality(
    key: key,
    textDirection: TextDirection.ltr,
    child: Center(
      child: SizedBox(
        width: 300,
        height: 160,
        child: LiquidGlassLayer(
          child: LiquidGlassBlendGroup(
            blend: 16,
            child: Stack(
              children: [
                const Positioned(
                  left: 10,
                  top: 20,
                  child: LiquidGlass.grouped(
                    shape: LiquidRoundedSuperellipse(borderRadius: 50),
                    child: SizedBox.square(dimension: 100),
                  ),
                ),
                Positioned(
                  left: 150 + drift.dx,
                  top: 40 + drift.dy,
                  child: const LiquidGlass.grouped(
                    shape: LiquidRoundedSuperellipse(borderRadius: 24),
                    child: SizedBox(width: 120, height: 70),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

RenderLiquidGlassLayer _layer(WidgetTester tester) =>
    tester.allRenderObjects.whereType<RenderLiquidGlassLayer>().last;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'shapes that drift keep their tiling until one leaves its slack',
    (tester) async {
      tester.view
        ..physicalSize = const Size(1200, 900)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      // A tenth of a logical pixel a frame: 0.3 device pixels.
      Offset at(int frame) => Offset(frame * 0.1, frame * 0.05);
      await tester.pumpWidget(_scene(at(0)));
      final renderer = _layer(tester).gpuGeometryRenderer!;
      final tilings = <Tiling>[_layer(tester).debugTiling!];
      for (var frame = 1; frame <= 30; frame++) {
        await tester.pumpWidget(_scene(at(frame)));
        tilings.add(_layer(tester).debugTiling!);
      }
      expect(renderer.debugRenderCount, 31, reason: 'every frame draws');
      // The first moves are tiled as they come; then a tiling serves its
      // shapes for six frames' worth of their drift.
      expect(tilings[0].slack, 0);
      expect(tilings[1].slack, 0);
      var tiled = 0;
      for (var frame = 3; frame <= 30; frame++) {
        expect(tilings[frame].slack, closeTo(2, 0.1), reason: 'frame $frame');
        if (!identical(tilings[frame].runs, tilings[frame - 1].runs)) tiled++;
      }
      expect(tiled, inInclusiveRange(4, 6));

      // The held atlas holds the shapes where they are: within NEAR of the
      // atlas a new layer draws of them, wherever both hold texels.
      final layer = _layer(tester);
      final held = layer.debugGeometryImage!.clone();
      addTearDown(held.dispose);
      final heldPlace = layer.debugGeometryPlace;
      final heldBounds = layer.debugGeometryMatteBounds;
      await tester.pumpWidget(_scene(at(30), key: UniqueKey()));
      final fresh = _layer(tester);
      expect(fresh.debugTiling!.slack, 0);
      final freshBounds = fresh.debugGeometryMatteBounds;
      final a = (await tester.runAsync(
        () => AtlasTexels.read(held, heldPlace),
      ))!;
      final b = (await tester.runAsync(
        () => AtlasTexels.read(
          fresh.debugGeometryImage!,
          fresh.debugGeometryPlace,
        ),
      ))!;
      final shift = (freshBounds.topLeft - heldBounds.topLeft) * 3;
      expect(shift.dx, closeTo(shift.dx.roundToDouble(), 1e-6));
      expect(shift.dy, closeTo(shift.dy.roundToDouble(), 1e-6));
      final reach = fresh.debugTiling!.reach;
      var compared = 0;
      var worst = 0.0;
      for (var y = 0; y < (freshBounds.height * 3).round(); y++) {
        for (var x = 0; x < (freshBounds.width * 3).round(); x++) {
          final here = b.pixel(x, y);
          final there = a.pixel(x + shift.dx.round(), y + shift.dy.round());
          if (here.$4 == 0 || there.$4 == 0) continue;
          compared++;
          // What a read can tell apart: past the reach it is outside, or
          // deep, whatever the texels there hold.
          double told(double inward) =>
              inward.clamp(-reach.outward, reach.inward);
          worst = max(worst, (told(here.$1) - told(there.$1)).abs());
        }
      }
      expect(compared, greaterThan(20000));
      expect(worst, lessThan(0.25));
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'shapes encoded again where they are take no slack',
    (tester) async {
      tester.view
        ..physicalSize = const Size(1200, 900)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_scene(Offset.zero));
      final layer = _layer(tester);
      final bounds = layer.debugGeometryMatteBounds;
      final renders = layer.gpuGeometryRenderer!.debugRenderCount;
      for (var frame = 1; frame <= 4; frame++) {
        layer
          // ignore: invalid_use_of_protected_member
          ..needsGeometryUpdate = true
          ..markNeedsPaint();
        await tester.pump();
        expect(layer.debugTiling!.slack, 0, reason: 'frame $frame');
        expect(layer.debugGeometryMatteBounds, bounds);
      }
      expect(layer.gpuGeometryRenderer!.debugRenderCount, renders + 4);
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'a shape that moves fast is tiled without slack',
    (tester) async {
      tester.view
        ..physicalSize = const Size(1200, 900)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      for (var frame = 0; frame <= 6; frame++) {
        await tester.pumpWidget(_scene(Offset(frame * 2.0, 0)));
        expect(_layer(tester).debugTiling!.slack, 0, reason: 'frame $frame');
      }
    },
    skip: skipProperGlassTests,
  );
}

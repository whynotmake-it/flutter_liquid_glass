// This regression intentionally inspects the renderer's compositor counters.
// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_render_scope.dart';
import 'package:liquid_glass_renderer/src/rendering/consolidated_fake_glass_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

import '../../test/src/submitted_scene_binding.dart';
import 'support/scrolling_glass.dart';

void main() {
  final binding = SubmittedSceneBinding();
  for (final fake in [true, false]) {
    for (final blended in [false, true]) {
      testWidgets(
        'glass tracks every submitted scroll frame '
        'blended=$blended fake=$fake',
        (
          tester,
        ) async {
          tester.view
            ..physicalSize = const Size(1080, 2100)
            ..devicePixelRatio = 2.625;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            CupertinoApp(
              home: LiquidGlassLayer(
                fake: fake,
                settings: LiquidGlassSettings.ios27ToolbarLight(),
                defaultAppearance:
                    const LiquidGlassAppearance.ios27ToolbarLight(),
                child: ScrollingGlass(blended: blended),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (!fake) {
            for (var frame = 0; frame < 60; frame++) {
              await tester.pump(const Duration(milliseconds: 16));
              if (tester
                  .widgetList<LiquidGlassRenderScope>(
                    find.byType(LiquidGlassRenderScope),
                  )
                  .every((s) => !s.consolidatesFakeBackdrop)) {
                break;
              }
            }
            expect(
              tester.widgetList<LiquidGlassRenderScope>(
                find.byType(LiquidGlassRenderScope),
              ),
              isNotEmpty,
            );
            expect(
              tester
                  .widgetList<LiquidGlassRenderScope>(
                    find.byType(LiquidGlassRenderScope),
                  )
                  .every((s) => !s.consolidatesFakeBackdrop),
              isTrue,
              reason:
                  'Real glass falls back to fake glass unless the tests run '
                  'with --enable-impeller --enable-flutter-gpu.',
            );
          }
          final position = tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position;
          final layer = tester.allRenderObjects.firstWhere(
            (object) => fake
                ? object is RenderConsolidatedFakeGlassLayer
                : object is RenderLiquidGlassLayer,
          );
          ({int paints, Offset translation}) layerState() => switch (layer) {
            RenderConsolidatedFakeGlassLayer() => (
              paints: layer.debugPaintCount,
              translation: layer.debugCompositorTranslation,
            ),
            RenderLiquidGlassLayer() => (
              paints: layer.debugPaintCount,
              translation: layer.debugCompositorTranslation,
            ),
            _ => throw StateError('Expected a glass layer'),
          };
          var paints = layerState().paints;
          var paintedOffset = 0.0;
          for (var frame = 1; frame <= 20; frame++) {
            final offset = (frame * 12.3).clamp(0.0, position.maxScrollExtent);
            position.jumpTo(offset);
            binding
              ..captured = null
              ..captureNextScene = true
              ..scheduleFrame();
            await tester.pump(const Duration(milliseconds: 16));
            final first = await tester.runAsync(() => binding.captured!);
            final firstBytes = await tester.runAsync(first!.toByteData);
            first.dispose();
            final state = layerState();
            if (state.paints != paints) {
              paints = state.paints;
              paintedOffset = offset;
            }
            expect(
              state.translation.dy,
              closeTo(paintedOffset - offset, 0.00001),
              reason:
                  'The submitted frame $frame must not use an older offset.',
            );
            binding
              ..captured = null
              ..captureNextScene = true
              ..scheduleFrame();
            await tester.pump();
            final next = await tester.runAsync(() => binding.captured!);
            final nextBytes = await tester.runAsync(next!.toByteData);
            next.dispose();
            var different = 0;
            final a = firstBytes!.buffer.asUint8List();
            final b = nextBytes!.buffer.asUint8List();
            for (var i = 0; i < a.length; i += 4) {
              if (a[i] != b[i] ||
                  a[i + 1] != b[i + 1] ||
                  a[i + 2] != b[i + 2]) {
                different++;
              }
            }
            expect(
              different,
              0,
              reason:
                  'The first submitted scene at frame $frame must not '
                  'catch up on the next frame.',
            );
          }
        },
      );
    }
  }
}

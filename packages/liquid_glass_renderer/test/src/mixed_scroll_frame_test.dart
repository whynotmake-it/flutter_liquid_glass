import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_render_scope.dart';
import 'package:liquid_glass_renderer/src/rendering/consolidated_fake_glass_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';

import 'shared.dart';
import 'submitted_scene_binding.dart';

void main() {
  final binding = SubmittedSceneBinding()
    ..captureWidth = 400
    ..captureHeight = 400;
  for (final fake in [true, false]) {
    for (final repaint in [false, true]) {
      testWidgets(
        'scrolling glass agrees on the first frame fake=$fake repaint=$repaint',
        (
          tester,
        ) async {
          tester.view
            ..physicalSize = const Size(400, 400)
            ..devicePixelRatio = 1;
          addTearDown(tester.view.reset);

          Future<Uint8List> capture({
            required bool moving,
            bool settle = false,
          }) async {
            final controller = ScrollController(
              initialScrollOffset: moving ? 0 : 50,
            );
            final key = GlobalKey();
            Widget glass() => const LiquidGlass(
              shape: LiquidRoundedRectangle(borderRadius: 16),
              appearance: LiquidGlassAppearance(tint: Color(0xCC2288EE)),
              child: SizedBox(width: 100, height: 70),
            );
            await tester.pumpWidget(
              MaterialApp(
                home: RepaintBoundary(
                  key: key,
                  child: ColoredBox(
                    color: Colors.white,
                    child: LiquidGlassLayer(
                      fake: fake,
                      settings: const LiquidGlassSettings(frost: 0),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CustomScrollView(
                              controller: controller,
                              slivers: [
                                SliverToBoxAdapter(
                                  child: Column(
                                    children: [
                                      const SizedBox(height: 120),
                                      glass(),
                                      const SizedBox(height: 700),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!repaint)
                            Positioned(left: 10, bottom: 10, child: glass()),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
            for (var frame = 0; frame < 60; frame++) {
              await tester.pump(const Duration(milliseconds: 16));
              final scopes = tester.widgetList<LiquidGlassRenderScope>(
                find.byType(LiquidGlassRenderScope),
              );
              if (fake ||
                  (scopes.isNotEmpty &&
                      scopes.every((s) => !s.consolidatesFakeBackdrop)))
                break;
            }
            await tester.pump();
            binding.captured = null;
            binding.captureNextScene = true;
            binding.scheduleFrame();
            if (moving) {
              controller.jumpTo(50);
              if (repaint) {
                for (final object in tester.allRenderObjects) {
                  if (object is LiquidGlassRenderObject ||
                      object is RenderConsolidatedFakeGlassLayer) {
                    object.markNeedsPaint();
                  }
                }
              }
              await tester.pump(const Duration(milliseconds: 16));
              if (settle) {
                final unused = await tester.runAsync(() => binding.captured!);
                unused!.dispose();
                binding.captured = null;
                binding.captureNextScene = true;
                binding.scheduleFrame();
                await tester.pump(const Duration(milliseconds: 16));
              }
            } else {
              await tester.pump();
            }
            final image = await tester.runAsync(() => binding.captured!);
            final bytes = await tester.runAsync(image!.toByteData);
            image.dispose();
            await tester.pumpWidget(const SizedBox.shrink());
            controller.dispose();
            return bytes!.buffer.asUint8List();
          }

          final reference = await capture(moving: false);
          final settled = await capture(moving: true, settle: true);
          expect(
            settled,
            orderedEquals(reference),
            reason: 'The next frame should confirm this is lag, not different geometry.',
          );
          final actual = await capture(moving: true);
          var different = 0;
          for (var i = 0; i < reference.length; i += 4) {
            if (reference[i] != actual[i] ||
                reference[i + 1] != actual[i + 1] ||
                reference[i + 2] != actual[i + 2])
              different++;
          }
          expect(
            different,
            0,
            reason: 'Glass must not trail the current Flutter frame.',
          );
        },
        skip: !fake && skipProperGlassTests,
      );
    }
  }
}

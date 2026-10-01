import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_render_scope.dart';

import 'shared.dart';

void main() {
  for (final fake in [true, false]) {
    for (final autoInGroup in [false, true]) {
      testWidgets(
        'Layer -> Glass -> Glass paints both materials '
        '(fake=$fake autoInGroup=$autoInGroup)',
        (
          tester,
        ) async {
          tester.view
            ..physicalSize = const Size(320, 240)
            ..devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          const settings = LiquidGlassSettings(thickness: 12, frost: 0);
          const appearance = LiquidGlassAppearance(tint: Color(0x803090FF));
          const shape = LiquidRoundedRectangle(borderRadius: 20);

          Future<({Uint8List png, Uint8List rgba})> render({
            required bool ownLayer,
          }) async {
            final key = GlobalKey();
            const content = SizedBox(width: 100, height: 60);
            final inner = ownLayer
                ? LiquidGlass.withOwnLayer(
                    fake: fake,
                    settings: settings,
                    appearance: appearance,
                    shape: shape,
                    child: content,
                  )
                : autoInGroup
                ? LiquidGlass.auto(
                    fake: fake,
                    settings: settings,
                    appearance: appearance,
                    shape: shape,
                    child: content,
                  )
                : const LiquidGlass(shape: shape, child: content);
            await tester.pumpWidget(
              MaterialApp(
                home: RepaintBoundary(
                  key: key,
                  child: ColoredBox(
                    color: Colors.white,
                    child: Center(
                      child: LiquidGlassLayer(
                        fake: fake,
                        settings: settings,
                        defaultAppearance: appearance,
                        child: LiquidGlassBlendGroup(
                          child: LiquidGlass.grouped(
                            shape: shape,
                            child: SizedBox(
                              width: 260,
                              height: 180,
                              child: Center(child: inner),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            for (var frame = 0; frame < 60; frame++) {
              await tester.pump(const Duration(milliseconds: 16));
              if (fake ||
                  tester
                      .widgetList<LiquidGlassRenderScope>(
                        find.byType(LiquidGlassRenderScope),
                      )
                      .every((scope) => !scope.consolidatesFakeBackdrop)) {
                break;
              }
            }
            await tester.pump();
            final image =
                await (key.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage();
            // Rasterize while the layer still owns its Flutter-GPU textures.
            // Read a deferred image before unmounting the layer.
            final png = await tester.runAsync(
              () => image.toByteData(format: ui.ImageByteFormat.png),
            );
            final rgba = await tester.runAsync(image.toByteData);
            image.dispose();
            await tester.pumpWidget(const SizedBox.shrink());
            return (
              png: png!.buffer.asUint8List(),
              rgba: rgba!.buffer.asUint8List(),
            );
          }

          final reference = await render(ownLayer: true);
          final nested = await render(ownLayer: false);
          final golden =
              'goldens/nested_shape_order_${fake ? "fake" : "real"}.png';
          await tester.runAsync(
            () => expectLater(reference.png, matchesGoldenFile(golden)),
          );
          if (!autoUpdateGoldenFiles) {
            await tester.runAsync(
              () => expectLater(nested.png, matchesGoldenFile(golden)),
            );
          }
          expect(
            nested.rgba,
            orderedEquals(reference.rgba),
            reason:
                'A nested shape must paint after its parent, not disappear '
                'into the same geometry union.',
          );
        },
        skip: !fake && skipProperGlassTests,
      );
    }
  }
}

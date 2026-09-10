import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_render_scope.dart';

import 'shared.dart';

void main() {
  for (final fake in [true, false]) {
    for (final kind in ['rect', 'rounded', 'superellipse', 'oval', 'path']) {
      for (final behavior in [
        Clip.none,
        Clip.hardEdge,
        Clip.antiAliasWithSaveLayer,
      ]) {
        testWidgets(
          'glass respects an intervening $kind clip $behavior (fake=$fake)',
          (
            tester,
          ) async {
            tester.view
              ..physicalSize = const Size(400, 300)
              ..devicePixelRatio = 1;
            addTearDown(tester.view.reset);

            Future<Uint8List> render({required bool clipAboveLayer}) async {
              final key = GlobalKey();
              const glass = OverflowBox(
                alignment: Alignment.topCenter,
                minHeight: 180,
                maxHeight: 180,
                child: LiquidGlass(
                  shape: LiquidRoundedRectangle(borderRadius: 20),
                  child: SizedBox(width: 260, height: 180),
                ),
              );
              Widget layer(Widget child) => LiquidGlassLayer(
                fake: fake,
                settings: const LiquidGlassSettings(thickness: 12, frost: 0),
                defaultAppearance: const LiquidGlassAppearance(
                  tint: Color(0xC00040FF),
                ),
                child: child,
              );
              Widget clip(Widget child) => switch (kind) {
                'rect' => ClipRect(clipBehavior: behavior, child: child),
                'rounded' => ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  clipBehavior: behavior,
                  child: child,
                ),
                'superellipse' => ClipRSuperellipse(
                  borderRadius: BorderRadius.circular(30),
                  clipBehavior: behavior,
                  child: child,
                ),
                'oval' => ClipOval(clipBehavior: behavior, child: child),
                'path' => ClipPath(
                  clipper: const ShapeBorderClipper(shape: StadiumBorder()),
                  clipBehavior: behavior,
                  child: child,
                ),
                _ => throw StateError(kind),
              };
              await tester.pumpWidget(
                MaterialApp(
                  home: RepaintBoundary(
                    key: key,
                    child: ColoredBox(
                      color: Colors.white,
                      child: Stack(
                        children: [
                          Positioned(
                            left: 50,
                            top: 60,
                            width: 300,
                            height: 100,
                            child: clipAboveLayer
                                ? clip(layer(glass))
                                : layer(clip(glass)),
                          ),
                        ],
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
              final boundary =
                  key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await boundary.toImage();
              final bytes = await tester.runAsync(image.toByteData);
              image.dispose();
              await tester.pumpWidget(const SizedBox.shrink());
              return bytes!.buffer.asUint8List();
            }

            final expected = await render(clipAboveLayer: true);
            final actual = await render(clipAboveLayer: false);
            const probe = (100 * 400 + 200) * 4;
            expect(
              expected[probe],
              lessThan(expected[probe + 2]),
              reason:
                  'The reference must visibly contain blue glass; two '
                  'equally missing filters are not a valid comparison.',
            );
            expect(
              actual,
              orderedEquals(expected),
              reason:
                  'Moving a clip below the layer must not let glass escape it.',
            );
          },
          skip: !fake && skipProperGlassTests,
        );
      }
    }
  }
}

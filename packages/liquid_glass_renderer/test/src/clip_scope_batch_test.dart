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
    for (final grouped in [false, true]) {
      testWidgets(
        'a fully clipped contributor cannot affect another scope '
        '(fake=$fake grouped=$grouped)',
        (tester) async {
          tester.view
            ..physicalSize = const Size(360, 280)
            ..devicePixelRatio = 1;
          addTearDown(tester.view.reset);

          Future<({Uint8List png, Uint8List rgba})> render(bool hidden) async {
            final key = GlobalKey();
            Widget glass({required bool hidden}) {
              final appearance = LiquidGlassAppearance(
                tint: hidden
                    ? const Color(0xE0FF2020)
                    : const Color(0xA03090FF),
              );
              const shape = LiquidRoundedRectangle(borderRadius: 24);
              final content = SizedBox(
                width: hidden ? 220 : 150,
                height: hidden ? 160 : 110,
                child: hidden ? const ColoredBox(color: Colors.green) : null,
              );
              return grouped
                  ? LiquidGlass.grouped(
                      appearance: appearance,
                      shape: shape,
                      glassContainsChild: hidden,
                      child: content,
                    )
                  : LiquidGlass(
                      appearance: appearance,
                      shape: shape,
                      glassContainsChild: hidden,
                      child: content,
                    );
            }

            Widget contents = Stack(
              children: [
                if (hidden)
                  Positioned(
                    left: 40,
                    top: 40,
                    child: ClipRect(
                      clipper: const _EmptyClipper(),
                      child: glass(hidden: true),
                    ),
                  ),
                Positioned(left: 110, top: 90, child: glass(hidden: false)),
              ],
            );
            if (grouped) {
              contents = LiquidGlassBlendGroup(blend: 32, child: contents);
            }
            await tester.pumpWidget(
              MaterialApp(
                home: RepaintBoundary(
                  key: key,
                  child: ColoredBox(
                    color: Colors.white,
                    child: LiquidGlassLayer(
                      fake: fake,
                      settings: const LiquidGlassSettings(
                        thickness: 12,
                        frost: 0,
                      ),
                      child: contents,
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

          final reference = await render(false);
          final actual = await render(true);
          final golden =
              'goldens/hidden_clip_contributor_'
              '${fake ? "fake" : "real"}_${grouped ? "group" : "plain"}.png';
          await tester.runAsync(
            () => expectLater(reference.png, matchesGoldenFile(golden)),
          );
          if (!autoUpdateGoldenFiles) {
            await tester.runAsync(
              () => expectLater(actual.png, matchesGoldenFile(golden)),
            );
          }
          expect(
            actual.rgba,
            orderedEquals(reference.rgba),
            reason:
                'A clipped shape and its contained child must not alter '
                'another scope, even when both leaves belong to one group.',
          );
        },
        skip: !fake && skipProperGlassTests,
      );
    }
  }
}

class _EmptyClipper extends CustomClipper<Rect> {
  const _EmptyClipper();

  @override
  Rect getClip(Size size) => Rect.zero;

  @override
  bool shouldReclip(_EmptyClipper oldClipper) => false;
}

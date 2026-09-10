import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

import 'shared.dart';
import 'submitted_scene_binding.dart';

void main() {
  final binding = SubmittedSceneBinding()
    ..captureWidth = 240
    ..captureHeight = 160;

  for (final grouped in [false, true]) {
    for (final mode in ['uniform', 'tint', 'response']) {
      testWidgets(
        'material update matches fresh scene: $mode grouped=$grouped',
        (tester) async {
          tester.view
            ..physicalSize = const Size(240, 160)
            ..devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final progress = ValueNotifier<double>(1);
          addTearDown(progress.dispose);

          Widget buildScene({
            required bool fresh,
            bool includeGlass = true,
          }) => MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Stack(
              children: [
                const Positioned.fill(child: ColoredBox(color: Colors.white)),
                const Positioned.fill(child: GridPaper(color: Colors.black)),
                if (includeGlass)
                  LiquidGlassLayer(
                    key: ValueKey(fresh),
                    settings: const LiquidGlassSettings(frost: 8),
                    child: ValueListenableBuilder<double>(
                      valueListenable: progress,
                      builder: (_, value, __) {
                        Widget shape(LiquidGlassAppearance appearance) =>
                            grouped
                            ? LiquidGlass.grouped(
                                appearance: appearance,
                                shape: const LiquidOval(),
                                child: const SizedBox.square(dimension: 80),
                              )
                            : LiquidGlass(
                                appearance: appearance,
                                shape: const LiquidOval(),
                                child: const SizedBox.square(dimension: 80),
                              );
                        final first = LiquidGlassAppearance(
                          tint: mode == 'tint'
                              ? Color.lerp(Colors.blue, Colors.red, value)!
                              : const Color(0x604080FF),
                          saturation: mode == 'response' ? 1 + value : 1,
                        );
                        final children = Stack(
                          children: [
                            Positioned(left: 35, top: 40, child: shape(first)),
                            Positioned(
                              left: 105,
                              top: 40,
                              child: shape(
                                mode == 'uniform'
                                    ? first
                                    : const LiquidGlassAppearance(
                                        tint: Color(0x60FF8040),
                                      ),
                              ),
                            ),
                          ],
                        );
                        return LiquidGlassVisibility(
                          visibility: mode == 'uniform' ? value : 1,
                          child: grouped
                              ? LiquidGlassBlendGroup(child: children)
                              : children,
                        );
                      },
                    ),
                  ),
              ],
            ),
          );

          Future<Uint8List> capture() async {
            binding
              ..captureNextScene = true
              ..scheduleFrame();
            await tester.pump();
            final image = (await tester.runAsync(() => binding.captured!))!;
            final bytes = (await tester.runAsync(image.toByteData))!;
            final result = Uint8List.fromList(bytes.buffer.asUint8List());
            image.dispose();
            return result;
          }

          await tester.pumpWidget(buildScene(fresh: false));
          await tester.pumpAndSettle();
          await pumpUntilGlassReady(tester);
          final before = await capture();
          final layer = tester.allRenderObjects
              .whereType<RenderLiquidGlassLayer>()
              .last;
          final renderer = layer.gpuGeometryRenderer!;
          final renderCount = renderer.debugRenderCount;
          // Verify retained resource identity, not just submission counts.
          // ignore: invalid_use_of_protected_member
          final matte = layer.geometryImage;
          progress.value = 0.4;
          final animated = await capture();
          expect(animated, isNot(orderedEquals(before)));
          expect(
            renderer.debugRenderCount,
            mode == 'uniform' ? renderCount : renderCount + 1,
          );
          if (mode == 'uniform') {
            // ignore: invalid_use_of_protected_member
            expect(layer.geometryImage, same(matte));
          }

          Uint8List? hidden;
          if (mode == 'uniform') {
            progress.value = 0;
            hidden = await capture();
            expect(layer.debugBackdropFilterLayer, isNull);
            expect(renderer.debugRenderCount, renderCount);
            // Hidden material retains the last matte but does not sample it.
            // ignore: invalid_use_of_protected_member
            expect(layer.geometryImage, same(matte));
            progress.value = 1;
            final restored = await capture();
            expect(restored, orderedEquals(before));
            // Zero changes contributor membership; restoration may rebuild
            // once, but the nonzero animation above must stay uniform-only.
            expect(renderer.debugRenderCount, renderCount + 1);
            progress.value = 0.4;
            expect(await capture(), orderedEquals(animated));
            expect(renderer.debugRenderCount, renderCount + 1);
          }

          await tester.pumpWidget(buildScene(fresh: true));
          await tester.pumpAndSettle();
          await pumpUntilGlassReady(tester);
          final reference = await capture();
          expect(
            animated,
            orderedEquals(reference),
            reason: 'Retained material inputs must match a fresh static frame.',
          );
          if (hidden != null) {
            await tester.pumpWidget(
              buildScene(fresh: true, includeGlass: false),
            );
            expect(
              hidden,
              orderedEquals(await capture()),
              reason: 'Hidden glass must leave the backdrop untouched.',
            );
          }
        },
        skip: skipProperGlassTests,
      );
    }
  }
}

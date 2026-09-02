import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/multi_shader_builder.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';

import 'shared.dart';
import 'submitted_scene_binding.dart';

void main() {
  final binding = SubmittedSceneBinding()
    ..captureWidth = 240
    ..captureHeight = 160;

  for (final fake in [true, false]) {
    testWidgets(
      'composition preserves foreground bounds and motion fake=$fake',
      (
        tester,
      ) async {
        tester.view
          ..physicalSize = const Size(240, 160)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.runAsync(
          () => MultiShaderBuilder.precacheShaders([
            ShaderKeys.fakeGlassSurface,
            ShaderKeys.liquidGlassRender,
            ShaderKeys.liquidGlassMaterialRender,
            ShaderKeys.liquidGlassTintRender,
          ]),
        );
        final movement = ValueNotifier(Offset.zero);
        addTearDown(movement.dispose);
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: ColoredBox(
              color: Colors.white,
              child: LiquidGlassLayer(
                fake: fake,
                child: Stack(
                  children: [
                    Positioned(
                      left: 35,
                      top: 40,
                      child: ValueListenableBuilder<Offset>(
                        valueListenable: movement,
                        child: const LiquidGlass(
                          shape: LiquidOval(),
                          child: SizedBox.square(
                            dimension: 80,
                            child: Center(
                              child: SizedBox.square(
                                dimension: 10,
                                child: ColoredBox(color: Colors.red),
                              ),
                            ),
                          ),
                        ),
                        builder: (_, value, child) => Transform.translate(
                          offset: value,
                          child: child,
                        ),
                      ),
                    ),
                    const Positioned(
                      left: 190,
                      top: 70,
                      child: SizedBox.square(
                        dimension: 20,
                        child: ColoredBox(color: Colors.blue),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (!fake) await pumpUntilGlassReady(tester);
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

        List<int> pixel(Uint8List frame, int x, int y) =>
            frame.sublist((y * 240 + x) * 4, (y * 240 + x) * 4 + 4);
        final before = await capture();
        movement.value = const Offset(20, 0);
        final moved = await capture();
        expect(
          [
            pixel(before, 200, 80),
            pixel(moved, 200, 80),
            pixel(before, 75, 80),
            pixel(moved, 95, 80),
          ],
          [
            [33, 150, 243, 255],
            [33, 150, 243, 255],
            [244, 67, 54, 255],
            [244, 67, 54, 255],
          ],
          reason:
              'Backdrop clips must not clip unrelated foreground, and '
              'retained motion must move a glass child exactly once.',
        );
      },
      skip: !fake && skipProperGlassTests,
    );
  }
}

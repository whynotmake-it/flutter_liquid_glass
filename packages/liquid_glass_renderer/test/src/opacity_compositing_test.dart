import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/fake_glass_color.dart';
import 'package:liquid_glass_renderer/src/internal/multi_shader_builder.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';

import 'shared.dart';
import 'submitted_scene_binding.dart';

void main() {
  runOpacityTests(SubmittedSceneBinding());
}

void runOpacityTests(SubmittedSceneCapture binding) {
  binding
    ..captureWidth = 240
    ..captureHeight = 160;

  for (final kind in [
    'native',
    'nativeMaterial',
    'nativeSibling',
    'fake',
    'real',
  ]) {
    testWidgets(
      '$kind opacity approaches opaque output',
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
        final opacity = AnimationController(vsync: tester, value: 1);
        addTearDown(opacity.dispose);

        Widget fade(Widget child) => ValueListenableBuilder<double>(
          valueListenable: opacity,
          child: child,
          builder: (_, value, child) => Opacity(opacity: value, child: child),
        );
        const shape = LiquidGlass(
          shape: LiquidRoundedRectangle(borderRadius: 20),
          child: SizedBox(
            width: 160,
            height: 100,
            child: Center(
              child: SizedBox.square(
                dimension: 10,
                child: ColoredBox(color: Colors.red),
              ),
            ),
          ),
        );
        final Widget glass;
        if (kind.startsWith('native')) {
          final backdrop = ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: kind == 'native'
                  ? ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8)
                  : fakeGlassBackdropFilter(
                      const LiquidGlassSettings(frost: 8),
                      LiquidGlassAppearance.ios27Toolbar(
                        brightness: Brightness.light,
                      ),
                    )!,
              child: kind == 'nativeMaterial'
                  ? const SizedBox(
                      width: 160,
                      height: 100,
                      child: Center(
                        child: SizedBox.square(
                          dimension: 10,
                          child: ColoredBox(color: Colors.red),
                        ),
                      ),
                    )
                  : const SizedBox(width: 160, height: 100),
            ),
          );
          glass = fade(
            kind == 'nativeSibling'
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      backdrop,
                      const SizedBox.square(
                        dimension: 10,
                        child: ColoredBox(color: Colors.red),
                      ),
                    ],
                  )
                : backdrop,
          );
        } else {
          final layer = LiquidGlassLayer(
            fake: kind == 'fake',
            settings: const LiquidGlassSettings(
              frost: 8,
              highlight: 0,
              chromaticAberration: 0,
            ),
            child: shape,
          );
          glass = fade(layer);
        }
        Widget scene(Widget child) => MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Stack(
            children: [
              const Positioned.fill(child: ColoredBox(color: Colors.white)),
              const Positioned.fill(child: GridPaper(color: Colors.black)),
              Center(child: child),
            ],
          ),
        );
        await tester.pumpWidget(scene(glass));
        await tester.pumpAndSettle();

        Future<Uint8List> capture(double value) async {
          opacity.value = value;
          binding
            ..captured = null
            ..captureNextScene = true
            ..scheduleFrame();
          await tester.pump();
          expect(
            binding.captureNextScene,
            isFalse,
            reason: 'This pump must submit the requested scene.',
          );
          expect(
            binding.captured,
            isNotNull,
            reason: 'Never reuse a previous frame or test capture.',
          );
          final image = (await tester.runAsync(() => binding.captured!))!;
          final bytes = (await tester.runAsync(image.toByteData))!;
          final copy = Uint8List.fromList(bytes.buffer.asUint8List());
          image.dispose();
          return copy;
        }

        final full = await capture(1);
        final renderer = kind == 'real'
            ? tester.allRenderObjects.whereType<RenderLiquidGlassLayer>().last
            : null;
        final geometryCount = renderer?.gpuGeometryRenderer?.debugRenderCount;
        final almost = await capture(254 / 255);
        final half = await capture(0.5);
        final zero = await capture(0);
        final restored = await capture(1);
        var restorationError = 0;
        for (var i = 0; i < full.length; i++) {
          final error = (restored[i] - full[i]).abs();
          if (error > restorationError) restorationError = error;
        }
        expect(restorationError, lessThanOrEqualTo(3));
        if (renderer != null) {
          expect(
            renderer.gpuGeometryRenderer?.debugRenderCount,
            geometryCount,
          );
        }
        await tester.pumpWidget(scene(const SizedBox.shrink()));
        final background = await capture(0);
        var visibleDifference = 0;
        var maxJump = 0;
        var halfError = 0;
        var zeroError = 0;
        for (var i = 0; i < full.length; i += 4) {
          for (var channel = 0; channel < 3; channel++) {
            final index = i + channel;
            final hiddenError = (zero[index] - background[index]).abs();
            if (hiddenError > zeroError) zeroError = hiddenError;
            final difference = (full[index] - zero[index]).abs();
            if (difference > visibleDifference) {
              visibleDifference = difference;
            }
            final jump = (full[index] - almost[index]).abs();
            if (jump > maxJump) maxJump = jump;
            final error =
                (half[index] - (full[index] * 128 + zero[index] * 127) / 255)
                    .abs()
                    .round();
            if (error > halfError) halfError = error;
          }
        }
        expect(
          visibleDifference,
          greaterThan(10),
          reason:
              'Opacity must actually fade the material, not just its child.',
        );
        expect(
          maxJump,
          lessThanOrEqualTo(3),
          reason: 'Discontinuity at opaque; half-opacity error=$halfError',
        );
        expect(
          zeroError,
          0,
          reason: 'Zero opacity must leave only the backdrop.',
        );
        expect(halfError, lessThanOrEqualTo(3));
      },
      skip: kind == 'real' && skipProperGlassTests,
    );
  }
}

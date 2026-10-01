import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/liquid_glass_render_scope.dart';

import 'shared.dart';
import 'submitted_scene_binding.dart';

void main() {
  final binding = SubmittedSceneBinding()
    ..captureWidth = 420
    ..captureHeight = 440;
  for (final fake in [true, false]) {
    testWidgets('submitted nested frame survives a later scroll fake=$fake', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(420, 440)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _scene(
          key: GlobalKey(),
          controller: controller,
          fake: fake,
          ownLayer: true,
        ),
      );
      for (var frame = 0; frame < 60; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (fake ||
            tester
                .widgetList<LiquidGlassRenderScope>(
                  find.byType(LiquidGlassRenderScope),
                )
                .every((s) => !s.consolidatesFakeBackdrop)) {
          break;
        }
      }
      if (!fake) {
        final scopes = tester.widgetList<LiquidGlassRenderScope>(
          find.byType(LiquidGlassRenderScope),
        );
        expect(scopes, isNotEmpty);
        expect(scopes.every((s) => !s.consolidatesFakeBackdrop), isTrue);
      }
      binding
        ..captureNextScene = true
        ..scheduleFrame();
      await tester.pump();
      final reference = await tester.runAsync(() => binding.captured!);
      final referenceBytes = await tester.runAsync(reference!.toByteData);
      reference.dispose();

      final pendingBuilder = ui.SceneBuilder()
        ..addRetained(
          tester.binding.renderViews.single.debugLayer!.engineLayer!,
        );
      final pending = pendingBuilder.build();
      controller.jumpTo(75);
      await tester.pump(const Duration(milliseconds: 16));
      final submitted = await tester.runAsync(() => pending.toImage(420, 440));
      final submittedBytes = await tester.runAsync(submitted!.toByteData);
      submitted.dispose();
      pending.dispose();
      final a = referenceBytes!.buffer.asUint8List();
      final b = submittedBytes!.buffer.asUint8List();
      var different = 0;
      for (var i = 0; i < a.length; i += 4) {
        if (a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2]) {
          different++;
        }
      }
      expect(
        different,
        0,
        reason:
            'A later scroll must not mutate an already-submitted nested frame.',
      );
    }, skip: !fake && skipProperGlassTests);
    for (final ownLayer in [false, true]) {
      final name =
          '${fake ? "fake" : "real"} '
          'ownLayer=$ownLayer';
      testWidgets('sliver nested glass matches static destination $name', (
        tester,
      ) async {
        tester.view
          ..physicalSize = const Size(420, 440)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        Future<({Uint8List png, Uint8List rgba})> render(
          double initial, {
          required double destination,
          bool scroll = false,
        }) async {
          final controller = ScrollController(initialScrollOffset: initial);
          final key = GlobalKey();
          await tester.pumpWidget(
            _scene(
              key: key,
              controller: controller,
              fake: fake,
              ownLayer: ownLayer,
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
          if (!fake) {
            final scopes = tester.widgetList<LiquidGlassRenderScope>(
              find.byType(LiquidGlassRenderScope),
            );
            expect(scopes, isNotEmpty);
            expect(
              scopes.every((scope) => !scope.consolidatesFakeBackdrop),
              isTrue,
              reason: 'Real-glass coverage must not use the fake fallback.',
            );
          }
          binding.captured = null;
          if (!scroll) {
            binding
              ..captureNextScene = true
              ..scheduleFrame();
          }
          await tester.pump();
          if (scroll) {
            for (final offset in [30.0, 75.0, destination]) {
              controller.jumpTo(offset);
              if (offset == destination) {
                binding
                  ..captureNextScene = true
                  ..scheduleFrame();
              }
              await tester.pump(const Duration(milliseconds: 16));
            }
          }
          final image = await tester.runAsync(() => binding.captured!);
          final png = await tester.runAsync(
            () => image!.toByteData(format: ui.ImageByteFormat.png),
          );
          final rgba = await tester.runAsync(image!.toByteData);
          image.dispose();
          await tester.pumpWidget(const SizedBox.shrink());
          controller.dispose();
          return (
            png: png!.buffer.asUint8List(),
            rgba: rgba!.buffer.asUint8List(),
          );
        }

        for (final destination in [125.0, 280.0]) {
          final reference = await render(
            destination,
            destination: destination,
          );
          final scrolled = await render(
            0,
            scroll: true,
            destination: destination,
          );
          if (!fake && !ownLayer && destination == 280) {
            const golden = 'goldens/nested_scroll_clipped_real.png';
            await tester.runAsync(
              () => expectLater(reference.png, matchesGoldenFile(golden)),
            );
            if (!autoUpdateGoldenFiles) {
              await tester.runAsync(
                () => expectLater(scrolled.png, matchesGoldenFile(golden)),
              );
            }
          }
          final expected = reference.rgba;
          final actual = scrolled.rgba;
          var differentPixels = 0;
          for (var i = 0; i < actual.length; i += 4) {
            if (actual[i] != expected[i] ||
                actual[i + 1] != expected[i + 1] ||
                actual[i + 2] != expected[i + 2] ||
                actual[i + 3] != expected[i + 3]) {
              differentPixels++;
            }
          }
          expect(
            differentPixels,
            0,
            reason:
                'A moved frame must equal an independently laid-out '
                'static scene at $destination, including nested clips and '
                'backdrop optics.',
          );
        }
      }, skip: !fake && skipProperGlassTests);
    }
  }
}

Widget _scene({
  required GlobalKey key,
  required ScrollController controller,
  required bool fake,
  required bool ownLayer,
}) {
  const innerContent = SizedBox(
    width: 92,
    height: 58,
    child: ColoredBox(
      color: Color(0x8090FF40),
      child: Center(child: Text('lens')),
    ),
  );
  const shape = LiquidRoundedSuperellipse(borderRadius: 20);
  final inner = ownLayer
      ? LiquidGlass.withOwnLayer(
          fake: fake,
          settings: const LiquidGlassSettings(thickness: 10, frost: 0),
          shape: shape,
          child: innerContent,
        )
      : const LiquidGlass(
          shape: shape,
          child: innerContent,
        );
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    home: RepaintBoundary(
      key: key,
      child: Stack(
        children: [
          const Positioned.fill(
            child: ColoredBox(
              color: Colors.white,
              child: GridPaper(color: Colors.black, interval: 24),
            ),
          ),
          Positioned.fill(
            child: LiquidGlassLayer(
              fake: fake,
              settings: const LiquidGlassSettings(thickness: 18, frost: 4),
              defaultAppearance: const LiquidGlassAppearance(
                tint: Color(0x403090FF),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: CustomScrollView(
                  controller: controller,
                  slivers: [
                    SliverToBoxAdapter(
                      child: Column(
                        children: [
                          const SizedBox(height: 180),
                          LiquidGlass(
                            shape: const LiquidRoundedSuperellipse(
                              borderRadius: 32,
                            ),
                            child: SizedBox(
                              width: 280,
                              height: 180,
                              child: Center(child: inner),
                            ),
                          ),
                          const SizedBox(height: 500),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

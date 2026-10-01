import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

import 'shared.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  runGeometrySubmitBatchingTests();
}

final _boundaryKey = GlobalKey();

/// Three layers rebuilding every frame; the middle one mixes appearances, so
/// it records a matte and a material pass. This multi-pass frame crashed
/// Vulkan and Metal when its passes shared one command buffer.
Widget _scene(double t, {Key? key}) {
  Widget layer(double width, {bool tinted = false}) => LiquidGlassLayer(
    settings: const LiquidGlassSettings(contourWidth: 1, contourStrength: 0.3),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        LiquidGlass(
          shape: const LiquidRoundedSuperellipse(borderRadius: 22),
          child: SizedBox(width: width, height: 44),
        ),
        const SizedBox(width: 8),
        LiquidGlass(
          shape: const LiquidOval(),
          appearance: tinted
              ? const LiquidGlassAppearance(tint: Color(0x552060FF))
              : null,
          child: const SizedBox(width: 44, height: 44),
        ),
      ],
    ),
  );

  return Directionality(
    key: key,
    textDirection: TextDirection.ltr,
    child: RepaintBoundary(
      key: _boundaryKey,
      child: ColoredBox(
        color: Colors.white,
        child: Stack(
          children: [
            const Positioned.fill(child: GridPaper(color: Colors.black)),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  layer(120 + t),
                  const SizedBox(height: 16),
                  layer(90 + t * 2, tinted: true),
                  const SizedBox(height: 16),
                  layer(150 - t),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<Uint8List> _bytes(WidgetTester tester, ui.Image image) async {
  final bytes = await tester.runAsync(image.toByteData);
  return bytes!.buffer.asUint8List();
}

/// The top-left [width] x [height] texels of [image], as RGBA bytes.
///
/// Geometry textures only grow and each render fills a top-left sub-rect, so
/// texels outside it are undefined and never sampled.
Future<Uint8List> _subRect(
  WidgetTester tester,
  ui.Image image,
  int width,
  int height,
) async {
  final bytes = await _bytes(tester, image);
  final out = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    out.setRange(
      y * width * 4,
      (y + 1) * width * 4,
      bytes,
      y * image.width * 4,
    );
  }
  return out;
}

/// Each layer's matte sub-rect, then the composited frame, which also covers
/// the material maps.
Future<List<Uint8List>> _capture(WidgetTester tester) async {
  final result = <Uint8List>[];
  final dpr = tester.view.devicePixelRatio;
  for (final layer
      in tester.allRenderObjects.whereType<RenderLiquidGlassLayer>()) {
    final size = layer.debugGeometryMatteBounds.size * dpr;
    result.add(
      await _subRect(
        tester,
        layer.debugGeometryImage!,
        size.width.round(),
        size.height.round(),
      ),
    );
  }
  final boundary =
      _boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final frame = await tester.runAsync(boundary.toImage);
  result.add(await _bytes(tester, frame!));
  frame.dispose();
  return result;
}

/// Also runs on devices from `example/integration_test`.
void runGeometrySubmitBatchingTests() {
  tearDown(() => FlutterGpuGeometryRenderer.debugSubmitImmediately = false);

  testWidgets(
    'passes recorded in a frame are submitted while its scene is built',
    (tester) async {
      tester.view
        ..physicalSize = const Size(900, 900)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_scene(0));
      final postFrameFlushes =
          FlutterGpuGeometryRenderer.debugPostFrameFlushCount;
      for (var frame = 1; frame <= 10; frame++) {
        final passes = FlutterGpuGeometryRenderer.debugDeferredPassCount;
        final submits = FlutterGpuGeometryRenderer.debugBatchedSubmitCount;
        await tester.pumpWidget(_scene(frame * 0.5));
        final framePasses =
            FlutterGpuGeometryRenderer.debugDeferredPassCount - passes;
        final frameSubmits =
            FlutterGpuGeometryRenderer.debugBatchedSubmitCount - submits;
        if (!kDebugMode) continue;
        expect(framePasses, 4, reason: 'three mattes and one material map');
        expect(frameSubmits, 4, reason: 'one command buffer per pass');
      }
      if (kDebugMode) {
        expect(
          FlutterGpuGeometryRenderer.debugPostFrameFlushCount,
          postFrameFlushes,
          reason: 'the scene build must flush before the scene is rendered',
        );
      }
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'batched passes produce the same mattes and frame as immediate ones',
    (tester) async {
      tester.view
        ..physicalSize = const Size(900, 900)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      for (var frame = 0; frame <= 12; frame++) {
        await tester.pumpWidget(_scene(frame * 0.5));
      }
      final batched = await _capture(tester);

      FlutterGpuGeometryRenderer.debugSubmitImmediately = true;
      for (var frame = 0; frame <= 12; frame++) {
        await tester.pumpWidget(_scene(frame * 0.5, key: UniqueKey()));
      }
      final immediate = await _capture(tester);

      expect(batched.length, immediate.length);
      for (var index = 0; index < batched.length; index++) {
        expect(batched[index], immediate[index], reason: 'capture $index');
      }
    },
    skip: skipProperGlassTests,
  );
}

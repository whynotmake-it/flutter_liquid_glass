import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

import 'shared.dart';

Widget _scene(double width, {Key? key}) {
  return Directionality(
    key: key,
    textDirection: TextDirection.ltr,
    child: Center(
      child: LiquidGlassLayer(
        settings: const LiquidGlassSettings(
          contourWidth: 1,
          contourStrength: 0.3,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LiquidGlass(
              shape: const LiquidRoundedSuperellipse(borderRadius: 22),
              child: SizedBox(width: width, height: 44),
            ),
            const SizedBox(width: 12),
            // A second appearance, so every render also writes a material
            // map.
            const LiquidGlass(
              shape: LiquidOval(),
              appearance: LiquidGlassAppearance(tint: Color(0x552060FF)),
              child: SizedBox(width: 44, height: 44),
            ),
          ],
        ),
      ),
    ),
  );
}

RenderLiquidGlassLayer _layer(WidgetTester tester) =>
    tester.allRenderObjects.whereType<RenderLiquidGlassLayer>().last;

/// The top-left [width] x [height] texels of [image], as RGBA bytes.
Future<Uint8List> _subRect(
  WidgetTester tester,
  ui.Image image,
  int width,
  int height,
) async {
  final data = await tester.runAsync(image.toByteData);
  final bytes = data!.buffer.asUint8List();
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

int get _allocated => FlutterGpuGeometryRenderer.debugAllocatedTextureCount;
int get _dropped => FlutterGpuGeometryRenderer.debugDroppedTextureCount;
int get _reused => FlutterGpuGeometryRenderer.debugReusedTextureCount;

void main() {
  setUp(() {
    FlutterGpuGeometryRenderer.debugReusedTextureCount = 0;
  });

  void useDpr3(WidgetTester tester) {
    tester.view
      ..physicalSize = const Size(2400, 600)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets(
    'a changing matte ping-pongs between two textures',
    (tester) async {
      useDpr3(tester);
      // 0.05 logical px per frame keeps the 64 px bucket, like a stretch.
      await tester.pumpWidget(_scene(130));
      final renderer = _layer(tester).gpuGeometryRenderer!;
      final textures = <Object?>[renderer.debugMatteTexture];
      for (var frame = 1; frame <= 8; frame++) {
        await tester.pumpWidget(_scene(130 + frame * 0.05));
        textures.add(renderer.debugMatteTexture);
      }
      for (var frame = 1; frame < textures.length; frame++) {
        expect(
          identical(textures[frame], textures[frame - 1]),
          isFalse,
          reason: 'frame $frame must not rewrite the texture on screen',
        );
      }
      for (var frame = 2; frame < textures.length; frame++) {
        expect(
          identical(textures[frame], textures[frame - 2]),
          isTrue,
          reason: 'frame $frame reuses the texture retired one frame earlier',
        );
      }
      expect(renderer.debugMatteTextureCount, 2);
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'a resize sweep stops allocating once the texture has grown',
    (tester) async {
      useDpr3(tester);
      // 4 logical px per frame at DPR 3 crosses a 64 px bucket every few
      // frames, in both directions.
      double width(int frame) {
        final phase = frame % 100;
        return 130 + 4.0 * (phase < 50 ? phase : 100 - phase);
      }

      await tester.pumpWidget(_scene(width(0)));
      final renderer = _layer(tester).gpuGeometryRenderer!;
      // Two sweeps, which also outlast the expiry of textures released by
      // earlier tests.
      for (var frame = 1; frame < 200; frame++) {
        await tester.pumpWidget(_scene(width(frame)));
      }
      final allocatedBefore = _allocated;
      final droppedBefore = _dropped;
      final reusedBefore = _reused;
      const measured = 200;
      for (var frame = 200; frame < 200 + measured; frame++) {
        await tester.pumpWidget(_scene(width(frame)));
      }
      expect(_allocated - allocatedBefore, 0);
      expect(_dropped - droppedBefore, 0);
      expect(
        _reused - reusedBefore,
        2 * measured,
        reason: 'every matte and material map comes from the ring',
      );
      final (textureWidth, _) = renderer.debugMatteTextureSize!;
      expect(textureWidth, lessThanOrEqualTo(2432), reason: 'capped at view');
      expect(renderer.debugMatteTextureCount, 2);
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'a matte in a sub-rect of a larger texture is byte-identical to a fresh '
    'one',
    (tester) async {
      useDpr3(tester);
      // Grow the texture, then come back to a much smaller matte.
      for (var frame = 0; frame < 20; frame++) {
        await tester.pumpWidget(_scene(130 + frame * 12.0));
      }
      for (var frame = 0; frame < 4; frame++) {
        await tester.pumpWidget(_scene(131.5 + frame * 0.01));
      }
      final reusedBefore = _reused;
      await tester.pumpWidget(_scene(131.5));
      expect(
        _reused - reusedBefore,
        2,
        reason: 'the compared matte and material map must be reused textures',
      );
      final layer = _layer(tester);
      final matteSize = layer.debugGeometryMatteBounds.size * 3;
      final width = matteSize.width.round();
      final height = matteSize.height.round();
      final (textureWidth, textureHeight) =
          layer.gpuGeometryRenderer!.debugMatteTextureSize!;
      expect(textureWidth * textureHeight, greaterThan(width * height));
      final reusedImage = layer.debugGeometryImage!.clone();
      final reusedMaterialImage = layer.debugMaterialImage!.clone();
      addTearDown(reusedImage.dispose);
      addTearDown(reusedMaterialImage.dispose);

      // A new layer owns a new renderer, whose first textures are
      // exact-size, so its images are the reference sub-rects.
      await tester.pumpWidget(_scene(131.5, key: UniqueKey()));
      final fresh = _layer(tester);
      expect(fresh.debugGeometryImage!.width, width);
      final materialWidth = fresh.debugMaterialImage!.width;
      final materialHeight = fresh.debugMaterialImage!.height;
      expect(
        reusedMaterialImage.width * reusedMaterialImage.height,
        greaterThan(materialWidth * materialHeight),
      );
      final reused = await _subRect(tester, reusedImage, width, height);
      final reusedMaterial = await _subRect(
        tester,
        reusedMaterialImage,
        materialWidth,
        materialHeight,
      );
      final freshMatte = await _subRect(
        tester,
        fresh.debugGeometryImage!,
        width,
        height,
      );
      final freshMaterial = await _subRect(
        tester,
        fresh.debugMaterialImage!,
        materialWidth,
        materialHeight,
      );

      expect(reused, freshMatte);
      expect(reusedMaterial, freshMaterial);
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'a released texture is claimed by the next layer',
    (tester) async {
      useDpr3(tester);
      await tester.pumpWidget(_scene(130, key: const ValueKey('a')));
      await tester.pumpWidget(_scene(130.05, key: const ValueKey('a')));
      await tester.pumpWidget(const SizedBox());
      expect(FlutterGpuGeometryRenderer.debugReleasedTextureCount, 4);
      await tester.pump();

      final allocatedBefore = _allocated;
      final droppedBefore = _dropped;
      await tester.pumpWidget(_scene(130, key: const ValueKey('b')));
      expect(_allocated - allocatedBefore, 0);
      expect(_dropped - droppedBefore, 0);
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'spare textures are released once geometry stops changing',
    (tester) async {
      useDpr3(tester);
      for (var frame = 0; frame < 4; frame++) {
        await tester.pumpWidget(_scene(130 + frame * 0.05));
      }
      final renderer = _layer(tester).gpuGeometryRenderer!;
      expect(renderer.debugRetiredTextureCount, greaterThan(0));
      for (var frame = 0; frame < 130; frame++) {
        await tester.pump(const Duration(milliseconds: 8));
        tester.binding.scheduleFrame();
      }
      expect(renderer.debugRetiredTextureCount, 0);
    },
    skip: skipProperGlassTests,
  );
}

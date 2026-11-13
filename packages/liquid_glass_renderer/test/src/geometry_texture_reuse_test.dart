import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/geometry_tiling.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';
import 'package:material_ui/material_ui.dart';

import 'gpu_test_helpers.dart';
import 'shared.dart';

Widget _glass(double width) => LiquidGlassLayer(
  settings: const LiquidGlassSettings(
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
      // A second appearance, so every render also writes a look.
      const LiquidGlass(
        shape: LiquidOval(),
        appearance: LiquidGlassAppearance(tint: Color(0x552060FF)),
        child: SizedBox(width: 44, height: 44),
      ),
    ],
  ),
);

/// One layer of glass [width] wide; with [above], below another that wide.
Widget _scene(double width, {Key? key, double? above}) {
  return Directionality(
    key: key,
    textDirection: TextDirection.ltr,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (above != null) ...[_glass(above), const SizedBox(height: 12)],
          _glass(width),
        ],
      ),
    ),
  );
}

RenderLiquidGlassLayer _layer(WidgetTester tester) => _layers(tester).last;

/// The layers that hold an atlas, in paint order.
List<RenderLiquidGlassLayer> _layers(WidgetTester tester) => {
  for (final layer
      in tester.allRenderObjects.whereType<RenderLiquidGlassLayer>())
    if (layer.debugGeometryImage != null) layer,
}.toList();

/// What the final shader reads of the [width] x [height] geometry buffer
/// in the atlas at [place] in [image], pixel by pixel.
Future<List<(double, double, double, double)>> _geometry(
  WidgetTester tester,
  ui.Image image,
  AtlasPlace place,
  int width,
  int height,
) async {
  final atlas = (await tester.runAsync(() => AtlasTexels.read(image, place)))!;
  return [
    for (var y = 0; y < height; y++)
      for (var x = 0; x < width; x++) atlas.pixel(x, y),
  ];
}

/// A tint beside [testRectangle].
final _tint = ShapeLooks(const [1, 0, 0, 1, 1, 1, 0, 1], tintOnly: true);

/// What the final shader reads of [look], a texture beside the atlas at
/// [place] in [image] of a [width] x [height] geometry buffer, pixel by
/// pixel.
Future<List<(double, double, double, double)>> _looks(
  WidgetTester tester,
  ui.Image image,
  AtlasPlace place,
  ui.Image look,
  int width,
  int height,
) async {
  final atlas = (await tester.runAsync(() => AtlasTexels.read(image, place)))!;
  final texels = (await tester.runAsync(() => AtlasTexels.read(look)))!;
  return [
    for (var y = 0; y < height; y++)
      for (var x = 0; x < width; x++) atlas.lookAt(texels, x, y),
  ];
}

int get _allocated => FlutterGpuGeometryRenderer.debugAllocatedTextureCount;
int get _dropped => FlutterGpuGeometryRenderer.debugDroppedTextureCount;
int get _reused => FlutterGpuGeometryRenderer.debugReusedTextureCount;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  runGeometryTextureReuseTests();
}

/// Also runs on devices from `example/integration_test/geometry_batch_test.dart`.
void runGeometryTextureReuseTests() {
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
    'a changing atlas ping-pongs between two textures',
    (tester) async {
      useDpr3(tester);
      // 0.05 logical px per frame keeps the atlas's size, like a stretch.
      await tester.pumpWidget(_scene(130));
      final renderer = _layer(tester).gpuGeometryRenderer!;
      final textures = <Object?>[renderer.debugMatteTexture];
      var allocated = 0;
      for (var frame = 1; frame <= 8; frame++) {
        await tester.pumpWidget(_scene(130 + frame * 0.05));
        textures.add(renderer.debugMatteTexture);
        if (frame == 2) allocated = _allocated;
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
      expect(_allocated, allocated, reason: 'two pages serve every frame');
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'pages their atlases leave half empty for 30 flushes shrink to fit',
    (tester) async {
      useDpr3(tester);
      await tester.pumpWidget(_scene(700));
      await tester.pumpWidget(_scene(700.05));
      final renderer = _layer(tester).gpuGeometryRenderer!;
      final (wideWidth, wideHeight) = renderer.debugMatteTextureSize!;
      for (var frame = 1; frame <= 40; frame++) {
        await tester.pumpWidget(_scene(60 + frame * 0.05));
      }
      final (width, height) = renderer.debugMatteTextureSize!;
      expect(width * height * 2, lessThanOrEqualTo(wideWidth * wideHeight));
      final allocatedBefore = _allocated;
      for (var frame = 41; frame <= 60; frame++) {
        await tester.pumpWidget(_scene(60 + frame * 0.05));
      }
      expect(_allocated - allocatedBefore, 0);
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'a resize sweep stops allocating once the pages have grown',
    (tester) async {
      useDpr3(tester);
      // 4 logical px per frame at DPR 3 changes the atlas's size every few
      // frames, in both directions.
      double width(int frame) {
        final phase = frame % 100;
        return 130 + 4.0 * (phase < 50 ? phase : 100 - phase);
      }

      await tester.pumpWidget(_scene(width(0)));
      final renderer = _layer(tester).gpuGeometryRenderer!;
      // Two warmup sweeps grow the pages to full capacity.
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
        measured,
        reason: 'every atlas goes to a page drawn into before',
      );
      final (textureWidth, _) = renderer.debugMatteTextureSize!;
      expect(textureWidth, lessThanOrEqualTo(AtlasLayout.maxSize));
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'an atlas below another in its page reads as one alone',
    (tester) async {
      useDpr3(tester);
      // The pages grow to hold both in the first frame.
      await tester.pumpWidget(_scene(131.45, above: 300));
      await tester.pumpWidget(_scene(131.5, above: 300.05));
      final below = _layer(tester);
      final place = below.debugGeometryPlace;
      expect(
        place.tableY,
        greaterThan(AtlasLayout.tableOrigin.$2),
        reason: 'the layers of a frame share a page',
      );
      final bufferSize = below.debugGeometryMatteBounds.size * 3;
      final width = bufferSize.width.round();
      final height = bufferSize.height.round();
      final sharedImage = below.debugGeometryImage!.clone();
      final sharedLooks = [
        for (final look in below.debugLookImages) look.clone(),
      ];
      expect(sharedLooks, isNotEmpty);
      addTearDown(sharedImage.dispose);
      for (final look in sharedLooks) {
        addTearDown(look.dispose);
      }

      await tester.pumpWidget(_scene(131.5, key: UniqueKey()));
      final alone = _layer(tester);
      final alonePlace = alone.debugGeometryPlace;
      expect(alonePlace.tableY, AtlasLayout.tableOrigin.$2);
      // Each is read as the final shader reads it: through its table.
      expect(
        await _geometry(tester, sharedImage, place, width, height),
        await _geometry(
          tester,
          alone.debugGeometryImage!,
          alonePlace,
          width,
          height,
        ),
      );
      expect(alone.debugLookImages, hasLength(sharedLooks.length));
      for (final (i, look) in alone.debugLookImages.indexed) {
        expect(
          await _looks(
            tester,
            sharedImage,
            place,
            sharedLooks[i],
            width,
            height,
          ),
          await _looks(
            tester,
            alone.debugGeometryImage!,
            alonePlace,
            look,
            width,
            height,
          ),
          reason: 'look $i',
        );
      }
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'the layers of a frame are drawn in one page',
    (tester) async {
      useDpr3(tester);
      await tester.pumpWidget(_scene(130, above: 200));
      final layers = _layers(tester);
      expect(layers, hasLength(2));
      for (var frame = 1; frame <= 6; frame++) {
        final pages = FlutterGpuGeometryRenderer.debugBatchedSubmitCount;
        await tester.pumpWidget(
          _scene(130 + frame * 0.05, above: 200 + frame * 0.05),
        );
        expect(
          identical(
            layers.first.gpuGeometryRenderer!.debugMatteTexture,
            layers.last.gpuGeometryRenderer!.debugMatteTexture,
          ),
          isTrue,
          reason: 'frame $frame',
        );
        if (!kDebugMode) continue;
        expect(
          FlutterGpuGeometryRenderer.debugBatchedSubmitCount - pages,
          1,
          reason: 'frame $frame',
        );
      }
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'a page is not drawn over while a layer that stays holds an atlas in it',
    (tester) async {
      useDpr3(tester);
      await tester.pumpWidget(_scene(130, above: 200));
      final layers = _layers(tester);
      expect(layers, hasLength(2));
      final held = layers.first.gpuGeometryRenderer!.debugMatteTexture;
      final image = layers.first.debugGeometryImage!;
      for (var frame = 1; frame <= 8; frame++) {
        await tester.pumpWidget(_scene(130 + frame * 0.05, above: 200));
        expect(
          identical(layers.first.gpuGeometryRenderer!.debugMatteTexture, held),
          isTrue,
          reason: 'the layer that stays keeps its page',
        );
        expect(
          identical(layers.last.gpuGeometryRenderer!.debugMatteTexture, held),
          isFalse,
          reason: 'frame $frame draws the layer that changes elsewhere',
        );
      }
      expect(image.debugDisposed, isFalse);
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'a recreated layer draws into the pages the last one left',
    (tester) async {
      useDpr3(tester);
      await tester.pumpWidget(_scene(130, key: const ValueKey('a')));
      await tester.pumpWidget(_scene(130.05, key: const ValueKey('a')));
      await tester.pumpWidget(const SizedBox());

      final allocatedBefore = _allocated;
      await tester.pumpWidget(_scene(130, key: const ValueKey('b')));
      expect(_layer(tester).debugGeometryImage, isNotNull);
      expect(_allocated - allocatedBefore, 0);
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'spare pages stay while the geometry is stable',
    (tester) async {
      useDpr3(tester);
      for (var frame = 0; frame < 4; frame++) {
        await tester.pumpWidget(_scene(130 + frame * 0.05));
      }
      for (var frame = 0; frame < 130; frame++) {
        await tester.pump(const Duration(milliseconds: 8));
        tester.binding.scheduleFrame();
      }
      final allocatedBefore = _allocated;
      final droppedBefore = _dropped;
      await tester.pumpWidget(_scene(130.5));
      expect(_allocated - allocatedBefore, 0);
      expect(_dropped - droppedBefore, 0);
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'renders within one frame never draw over the page of an earlier one',
    (tester) async {
      await tester.runAsync(() async {
        final renderer = await createGeometryRenderer();
        final atlases = <Object?>[];
        for (var index = 0; index < 3; index++) {
          renderTestRectangle(renderer, centerX: 16.0 + index * 3);
          atlases.add(renderer.debugMatteTexture);
        }
        for (var index = 1; index < atlases.length; index++) {
          for (var earlier = 0; earlier < index; earlier++) {
            expect(
              identical(atlases[index], atlases[earlier]),
              isFalse,
              reason: 'render $index must not rewrite an earlier atlas',
            );
          }
        }
      });
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'looks come and go with the atlas they lie beside',
    (tester) async {
      await tester.runAsync(() async {
        final renderer = await createGeometryRenderer();
        void render(ShapeLooks? looks, {int index = 0}) =>
            renderTestRectangle(renderer, centerX: 16.0 + index, looks: looks);

        render(_tint);
        final first = renderer.lookImages.single;
        render(null, index: 1);
        expect(renderer.lookImages, isEmpty);
        expect(first.debugDisposed, isTrue);
        render(ShapeLooks(List.filled(8, 1), tintOnly: false), index: 2);
        expect(renderer.lookImages, hasLength(3));
        expect(renderer.debugRenderCount, 3);
      });
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'an atlas holds its looks whatever the atlases before it held',
    (tester) async {
      // Impeller keeps a framebuffer on its first attachment's texture, so
      // a page that drew with other looks would drop these.
      final renderer = (await tester.runAsync(createGeometryRenderer))!;
      final full = ShapeLooks(const [1, 0, 0, 1, 1, 1, 0, 7], tintOnly: false);
      final reusedBefore = _reused;
      for (final (frame, looks) in [
        null,
        null,
        _tint,
        _tint,
        full,
        full,
        full,
        null,
        _tint,
        full,
      ].indexed) {
        renderTestRectangle(renderer, looks: looks);
        await tester.pumpWidget(SizedBox(width: frame.toDouble()));
        final atlas = (await tester.runAsync(
          () => AtlasTexels.read(renderer.atlasImage!, renderer.atlasPlace),
        ))!;
        final read = [
          for (final image in renderer.lookImages)
            atlas.lookAt(
              (await tester.runAsync(() => AtlasTexels.read(image)))!,
              16,
              32,
            ),
        ];
        expect(read, switch (looks) {
          null => isEmpty,
          ShapeLooks(tintOnly: true) => [(1.0, 0.0, 0.0, 1.0)],
          _ => [
            (1.0, 0.0, 0.0, 1.0),
            (1.0, 1.0, 0.0, 1.0),
            (0.0, 0.0, 0.0, 1.0),
          ],
        }, reason: 'frame $frame');
      }
      expect(_reused - reusedBefore, greaterThan(0));
    },
    skip: skipProperGlassTests,
  );

  testWidgets(
    'two renders per frame stop allocating after warmup',
    (tester) async {
      final renderer = (await tester.runAsync(createGeometryRenderer))!;
      // Registers the scene-frame counter before the first pump.
      renderTestRectangle(renderer);
      var frame = 0;
      Future<void> pumpTwoRenders() async {
        // Submit a frame before recording its two geometry updates.
        await tester.pumpWidget(const SizedBox());
        renderTestRectangle(renderer, looks: frame.isEven ? _tint : null);
        renderTestRectangle(renderer, centerX: 19, looks: _tint);
        frame++;
      }

      for (var i = 0; i < 6; i++) {
        await pumpTwoRenders();
      }
      final allocatedBefore = _allocated;
      final droppedBefore = _dropped;
      for (var i = 0; i < 8; i++) {
        await pumpTwoRenders();
      }
      expect(
        _allocated - allocatedBefore,
        0,
        reason: 'the spares cover two renders per submitted frame',
      );
      expect(_dropped - droppedBefore, 0);
      expect(renderer.lookImages, isNotEmpty);
    },
    skip: skipProperGlassTests,
  );
}

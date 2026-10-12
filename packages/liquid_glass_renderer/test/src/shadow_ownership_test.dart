import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/glass_shadow.dart';
import 'package:liquid_glass_renderer/src/internal/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_renderer/src/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';

import 'shared.dart';
import 'submitted_scene_binding.dart';

late SubmittedSceneBinding _binding;

const _shadow = BoxShadow(
  color: Color(0x99000000),
  offset: Offset(0, 8),
  blurRadius: 8,
);

const _sideShadow = BoxShadow(
  color: Color(0x99000000),
  offset: Offset(8, 0),
  blurRadius: 8,
);

enum _Reveal {
  wholeLayer,
  shape,
  reparent,
}

Widget _scene({
  required bool grouped,
  List<BoxShadow> shadows = const [_shadow],
  bool fake = false,
  bool layerVisible = true,
  bool shapeVisible = true,
  bool reparent = false,
  Key? shapeKey,
}) {
  final buildGlass = grouped ? LiquidGlass.grouped : LiquidGlass.new;
  final shape = buildGlass(
    key: shapeKey,
    shape: const LiquidRoundedRectangle(borderRadius: 12),
    shadows: shadows,
    child: const SizedBox(width: 64, height: 64),
  );
  final shapeWithVisibility = Offstage(
    offstage: !shapeVisible,
    child: shape,
  );
  final glass = KeyedSubtree(
    key: ValueKey(reparent),
    child: Center(child: shapeWithVisibility),
  );
  final groupedGlass = grouped ? LiquidGlassBlendGroup(child: glass) : glass;
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    home: ColoredBox(
      color: Colors.white,
      child: SizedBox.expand(
        child: Offstage(
          offstage: !layerVisible,
          child: LiquidGlassLayer(
            fake: fake,
            settings: settingsWithoutLighting,
            child: groupedGlass,
          ),
        ),
      ),
    ),
  );
}

Future<Uint8List> _capture(WidgetTester tester, [Widget? scene]) async {
  _binding.captureNextScene = true;
  if (scene != null) {
    await tester.pumpWidget(scene);
  } else {
    _binding.scheduleFrame();
    await tester.pump();
  }
  final image = await tester.runAsync(() => _binding.captured!);
  final data = await tester.runAsync(() => image!.toByteData());
  image!.dispose();
  return Uint8List.fromList(data!.buffer.asUint8List());
}

Future<void> _warm(WidgetTester tester, Widget scene) async {
  tester.view
    ..physicalSize = const Size(160, 160)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(scene);
  for (var frame = 0; frame < 4; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

RenderLiquidGlassLayer _layer(WidgetTester tester) =>
    tester.allRenderObjects.whereType<RenderLiquidGlassLayer>().last;

void main() {
  _binding = SubmittedSceneBinding()
    ..captureWidth = 160
    ..captureHeight = 160;
  for (final grouped in [false, true]) {
    for (final reveal in _Reveal.values) {
      testWidgets(
        'first ${reveal.name} reveal preserves '
        '${grouped ? 'grouped' : 'standalone'} shadow',
        (tester) async {
          final shapeKey = reveal == _Reveal.reparent
              ? GlobalKey(debugLabel: 'shadow-shape')
              : null;
          await _warm(
            tester,
            _scene(grouped: grouped, shapeKey: shapeKey),
          );
          expect(find.byType(GlassShadow), findsNothing);
          final glass = tester.allRenderObjects
              .whereType<RenderLiquidGlass>()
              .where((renderObject) => renderObject.layerShadows.isNotEmpty);
          expect(glass.last.layerShadows, hasLength(1));
          expect(glass.last.layerShadows.single, _shadow);
          final visible = await _capture(tester);
          late Uint8List firstReveal;

          switch (reveal) {
            case _Reveal.wholeLayer:
              await tester.pumpWidget(
                _scene(grouped: grouped, layerVisible: false),
              );
              firstReveal = await _capture(
                tester,
                _scene(grouped: grouped),
              );
            case _Reveal.shape:
              await tester.pumpWidget(
                _scene(grouped: grouped, shapeVisible: false),
              );
              firstReveal = await _capture(
                tester,
                _scene(grouped: grouped),
              );
            case _Reveal.reparent:
              firstReveal = await _capture(
                tester,
                _scene(
                  grouped: grouped,
                  reparent: true,
                  shapeKey: shapeKey,
                ),
              );
          }
          expect(firstReveal, orderedEquals(visible));
        },
        skip: skipProperGlassTests,
      );
    }

    testWidgets(
      'shadow-only updates reuse ${grouped ? 'grouped' : 'standalone'} matte',
      (tester) async {
        await _warm(tester, _scene(grouped: grouped, shadows: const []));
        final layer = _layer(tester);
        final renderer = layer.gpuGeometryRenderer!;
        final initialCount = renderer.debugRenderCount;
        final initialImage = layer.debugGeometryImage;
        final initialBytes = await _capture(tester);
        var previousBytes = initialBytes;
        const shadowSpecs = <List<BoxShadow>>[
          [_shadow],
          [_sideShadow],
          [],
        ];
        for (final specs in shadowSpecs) {
          final bytes = await _capture(
            tester,
            _scene(grouped: grouped, shadows: specs),
          );
          expect(bytes, isNot(equals(previousBytes)));
          expect(renderer.debugRenderCount, initialCount);
          expect(identical(layer.debugGeometryImage, initialImage), isTrue);
          final geometry = tester.allRenderObjects
              .whereType<RenderLiquidGlassGeometry>()
              .lastWhere((node) => node.geometry != null)
              .geometry!;
          expect(geometry.shapes.single.shadows, specs);
          previousBytes = bytes;
        }
        expect(previousBytes, orderedEquals(initialBytes));
      },
      skip: skipProperGlassTests,
    );
  }

  for (final offset in [Offset.zero, const Offset(8, 0)]) {
    testWidgets(
      'singleton shadow with offset $offset has no interior leakage',
      (tester) async {
        await _warm(
          tester,
          _scene(
            grouped: false,
            fake: true,
            shadows: [
              BoxShadow(
                color: const Color(0x99000000),
                offset: offset,
                blurRadius: 8,
              ),
            ],
          ),
        );
        final fakeBytes = await _capture(tester);
        final bytes = await _capture(
          tester,
          _scene(
            grouped: false,
            shadows: [
              BoxShadow(
                color: const Color(0x99000000),
                offset: offset,
                blurRadius: 8,
              ),
            ],
          ),
        );
        const center = (80 * 160 + 80) * 4;
        final actualCenter = bytes.sublist(center, center + 4);
        final fakeCenter = fakeBytes.sublist(center, center + 4);
        for (var channel = 0; channel < 4; channel++) {
          expect(actualCenter[channel], closeTo(fakeCenter[channel], 2));
        }
        final exteriorX = offset == Offset.zero ? 80 : 120;
        final exteriorY = offset == Offset.zero ? 42 : 80;
        final exterior = (exteriorY * 160 + exteriorX) * 4;
        final actualExterior = bytes.sublist(exterior, exterior + 4);
        final fakeExterior = fakeBytes.sublist(exterior, exterior + 4);
        for (var channel = 0; channel < 4; channel++) {
          expect(actualExterior[channel], closeTo(fakeExterior[channel], 2));
        }
      },
      skip: skipProperGlassTests,
    );
  }
}

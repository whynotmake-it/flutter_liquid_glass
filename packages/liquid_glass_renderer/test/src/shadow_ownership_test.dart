import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/glass_shadow.dart';
import 'package:liquid_glass_renderer/src/internal/render_liquid_glass_geometry.dart';
import 'package:liquid_glass_renderer/src/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';

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

const _negativeSpreadShadow = BoxShadow(
  color: Color(0xFF000000),
  blurRadius: 16,
  spreadRadius: -8,
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

Widget _twoShapeScene({
  required bool fake,
  required List<BoxShadow> shadows,
  required bool curvedClip,
  GlobalKey? clipKey,
}) {
  final first = LiquidGlass(
    shape: const LiquidRoundedRectangle(borderRadius: 12),
    shadows: shadows,
    child: const SizedBox(width: 64, height: 64),
  );
  final clipped = curvedClip
      ? Transform.rotate(
          angle: .35,
          child: ClipRRect(
            key: clipKey,
            borderRadius: BorderRadius.circular(20),
            child: first,
          ),
        )
      : ClipRect(key: clipKey, child: first);
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    home: ColoredBox(
      color: Colors.white,
      child: SizedBox.expand(
        child: LiquidGlassLayer(
          fake: fake,
          settings: settingsWithoutLighting,
          child: Stack(
            children: [
              Positioned(left: 32, top: 48, child: clipped),
              Positioned(
                left: 160,
                top: 48,
                child: LiquidGlass(
                  shape: const LiquidRoundedRectangle(borderRadius: 12),
                  shadows: shadows,
                  child: const SizedBox(width: 64, height: 64),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _retainedMotionScene({
  required bool fake,
  required ValueListenable<Offset> offset,
}) {
  Widget shape() => const LiquidGlass(
    shape: LiquidRoundedRectangle(borderRadius: 12),
    shadows: [_shadow],
    child: SizedBox(width: 64, height: 64),
  );
  Widget movingGlass() => ValueListenableBuilder<Offset>(
    valueListenable: offset,
    builder: (_, value, child) => Transform.translate(
      offset: value,
      child: child,
    ),
    child: shape(),
  );
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    home: ColoredBox(
      color: Colors.white,
      child: SizedBox.expand(
        child: LiquidGlassLayer(
          fake: fake,
          settings: settingsWithoutLighting,
          child: Stack(
            children: [
              Positioned(
                left: 32,
                top: 48,
                child: ClipRect(
                  child: SizedBox(
                    width: 80,
                    height: 80,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: RepaintBoundary(child: movingGlass()),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 160,
                top: 48,
                child: RepaintBoundary(child: movingGlass()),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Uint8List _pixel(Uint8List image, int x, int y, int width) {
  final index = (y * width + x) * 4;
  return image.sublist(index, index + 4);
}

void _expectPixelEqual(
  Uint8List actual,
  Uint8List expected,
  int x,
  int y,
  int width,
) {
  expect(
    _pixel(actual, x, y, width),
    orderedEquals(_pixel(expected, x, y, width)),
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

Future<void> _warm(
  WidgetTester tester,
  Widget scene, {
  Size viewport = const Size(160, 160),
}) async {
  tester.view
    ..physicalSize = viewport
    ..devicePixelRatio = 1;
  _binding
    ..captureWidth = viewport.width.toInt()
    ..captureHeight = viewport.height.toInt();
  addTearDown(tester.view.reset);
  await _binding.setSurfaceSize(viewport);
  addTearDown(() => _binding.setSurfaceSize(null));
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

  for (final fake in [true, false]) {
    testWidgets(
      'negative spread zero-offset shadow stays outside the glass '
      '(fake=$fake)',
      (tester) async {
        await _warm(
          tester,
          _scene(
            grouped: false,
            fake: fake,
            shadows: const [_negativeSpreadShadow],
          ),
        );
        final shadow = await _capture(tester);
        final groupedShadow = await _capture(
          tester,
          _scene(
            grouped: true,
            fake: fake,
            shadows: const [_negativeSpreadShadow],
          ),
        );
        final noShadow = await _capture(
          tester,
          _scene(
            grouped: false,
            fake: fake,
            shadows: const [],
          ),
        );
        expect(shadow, isNot(equals(noShadow)));
        for (var y = 72; y < 88; y++) {
          for (var x = 50; x < 56; x++) {
            final index = (y * 160 + x) * 4;
            expect(
              shadow.sublist(index, index + 4),
              orderedEquals(groupedShadow.sublist(index, index + 4)),
            );
          }
        }
      },
      skip: skipProperGlassTests,
    );

    for (final curvedClip in [false, true]) {
      testWidgets(
        'individual ${curvedClip ? 'curved' : 'rect'} shadow clip '
        '(fake=$fake)',
        (tester) async {
          final clipKey = curvedClip ? GlobalKey() : null;
          await _warm(
            tester,
            _twoShapeScene(
              fake: fake,
              shadows: const [_shadow],
              curvedClip: curvedClip,
              clipKey: clipKey,
            ),
            viewport: const Size(240, 160),
          );
          final shadow = await _capture(tester);
          final noShadow = await _capture(
            tester,
            _twoShapeScene(
              fake: fake,
              shadows: const [],
              curvedClip: curvedClip,
              clipKey: clipKey,
            ),
          );
          _expectPixelEqual(shadow, noShadow, 104, 80, 240);
          expect(
            _pixel(shadow, 228, 80, 240),
            isNot(equals(_pixel(noShadow, 228, 80, 240))),
          );
          if (curvedClip) {
            final clip =
                clipKey!.currentContext!.findRenderObject()! as RenderBox;
            final point = MatrixUtils.transformPoint(
              clip.getTransformTo(null),
              const Offset(2, 2),
            );
            _expectPixelEqual(
              shadow,
              noShadow,
              point.dx.round(),
              point.dy.round(),
              240,
            );
          }
        },
        skip: skipProperGlassTests,
      );
    }

    testWidgets(
      'individual shadow clips refresh during retained motion (fake=$fake)',
      (tester) async {
        final offset = ValueNotifier(Offset.zero);
        addTearDown(offset.dispose);
        await _warm(
          tester,
          _retainedMotionScene(fake: fake, offset: offset),
          viewport: const Size(240, 160),
        );
        final initial = await _capture(tester);
        final owner = tester.allRenderObjects
            .whereType<LiquidGlassRenderObject>()
            .last;
        final layer = owner is RenderLiquidGlassLayer ? owner : null;
        final paintCount = layer?.debugPaintCount;
        final renderer = layer?.gpuGeometryRenderer;
        final renderCount = renderer?.debugRenderCount;

        offset.value = const Offset(16, 0);
        final moved = await _capture(tester);
        _expectPixelEqual(moved, initial, 116, 108, 240);
        expect(
          _pixel(moved, 228, 80, 240),
          isNot(equals(_pixel(initial, 228, 80, 240))),
        );
        if (!fake) {
          expect(layer!.debugPaintCount, paintCount);
          expect(renderer!.debugRenderCount, renderCount);
        }
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

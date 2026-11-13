import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/rendering.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_composition_probe.dart';
import 'package:liquid_glass_renderer/src/rendering/read.dart';
import 'package:material_ui/material_ui.dart';

import 'shared.dart';

const _key = ValueKey('screen');

final _filter = ui.ImageFilter.compose(
  outer: const ui.ColorFilter.matrix(<double>[
    1.2, 0, 0, 0, 8, //
    0, 1.2, 0, 0, 8, //
    0, 0, 1.2, 0, 8, //
    0, 0, 0, 0.7, 0,
  ]),
  inner: ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3),
);

class _Band extends LeafRenderObjectWidget {
  const _Band();

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderBand();
}

class _RenderBand extends RenderBox with LiquidGlassBackdropFilterHost {
  final layerHandle = LayerHandle<LiquidGlassBackdropFilterLayer>();

  @override
  Layer? get composedLayer => layerHandle.layer;

  @override
  bool get sizedByParent => true;

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  bool get isRepaintBoundary => true;

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      constraints.biggest;

  @override
  void paint(PaintingContext context, Offset offset) {
    final layer = (layerHandle.layer ??= LiquidGlassBackdropFilterLayer(
      filter: _filter,
      clip: offset & size,
      reach: 12,
      devicePixelRatio: 1,
    ))..clip = offset & size;
    context.pushLayer(layer, (context, offset) {
      final paint = Paint()..color = const Color(0x33FFFFFF);
      context.canvas.drawRect(offset & size, paint);
    }, offset);
  }

  @override
  void dispose() {
    layerHandle.layer = null;
    super.dispose();
  }
}

Widget _scene({
  double shift = 0,
  bool texture = false,
  bool band = true,
  bool glass = false,
  double glassTop = 80,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: RepaintBoundary(
    key: _key,
    child: Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: const [
                  Color(0xFF1E3A8A),
                  Color(0xFFF59E0B),
                  Color(0xFF10B981),
                ],
                begin: Alignment(-1 + shift, -1),
                end: Alignment.bottomRight,
                tileMode: TileMode.mirror,
              ),
            ),
            child: const Center(
              child: Text(
                'Page under the band',
                style: TextStyle(color: Color(0xFFFFFFFF), fontSize: 22),
              ),
            ),
          ),
        ),
        if (texture)
          const Positioned(
            left: 40,
            top: 20,
            width: 20,
            height: 20,
            child: Texture(textureId: 1),
          ),
        if (band)
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 60,
            child: _Band(),
          ),
        if (glass)
          Positioned.fromRect(
            rect: Rect.fromLTWH(190, glassTop, 56, 40),
            child: LiquidGlassLayer(
              settings: LiquidGlassSettings.ios27RegularLight().copyWith(
                frost: 0,
              ),
              child: const LiquidGlass(
                shape: LiquidRoundedSuperellipse(borderRadius: 28),
                child: SizedBox.expand(),
              ),
            ),
          ),
      ],
    ),
  ),
);

LiquidGlassBackdropFilterLayer _band(WidgetTester tester) =>
    tester.layers.whereType<LiquidGlassBackdropFilterLayer>().single;

Future<Uint8List> _pixels(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_key),
  );
  final image = (await tester.runAsync(boundary.toImage))!;
  final bytes = (await tester.runAsync(image.toByteData))!;
  image.dispose();
  return bytes.buffer.asUint8List();
}

int _difference(Uint8List a, Uint8List b) {
  var largest = 0;
  for (var i = 0; i < a.length; i++) {
    final d = (a[i] - b[i]).abs();
    if (d > largest) largest = d;
  }
  return largest;
}

void main() {
  tearDown(() {
    debugGlassCopies = null;
  });

  testWidgets('the band over a copy drawn in the very frame what lies under '
      'it changed draws what reading the backdrop draws', (tester) async {
    tester.view.physicalSize = const Size(260, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // flutter_tester renders only a process's first backdrop filter
    // reliably, so the reference reads the backdrop first.
    debugGlassCopies = false;
    await tester.pumpWidget(_scene());
    final reading = await _pixels(tester);
    expect(_band(tester).serves, isFalse);

    debugGlassCopies = true;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_scene(shift: 0.3));
    expect(_band(tester).serves, isTrue);
    await tester.pumpWidget(_scene());
    expect(_band(tester).serves, isTrue);
    expect(tester.layers.whereType<BackdropFilterLayer>(), isEmpty);
    // The copy reads as far as the blur's reach, the backdrop reads the pass.
    expect(_difference(reading, await _pixels(tester)), lessThanOrEqualTo(2));

    await tester.pumpWidget(_scene(band: false));
    expect(_difference(reading, await _pixels(tester)), greaterThan(40));
  }, skip: skipProperGlassTests);

  testWidgets('the band keeps its copy while what lies under it holds '
      'still', (tester) async {
    debugGlassCopies = true;
    tester.view.physicalSize = const Size(260, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final watch = PlanWatch();
    await tester.pumpWidget(_scene());
    final changes = watch.changes(_band(tester));
    for (var i = 0; i < 5; i++) {
      tester.binding.scheduleFrame();
      await tester.pump();
    }
    expect(_band(tester).serves, isTrue);
    expect(watch.changes(_band(tester)), changes);
  }, skip: skipProperGlassTests);

  testWidgets('the band reads its backdrop over a layer the copy cannot '
      'draw', (tester) async {
    debugGlassCopies = true;
    tester.view.physicalSize = const Size(260, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_scene(texture: true));
    expect(_band(tester).serves, isFalse);
  }, skip: skipProperGlassTests);

  testWidgets('the copy under the band is drawn in one image with the '
      'copies of the glass in the frame', (tester) async {
    debugGlassCopies = true;
    tester.view.physicalSize = const Size(260, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    RenderLiquidGlassLayer glass() => tester.allRenderObjects
        .whereType<RenderLiquidGlassLayer>()
        .toSet()
        .single;

    await tester.pumpWidget(_scene(glass: true, glassTop: 140, shift: 0.3));
    final drawn = GlassCopies.debugImagesDrawn;
    await tester.pumpWidget(_scene(glass: true, glassTop: 140));
    expect(_band(tester).serves, isTrue);
    expect(glass().debugDrewOverCopy, isTrue);
    expect(GlassCopies.debugImagesDrawn, drawn + 1);
  }, skip: skipProperGlassTests);

  testWidgets('glass over the band copies in one more image, drawing the band '
      'in, and both hold once nothing moves', (
    tester,
  ) async {
    copyIntoImages();
    debugGlassCopies = true;
    tester.view.physicalSize = const Size(260, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    RenderLiquidGlassLayer glass() => tester.allRenderObjects
        .whereType<RenderLiquidGlassLayer>()
        .toSet()
        .single;

    await tester.pumpWidget(_scene(glass: true, glassTop: 30, shift: 0.3));
    var drawn = GlassCopies.debugImagesDrawn;
    await tester.pumpWidget(_scene(glass: true, glassTop: 30));
    expect(_band(tester).serves, isTrue);
    expect(glass().debugDrewOverCopy, isTrue);
    expect(GlassCopies.debugImagesDrawn, drawn + 2);
    drawn = GlassCopies.debugImagesDrawn;
    glass().markNeedsPaint();
    await tester.pump();
    expect(glass().debugDrewOverCopy, isTrue);
    expect(GlassCopies.debugImagesDrawn, drawn);
  }, skip: skipProperGlassTests);

  testWidgets('glass near the band draws from its own copy while the band '
      'draws from its copy, and reads its backdrop while the band reads '
      'its', (tester) async {
    debugGlassCopies = true;
    tester.view.physicalSize = const Size(260, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    RenderLiquidGlassLayer glass() => tester.allRenderObjects
        .whereType<RenderLiquidGlassLayer>()
        .toSet()
        .single;

    await tester.pumpWidget(_scene(glass: true));
    expect(_band(tester).serves, isTrue);
    expect(glass().debugDrewOverCopy, isTrue);
    expect(
      tester.layers.whereType<BackdropFilterLayer>().where(
        (layer) => layer is! OpacitySeedLayer || layer.seeded,
      ),
      isEmpty,
    );

    await tester.pumpWidget(_scene(glass: true, texture: true));
    expect(_band(tester).serves, isFalse);
    expect(glass().debugDrewOverCopy, isFalse);
  }, skip: skipProperGlassTests);
}

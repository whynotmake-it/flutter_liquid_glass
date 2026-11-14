import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/final_shader_variant.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/shader_programs.dart';
import 'package:liquid_glass_renderer/src/rendering/shading.dart';
import 'package:material_ui/material_ui.dart';

import 'shared.dart';

const _view = Size(300, 200);
const _gray = Color(0xFF7A8290);

Widget _scene() => Directionality(
  textDirection: TextDirection.ltr,
  child: SizedBox.fromSize(
    size: _view,
    child: ColoredBox(
      color: _gray,
      child: LiquidGlassLayer(
        settings: LiquidGlassSettings.ios27RegularLight(),
        backdrop: const LiquidGlassBackdrop.solid(_gray),
        child: const Stack(
          children: [
            Positioned(
              left: 40,
              top: 50,
              width: 200,
              height: 100,
              child: LiquidGlass(
                shape: LiquidRoundedSuperellipse(borderRadius: 40),
                child: SizedBox.expand(),
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);

// Stripes drawn through [filter], as a layer the filter takes as its input.
Future<Uint8List> _through(WidgetTester tester, ui.ImageFilter filter) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final layer = Paint()..imageFilter = filter;
  canvas
    ..saveLayer(Offset.zero & _view, layer)
    ..drawColor(Colors.white, BlendMode.src);
  final stripe = Paint()..color = Colors.black;
  for (var x = 0.0; x < _view.width; x += 16) {
    canvas.drawRect(Rect.fromLTWH(x, 0, 8, _view.height), stripe);
  }
  canvas.restore();
  final picture = recorder.endRecording();
  final image = (await tester.runAsync(
    () => picture.toImage(_view.width.toInt(), _view.height.toInt()),
  ))!;
  picture.dispose();
  final bytes = (await tester.runAsync(image.toByteData))!;
  image.dispose();
  return bytes.buffer.asUint8List();
}

GlassFace _face(Color tint) {
  const appearance = LiquidGlassAppearance.ios27RegularLight();
  return GlassFace.of(
    settings: LiquidGlassSettings.ios27RegularLight(),
    appearance: appearance.copyWith(tint: tint),
    colorModels: [appearance.colorModel.parameters!],
    devicePixelRatio: 1,
    blurs: true,
  );
}

void main() {
  testWidgets('every variant names the uniforms a draw writes', (
    tester,
  ) async {
    await tester.runAsync(
      () => GlassShaderPrograms.precacheShaders(FinalShaderVariant.assetKeys),
    );
    for (final variant in FinalShaderVariant.all) {
      final shader = GlassShaderPrograms.cached(
        variant.assetKey,
      )!.fragmentShader();
      expect(
        () => FinalLayout(shader, variant),
        returnsNormally,
        reason: variant.name,
      );
      shader.dispose();
    }
  }, skip: skipProperGlassTests);

  testWidgets('a filter draws the draw it was made with, whatever the shader '
      'is given after', (tester) async {
    tester.view.physicalSize = _view;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_scene());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();
    final layer = tester.allRenderObjects
        .whereType<RenderLiquidGlassLayer>()
        .toSet()
        .single;
    final live = layer.debugLiveDraw;
    // The layer lies at the origin, at one device pixel a logical one: the
    // stripes' pixels are the matte's.
    GlassDraw tinted(Color tint) => GlassDraw(
      variant: live.variant,
      face: _face(tint),
      glow: live.glow,
      matte: live.matte,
      mapping: const MatteMapping((1, 0, 0, 1, 0, 0), Rect.largest),
    );
    final clear = tinted(const Color(0x00FFFFFF));
    final red = tinted(const Color(0xCCFF0000));
    final shading = GlassShading(layer.finalShaders);

    final first = shading.filter(clear);
    shading.filter(red);
    final shown = await _through(tester, first);
    final again = await _through(tester, shading.filter(clear));
    final other = await _through(tester, shading.filter(red));

    expect(listEquals(shown, again), isTrue);
    expect(listEquals(shown, other), isFalse);
  }, skip: skipProperGlassTests);
}

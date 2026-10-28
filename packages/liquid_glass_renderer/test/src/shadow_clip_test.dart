import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';

import 'shared.dart';

const _key = ValueKey('shadows');
const _view = Size(300, 160);
const _gray = Color(0xFF808080);
const _shadow = BoxShadow(
  blurRadius: 6,
  spreadRadius: 4,
);

Widget _scene({required List<Rect> glass, required bool shadows}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: _key,
          child: SizedBox.fromSize(
            size: _view,
            child: ColoredBox(
              color: _gray,
              child: LiquidGlassLayer(
                settings: LiquidGlassSettings.ios27RegularLight(),
                // Over a solid color the glass is painted without a backdrop
                // filter, so flutter_tester draws every render in this
                // process, not only the first.
                backdrop: const LiquidGlassBackdrop.solid(_gray),
                child: Stack(
                  children: [
                    for (final rect in glass)
                      Positioned.fromRect(
                        rect: rect,
                        child: LiquidGlass(
                          shape: const LiquidRoundedSuperellipse(
                            borderRadius: 20,
                          ),
                          shadows: shadows ? const [_shadow] : const [],
                          child: const SizedBox.expand(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

Future<Uint8List> _render(
  WidgetTester tester, {
  required List<Rect> glass,
  required bool shadows,
}) async {
  tester.view
    ..physicalSize = _view
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_scene(glass: glass, shadows: shadows));
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_key),
  );
  final image = (await tester.runAsync(boundary.toImage))!;
  final bytes = (await tester.runAsync(image.toByteData))!;
  image.dispose();
  return bytes.buffer.asUint8List();
}

int _red(Uint8List rgba, Offset p) =>
    rgba[(p.dy.toInt() * _view.width.toInt() + p.dx.toInt()) * 4];

void main() {
  for (final (name, glass) in [
    (
      'apart',
      const [Rect.fromLTWH(20, 40, 100, 80), Rect.fromLTWH(170, 40, 100, 80)],
    ),
    (
      'overlapping',
      const [Rect.fromLTWH(40, 40, 120, 80), Rect.fromLTWH(130, 40, 120, 80)],
    ),
  ]) {
    testWidgets('shadows stay outside every silhouette ($name)', (
      tester,
    ) async {
      final plain = await _render(tester, glass: glass, shadows: false);
      final shadowed = await _render(tester, glass: glass, shadows: true);
      for (final rect in glass) {
        // Inside a silhouette the glass is not darkened; in the overlapping
        // case the right glass's inset probe lies in the overlap of both.
        for (final p in [rect.center, rect.centerLeft + const Offset(12, 0)]) {
          expect(_red(shadowed, p), _red(plain, p), reason: '$name $p');
        }
        // Just outside, inside the shadow's spread, it darkens the backdrop.
        final below = rect.bottomCenter + const Offset(0, 2);
        expect(
          _red(shadowed, below),
          lessThan(_red(plain, below) - 10),
          reason: '$name $below',
        );
      }
    }, skip: skipProperGlassTests);
  }

  testWidgets('the shadow under a fading glass fades with it', (tester) async {
    tester.view
      ..physicalSize = _view
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // The shadow's alpha under the glass's center: the shadow draws at the
    // glass's visibility, and the glass cuts it by that visibility again.
    Future<int> under(double visibility) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: LiquidGlassLayer(
            settings: LiquidGlassSettings.ios27RegularLight(),
            backdrop: const LiquidGlassBackdrop.solid(_gray),
            child: Stack(
              children: [
                Positioned(
                  left: 100,
                  top: 40,
                  width: 100,
                  height: 80,
                  child: LiquidGlass(
                    shape: const LiquidRoundedSuperellipse(borderRadius: 20),
                    appearance: const LiquidGlassAppearance.ios27RegularLight()
                        .copyWith(visibility: visibility),
                    shadows: const [
                      BoxShadow(blurRadius: 4, offset: Offset(0, 8)),
                    ],
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      final layer = tester.allRenderObjects
          .whereType<LiquidGlassRenderObject>()
          .first;
      final recorder = ui.PictureRecorder();
      // ignore: invalid_use_of_protected_member
      layer.drawGlassShadows(Canvas(recorder), Offset.zero);
      final picture = recorder.endRecording();
      final image = (await tester.runAsync(() => picture.toImage(300, 160)))!;
      final bytes = (await tester.runAsync(image.toByteData))!;
      image.dispose();
      picture.dispose();
      return bytes.getUint8((80 * 300 + 150) * 4 + 3);
    }

    // A half visible glass keeps a quarter of the shadow: half drawn, half
    // of that cut.
    expect(await under(0.5), inInclusiveRange(54, 74));
    expect(await under(1), 0);
  }, skip: skipProperGlassTests);
}

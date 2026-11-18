import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_shadow.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';

import 'shared.dart';

const _view = Size(300, 160);
const _gray = Color(0xFF808080);
const _body = Rect.fromLTWH(100, 40, 100, 80);
const _other = Rect.fromLTWH(230, 40, 60, 80);
const _shape = LiquidRoundedSuperellipse(radius: 20);
const _center = Offset(150, 80);
const _below = Offset(150, 123);

final _edge = Path()
  ..addRRect(RRect.fromRectAndRadius(_body, const Radius.circular(20)));

Future<Uint8List> _pixels(
  WidgetTester tester,
  void Function(Canvas canvas) draw,
) async {
  final recorder = ui.PictureRecorder();
  // Tests draw BoxShadow without its blur, which outer blur needs to leave
  // the body out.
  debugDisableShadows = false;
  try {
    draw(Canvas(recorder));
  } finally {
    debugDisableShadows = true;
  }
  final picture = recorder.endRecording();
  final image = (await tester.runAsync(
    () => picture.toImage(_view.width.toInt(), _view.height.toInt()),
  ))!;
  final bytes = (await tester.runAsync(image.toByteData))!;
  image.dispose();
  picture.dispose();
  return bytes.buffer.asUint8List();
}

int _alpha(Uint8List rgba, Offset p) =>
    rgba[(p.dy.toInt() * _view.width.toInt() + p.dx.toInt()) * 4 + 3];

Future<Uint8List> _layerShadows(
  WidgetTester tester, {
  required List<Rect> glass,
  required LiquidShape shape,
  required LiquidGlassShadow shadow,
  required double visibility,
  LiquidGlassField? field,
}) async {
  tester.view
    ..physicalSize = _view
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: LiquidGlassLayer(
        settings: const LiquidGlassSettings.ios27Regular(
          brightness: Brightness.light,
        ),
        backdrop: const LiquidGlassBackdrop.solid(_gray),
        field: field,
        child: Stack(
          children: [
            for (final rect in glass)
              Positioned.fromRect(
                rect: rect,
                child: LiquidGlass(
                  shape: shape,
                  appearance: const LiquidGlassAppearance.ios27Regular(
                    brightness: Brightness.light,
                  ).copyWith(visibility: visibility),
                  shadows: [shadow],
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
  return _pixels(
    tester,
    (canvas) => layer.drawGlassShadows(canvas, Offset.zero),
  );
}

void main() {
  group('the cut of glass shadows', () {
    const plain = [BoxShadow(blurRadius: 6)];
    const offset = [BoxShadow(blurRadius: 6, offset: Offset(0, 8))];
    const spread = [BoxShadow(blurRadius: 6, spreadRadius: 2)];

    test('a lone whole body blurs a shadow without offset or spread '
        'outside itself alone', () {
      expect(
        GlassShadowCut.of(lone: true, shadows: plain, fading: false),
        GlassShadowCut.outer,
      );
      expect(
        GlassShadowCut.of(lone: true, shadows: offset, fading: false),
        GlassShadowCut.clip,
      );
      expect(
        GlassShadowCut.of(lone: true, shadows: spread, fading: false),
        GlassShadowCut.clip,
      );
      expect(
        GlassShadowCut.of(lone: false, shadows: plain, fading: false),
        GlassShadowCut.clip,
      );
    });

    test('a fading body cuts by its visibility, even under glass', () {
      for (final under in [false, true]) {
        expect(
          GlassShadowCut.of(
            lone: true,
            shadows: plain,
            fading: true,
            under: under,
          ),
          GlassShadowCut.fraction,
        );
      }
    });

    test('glass that covers its shadows leaves them whole', () {
      expect(
        GlassShadowCut.of(
          lone: false,
          shadows: offset,
          fading: false,
          under: true,
        ),
        GlassShadowCut.none,
      );
    });
  });

  for (final dy in [0.0, 8.0]) {
    for (final spread in [-2.0, 0.0, 2.0]) {
      for (final visibility in [1.0, 0.5]) {
        final shadow = LiquidGlassShadow(
          blurRadius: 12,
          offset: Offset(0, dy),
          spreadRadius: spread,
        );
        final what = 'offset $dy, spread $spread, visibility $visibility';

        Future<(int, int)> standalone(
          WidgetTester tester,
          LiquidGlassSilhouette silhouette,
        ) async {
          final pixels = await _pixels(
            tester,
            (canvas) => silhouette.paintShadows(canvas, [
              shadow,
            ], visibility: visibility),
          );
          return (_alpha(pixels, _center), _alpha(pixels, _below));
        }

        void expectLaw((int, int) probes) {
          final (center, below) = probes;
          if (visibility == 1) {
            expect(center, 0, reason: 'cut whole: $what');
          } else {
            expect(center, greaterThan(0), reason: 'shows through: $what');
          }
          expect(below, greaterThan(0), reason: 'cast: $what');
        }

        testWidgets('a lone shape and a lone path cast alike ($what)', (
          tester,
        ) async {
          expectLaw(
            await standalone(
              tester,
              const LiquidGlassSilhouette.shape(_shape, _body),
            ),
          );
          expectLaw(
            await standalone(tester, LiquidGlassSilhouette.path(_edge)),
          );
        });

        for (final (kind, glass, field) in [
          ('one shape', [_body], null),
          ('two shapes', [_body, _other], null),
          ('a field', [_body], LiquidGlassField.fromPath(_edge, step: 4)),
        ]) {
          testWidgets('a layer of $kind casts as a lone body does ($what)', (
            tester,
          ) async {
            final pixels = await _layerShadows(
              tester,
              glass: glass,
              shape: _shape,
              shadow: shadow,
              visibility: visibility,
              field: field,
            );
            final layer = (_alpha(pixels, _center), _alpha(pixels, _below));
            expectLaw(layer);
            final (center, below) = await standalone(
              tester,
              field == null
                  ? const LiquidGlassSilhouette.shape(_shape, _body)
                  : LiquidGlassSilhouette.path(_edge),
            );
            expect(layer.$1, closeTo(center, 2), reason: what);
            expect(layer.$2, closeTo(below, 2), reason: what);
          }, skip: skipProperGlassTests);
        }
      }
    }
  }

  testWidgets("a layer with a field casts by the field's edge, not by its "
      'shapes', (tester) async {
    const squareCornerOnly = Offset(102, 42);
    const shadow = LiquidGlassShadow(blurRadius: 6);
    final byEdge = await _layerShadows(
      tester,
      glass: [_body],
      shape: const LiquidRoundedRectangle(radius: 0),
      shadow: shadow,
      visibility: 1,
      field: LiquidGlassField.fromPath(_edge, step: 4),
    );
    final byShape = await _layerShadows(
      tester,
      glass: [_body],
      shape: const LiquidRoundedRectangle(radius: 0),
      shadow: shadow,
      visibility: 1,
    );
    expect(_alpha(byEdge, squareCornerOnly), greaterThan(0));
    expect(_alpha(byShape, squareCornerOnly), 0);
    expect(_alpha(byEdge, _center), 0);
  }, skip: skipProperGlassTests);
}

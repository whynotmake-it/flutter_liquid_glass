import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/painting/shader_constants.dart';
import 'package:liquid_glass_renderer/src/rendering/drawn_values.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';
import 'package:material_ui/material_ui.dart';

import 'shared.dart';

const _key = ValueKey('glow');
const _view = Size(260, 180);
const _glass = Rect.fromLTWH(30, 40, 200, 100);
final _spot = _glass.topLeft + _glow.center;
const _gray = Color(0xFF808080);
const _shape = LiquidRoundedSuperellipse(radius: 20);

const _glow = LiquidGlassGlow(
  center: Offset(50, 50),
  radius: 20,
  gain: 0.5,
  wash: 0.1,
);

LiquidGlassShapeFrame _frame(LiquidGlassGlow? glow) =>
    LiquidGlassShapeFrame(shape: _shape, glow: glow);

Widget _scene(
  List<(Rect, ValueListenable<LiquidGlassShapeFrame>)> glass, {
  bool fake = false,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: Center(
    child: RepaintBoundary(
      key: _key,
      child: SizedBox.fromSize(
        size: _view,
        child: ColoredBox(
          color: _gray,
          child: LiquidGlassLayer(
            settings: const LiquidGlassSettings.ios27Regular(
              brightness: Brightness.light,
            ),
            fake: fake,
            // A paint over a solid color: no backdrop filter, so every
            // render of the process draws.
            backdrop: const LiquidGlassBackdrop.solid(_gray),
            child: Stack(
              children: [
                for (final (rect, frame) in glass)
                  Positioned.fromRect(
                    rect: rect,
                    child: LiquidGlass.live(
                      frame: frame,
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

Future<Uint8List> _capture(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_key),
  );
  final image = (await tester.runAsync(boundary.toImage))!;
  final bytes = (await tester.runAsync(image.toByteData))!;
  image.dispose();
  return bytes.buffer.asUint8List();
}

Future<Uint8List> _render(
  WidgetTester tester,
  List<(Rect, ValueListenable<LiquidGlassShapeFrame>)> glass, {
  bool fake = false,
}) async {
  tester.view
    ..physicalSize = _view
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_scene(glass, fake: fake));
  await tester.pump();
  return _capture(tester);
}

(double, double, double) _at(Uint8List rgba, Offset p) {
  final i = (p.dy.toInt() * _view.width.toInt() + p.dx.toInt()) * 4;
  return (rgba[i] / 255, rgba[i + 1] / 255, rgba[i + 2] / 255);
}

void _expectClose(
  (double, double, double) actual,
  (double, double, double) expected,
  String reason,
) {
  expect(actual.$1, closeTo(expected.$1, 3 / 255), reason: '$reason red');
  expect(actual.$2, closeTo(expected.$2, 3 / 255), reason: '$reason green');
  expect(actual.$3, closeTo(expected.$3, 3 / 255), reason: '$reason blue');
}

void main() {
  testWidgets('a glow lights the glass as its CPU reference does', (
    tester,
  ) async {
    final plain = await _render(tester, [
      (_glass, ValueNotifier(_frame(null))),
    ]);
    final lit = await _render(tester, [(_glass, ValueNotifier(_frame(_glow)))]);
    final uniforms = glowUniforms(
      DrawnGlow.of(_glow)!,
      toLayer: Matrix4.translationValues(_glass.left, _glass.top, 0),
      box: null,
      devicePixelRatio: 1,
    );

    for (final p in [
      _spot,
      const Offset(100, 100),
      const Offset(200, 90),
      const Offset(60, 120),
    ]) {
      _expectClose(
        _at(lit, p),
        _shade(uniforms, p + const Offset(0.5, 0.5), _at(plain, p)),
        '$p',
      );
    }
    expect(
      _at(lit, _spot).$1,
      greaterThan(_at(lit, const Offset(200, 90)).$1),
      reason: 'the spot is brighter than the wash alone',
    );
    for (final p in const [Offset(10, 10), Offset(245, 90), Offset(130, 160)]) {
      expect(_at(lit, p), _at(plain, p), reason: '$p is outside the glass');
    }
  }, skip: skipProperGlassTests);

  testWidgets('a glow moves with its shape', (tester) async {
    final frame = ValueNotifier(_frame(_glow));
    addTearDown(frame.dispose);
    final before = await _render(tester, [(_glass, frame)]);
    const shift = Offset(10, 6);
    await tester.pumpWidget(_scene([(_glass.shift(shift), frame)]));
    await tester.pump();
    final after = await _capture(tester);

    for (final p in [_spot, const Offset(100, 100), const Offset(60, 120)]) {
      _expectClose(_at(after, p + shift), _at(before, p), '$p');
    }
  }, skip: skipProperGlassTests);

  testWidgets('a glow lights only its own shape', (tester) async {
    const left = Rect.fromLTWH(20, 40, 100, 100);
    const right = Rect.fromLTWH(140, 40, 100, 100);
    final plain = await _render(tester, [
      (left, ValueNotifier(_frame(null))),
      (right, ValueNotifier(_frame(null))),
    ]);
    final lit = await _render(tester, [
      (left, ValueNotifier(_frame(_glow))),
      (right, ValueNotifier(_frame(null))),
    ]);

    expect(
      _at(lit, const Offset(70, 90)).$1,
      greaterThan(_at(plain, const Offset(70, 90)).$1),
    );
    for (final p in const [Offset(150, 50), Offset(190, 90)]) {
      expect(_at(lit, p), _at(plain, p), reason: '$p is on the other shape');
    }
  }, skip: skipProperGlassTests);

  testWidgets('fake glass lights its shape', (tester) async {
    final plain = await _render(tester, [
      (_glass, ValueNotifier(_frame(null))),
    ], fake: true);
    final lit = await _render(tester, [
      (_glass, ValueNotifier(_frame(_glow))),
    ], fake: true);

    expect(
      _at(lit, _spot).$1,
      greaterThan(_at(lit, const Offset(200, 90)).$1),
    );
    expect(
      _at(lit, const Offset(200, 90)).$1,
      greaterThan(_at(plain, const Offset(200, 90)).$1),
    );
    for (final p in const [Offset(10, 10), Offset(245, 90)]) {
      expect(_at(lit, p), _at(plain, p), reason: '$p is outside the glass');
    }
  });

  test('a glow without a wash or a spot draws nothing', () {
    expect(
      DrawnGlow.of(const LiquidGlassGlow(gain: 1)),
      isNull,
    );
    expect(DrawnGlow.of(const LiquidGlassGlow(radius: 12)), isNull);
    expect(DrawnGlow.of(const LiquidGlassGlow()), isNull);
    expect(DrawnGlow.of(const LiquidGlassGlow(wash: 0.1)), isNotNull);
    expect(DrawnGlow.of(const LiquidGlassGlow(radius: 12, gain: 1)), isNotNull);
    expect(DrawnGlow.of(null), isNull);
  });

  testWidgets('a new glow reaches the retained pass without a repaint', (
    tester,
  ) async {
    final frame = ValueNotifier(_frame(null));
    addTearDown(frame.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: LiquidGlassLayer(
          settings: const LiquidGlassSettings.ios27Regular(
            brightness: Brightness.light,
          ),
          child: Stack(
            children: [
              Positioned.fromRect(
                rect: _glass,
                child: LiquidGlass.live(
                  frame: frame,
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
        .whereType<RenderLiquidGlassLayer>()
        .toSet()
        .single;
    final shape = tester.allRenderObjects.whereType<RenderLiquidGlass>().single;
    final unlit = layer.debugBackdropFilterLayer!.filter;

    frame.value = _frame(_glow);
    expect(layer.debugNeedsPaint, isFalse);
    expect(shape.debugNeedsPaint, isFalse);
    expect(layer.debugBackdropFilterLayer!.filter, isNot(unlit));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump();
    expect(layer.link.lit, shape);
  }, skip: skipProperGlassTests);

  test('the shader holds device pixels in highp', () {
    final source = File(
      'lib/assets/shaders/glass_glow.glsl',
    ).readAsStringSync();

    for (final variable in const [
      'highp vec2 q',
      'highp vec2 r',
      'highp float factor',
    ]) {
      expect(source, contains(variable));
    }
  });
}

/// The color the final pass gives the glass color [rgb] at [point], in matte
/// device pixels, under the glow [uniforms] (the renderer's `glowUniforms`):
/// the CPU reference of shaders/glass_glow.glsl and of the branch that skips
/// it.
(double, double, double) _shade(
  GlowUniforms uniforms,
  Offset point,
  (double, double, double) rgb,
) {
  final [spotX, spotY, falloff, gain] = uniforms[EffectsLane.glowSpot]!;
  final [boxX, boxY, halfWidth, halfHeight] = uniforms[EffectsLane.glowBox]!;
  final [wash] = uniforms[EffectsLane.glowWash]!;
  if (gain <= 0 && wash <= 0) return rgb;
  final qx = (point.dx - boxX).abs() - halfWidth;
  final qy = (point.dy - boxY).abs() - halfHeight;
  final cover = (0.5 - math.max(qx, qy)).clamp(0.0, 1.0);
  final rx = point.dx - spotX;
  final ry = point.dy - spotY;
  final factor = 1 + gain * math.exp(-falloff * (rx * rx + ry * ry) * math.ln2);
  double channel(double c) {
    final raised = (c + wash) * factor;
    final lit = raised < 1 ? raised : 1.0;
    return c + (lit - c) * cover;
  }

  return (channel(rgb.$1), channel(rgb.$2), channel(rgb.$3));
}

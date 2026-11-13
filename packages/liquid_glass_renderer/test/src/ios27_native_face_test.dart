import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:material_ui/material_ui.dart';

import 'shared.dart';

const _key = ValueKey('face');
const _view = Size(260, 190);

// The face of native iOS 27 glass at its center over a plain color:
// captures of `glassEffect` and `.buttonStyle(.glass)` on the iOS 27
// simulator for dark glass, and on an iPhone 16 Pro, whose slider is at 0.1,
// for light glass over anything but black (the simulator caps the luminance
// of light glass, see GlassColorParameters.ios27LightLuminanceCap).
const _panel = Size(210, 150);
const _toolbar = Size(224, 94);
const _control = Size(148, 63);
const _native = <(Brightness, Size, double, Color, Color)>[
  (Brightness.dark, _panel, 0, Color(0xFF000000), Color(0xFF202020)),
  (Brightness.dark, _panel, 0, Color(0xFF333333), Color(0xFF494949)),
  (Brightness.dark, _panel, 0, Color(0xFF737373), Color(0xFF747474)),
  (Brightness.dark, _panel, 0, Color(0xFF999999), Color(0xFF858585)),
  (Brightness.dark, _panel, 0, Color(0xFFDDDDDD), Color(0xFF939393)),
  (Brightness.dark, _panel, 0, Color(0xFFFFFFFF), Color(0xFF929292)),
  (Brightness.dark, _panel, 0, Color(0xFFEF4444), Color(0xFFFE4747)),
  (Brightness.dark, _panel, 0, Color(0xFF22C55E), Color(0xFF12AE4B)),
  (Brightness.dark, _panel, 0, Color(0xFF3B82F6), Color(0xFF367FF6)),
  (Brightness.dark, _panel, 0.5, Color(0xFFFFFFFF), Color(0xFF797979)),
  (Brightness.dark, _panel, 0.5, Color(0xFF737373), Color(0xFF6F6F6F)),
  (Brightness.dark, _panel, 0.5, Color(0xFFEF4444), Color(0xFFF44444)),
  (Brightness.dark, _panel, 1, Color(0xFFFFFFFF), Color(0xFF555555)),
  (Brightness.dark, _panel, 1, Color(0xFF737373), Color(0xFF494949)),
  (Brightness.dark, _panel, 1, Color(0xFF3B82F6), Color(0xFF264F92)),
  (Brightness.dark, _toolbar, 0, Color(0xFFFFFFFF), Color(0xFF9C9C9C)),
  (Brightness.dark, _toolbar, 0.5, Color(0xFFFFFFFF), Color(0xFF898989)),
  (Brightness.dark, _toolbar, 1, Color(0xFFFFFFFF), Color(0xFF575757)),
  (Brightness.dark, _control, 0, Color(0xFFFFFFFF), Color(0xFFB9B9B9)),
  (Brightness.dark, _control, 0.5, Color(0xFFFFFFFF), Color(0xFFB9B9B9)),
  (Brightness.dark, _control, 1, Color(0xFFFFFFFF), Color(0xFF6C6C6C)),
  (Brightness.light, _panel, 0.1, Color(0xFF000000), Color(0xFF6E6E6E)),
  (Brightness.light, _panel, 0.1, Color(0xFF333333), Color(0xFF8F8F8F)),
  (Brightness.light, _panel, 0.1, Color(0xFF737373), Color(0xFFB8B8B8)),
  (Brightness.light, _panel, 0.1, Color(0xFF999999), Color(0xFFD0D0D0)),
  (Brightness.light, _panel, 0.1, Color(0xFFDDDDDD), Color(0xFFF5F5F5)),
  (Brightness.light, _panel, 0.1, Color(0xFFFFFFFF), Color(0xFFFFFFFF)),
  (Brightness.light, _panel, 0.1, Color(0xFFEF4444), Color(0xFFFF8888)),
  (Brightness.light, _panel, 0.1, Color(0xFF22C55E), Color(0xFF45FF8B)),
  (Brightness.light, _panel, 0.1, Color(0xFF3B82F6), Color(0xFF73C6FF)),
  (Brightness.light, _control, 0, Color(0xFF000000), Color(0xFF666666)),
  (Brightness.light, _control, 0.5, Color(0xFF000000), Color(0xFF858585)),
  (Brightness.light, _control, 1, Color(0xFF000000), Color(0xFFB3B3B3)),
];

// The same under a tint, on the simulator: `.tint(#007AFF)` at full and at
// 40 % opacity on a regular panel, and at full opacity on a clear one, where
// both appearances draw alike.
const _blue = Color(0xFF007AFF);
const _blue40 = Color(0x66007AFF);
const _nativeTinted = <(Brightness?, Color, Color, Color)>[
  (Brightness.light, _blue, Color(0xFF000000), Color(0xFF0057C2)),
  (Brightness.light, _blue, Color(0xFF737373), Color(0xFF0069E1)),
  (Brightness.light, _blue, Color(0xFFFFFFFF), Color(0xFF007AFF)),
  (Brightness.light, _blue, Color(0xFFEF4444), Color(0xFF0063D7)),
  (Brightness.light, _blue40, Color(0xFF000000), Color(0xFF3E618C)),
  (Brightness.light, _blue40, Color(0xFF333333), Color(0xFF5278A5)),
  (Brightness.light, _blue40, Color(0xFF737373), Color(0xFF6B95C5)),
  (Brightness.light, _blue40, Color(0xFF3B82F6), Color(0xFF419DF3)),
  (Brightness.light, _blue40, Color(0xFFEF4444), Color(0xFF9975A3)),
  (Brightness.light, _blue40, Color(0xFFF97316), Color(0xFF998E7D)),
  (Brightness.dark, _blue, Color(0xFF000000), Color(0xFF0079FF)),
  (Brightness.dark, _blue, Color(0xFF737373), Color(0xFF1081FC)),
  (Brightness.dark, _blue, Color(0xFFFFFFFF), Color(0xFF1684FB)),
  (Brightness.dark, _blue, Color(0xFFF97316), Color(0xFF1282FC)),
  (Brightness.dark, _blue40, Color(0xFF000000), Color(0xFF134479)),
  (Brightness.dark, _blue40, Color(0xFF333333), Color(0xFF2F5E91)),
  (Brightness.dark, _blue40, Color(0xFF737373), Color(0xFF4C7AAB)),
  (Brightness.dark, _blue40, Color(0xFFFFFFFF), Color(0xFF618DBC)),
  (Brightness.dark, _blue40, Color(0xFF3B82F6), Color(0xFF2780F9)),
  (Brightness.dark, _blue40, Color(0xFFEF4444), Color(0xFF9E5E90)),
  (Brightness.dark, _blue40, Color(0xFFF97316), Color(0xFF96736C)),
  (null, _blue, Color(0xFF000000), Color(0xFF0047A6)),
  (null, _blue, Color(0xFF737373), Color(0xFF0060D2)),
  (null, _blue, Color(0xFFDDDDDD), Color(0xFF0077FA)),
  (null, _blue, Color(0xFFEF4444), Color(0xFF005DCC)),
];

Widget _scene(
  Brightness? brightness,
  Size size,
  double slider,
  Color page, {
  Color? tint,
}) => _glass(
  brightness == null
      ? LiquidGlassSettings.ios27Clear(tintAmount: slider)
      : LiquidGlassSettings.ios27Regular(
          brightness: brightness,
          tintAmount: slider,
        ),
  switch ((brightness, tint)) {
    (null, null) => const LiquidGlassAppearance.ios27Clear(),
    (null, final tint?) => LiquidGlassAppearance.ios27Clear(tint: tint),
    (final brightness?, null) => LiquidGlassAppearance.ios27Regular(
      brightness: brightness,
    ),
    (final brightness?, final tint?) => LiquidGlassAppearance.ios27Regular(
      brightness: brightness,
      tint: tint,
    ),
  },
  size,
  page,
);

Widget _glass(
  LiquidGlassSettings settings,
  LiquidGlassAppearance appearance,
  Size size,
  Color page,
) => Directionality(
  textDirection: TextDirection.ltr,
  child: RepaintBoundary(
    key: _key,
    child: ColoredBox(
      color: page,
      child: Center(
        child: LiquidGlassLayer(
          settings: settings,
          // Painted without a backdrop filter, so flutter_tester draws
          // every render in this process, not only the first.
          backdrop: LiquidGlassBackdrop.solid(page),
          child: LiquidGlass(
            shape: const LiquidRoundedSuperellipse(borderRadius: 30),
            appearance: appearance,
            child: SizedBox.fromSize(size: size),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('glass over a plain color shows the face native glass of its '
      'size shows', (tester) async {
    tester.view
      ..physicalSize = _view
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final off = <String>[];
    final cases = [
      for (final (brightness, size, slider, page, native) in _native)
        (brightness as Brightness?, size, slider, page, native, null as Color?),
      for (final (brightness, tint, page, native) in _nativeTinted)
        (brightness, _panel, 0.0, page, native, tint as Color?),
    ];
    for (final (brightness, size, slider, page, native, tint) in cases) {
      await tester.pumpWidget(
        _scene(brightness, size, slider, page, tint: tint),
      );
      await tester.pump();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(_key),
      );
      final image = (await tester.runAsync(boundary.toImage))!;
      final bytes = (await tester.runAsync(image.toByteData))!;
      image.dispose();
      final rgba = bytes.buffer.asUint8List();
      final at =
          ((_view.height ~/ 2) * _view.width.toInt() + _view.width ~/ 2) * 4;
      final drawn = [rgba[at], rgba[at + 1], rgba[at + 2]];
      final wanted = [
        (native.r * 255).round(),
        (native.g * 255).round(),
        (native.b * 255).round(),
      ];
      for (var channel = 0; channel < 3; channel++) {
        if ((drawn[channel] - wanted[channel]).abs() > 2) {
          off.add(
            '${brightness?.name ?? 'clear'} ${size.height} pt at slider '
            '$slider over $page under $tint: drew $drawn, native $wanted',
          );
          break;
        }
      }
      await tester.pumpWidget(const SizedBox());
    }
    expect(off, isEmpty, reason: off.join('\n'));
  }, skip: skipProperGlassTests);

  testWidgets('a shape that grows takes the face of its new size', (
    tester,
  ) async {
    tester.view
      ..physicalSize = _view
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Future<int> face(Size size) async {
      await tester.pumpWidget(
        _scene(Brightness.dark, size, 0, const Color(0xFFFFFFFF)),
      );
      await tester.pump();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(_key),
      );
      final image = (await tester.runAsync(boundary.toImage))!;
      final bytes = (await tester.runAsync(image.toByteData))!;
      image.dispose();
      return bytes.buffer.asUint8List()[((_view.height ~/ 2) *
                  _view.width.toInt() +
              _view.width ~/ 2) *
          4];
    }

    expect(await face(_control), closeTo(0xB9, 2));
    expect(await face(_panel), closeTo(0x92, 2));
    expect(await face(_toolbar), closeTo(0x9C, 2));
    expect(await face(_control), closeTo(0xB9, 2));
  }, skip: skipProperGlassTests);

  test('glass up to 64 points and from 160 points wears one model each', () {
    for (final brightness in Brightness.values) {
      final model = LiquidGlassColorModel.ios27(brightness: brightness);
      expect(identical(model.at(20), model.at(64)), isTrue);
      expect(identical(model.at(160), model.at(900)), isTrue);
      expect(model.at(64), isNot(model.at(160)));
      expect(model.at(100), model.at(100));
      expect(model.at(100), isNot(model.at(120)));
      expect(model.at(64).parameters!.bleed.opacity, 0);
    }
    const clear = LiquidGlassColorModel.ios27Clear();
    expect(identical(clear.at(40), clear), isTrue);
    const direct = LiquidGlassColorModel.direct();
    expect(identical(direct.at(40), direct), isTrue);
  });

  test('a grey tint takes its own tones, a color the tones of its scheme', () {
    const light = LiquidGlassColorModel.ios27(brightness: Brightness.light);
    const dark = LiquidGlassColorModel.ios27(brightness: Brightness.dark);
    const clear = LiquidGlassColorModel.ios27Clear();
    const white = Color(0xFFFFFFFF);
    const grey = Color(0x80808080);
    for (final model in [light, dark, clear]) {
      final tinted = model.at(200, tint: white).parameters!;
      // The diagonal matrix UIKit gives a grey tint g: 0.3125 of the face
      // plus 1.1875 g - 0.25.
      expect(tinted.tintTone(white, 0).r, closeTo(0.9375, 1e-9));
      expect(tinted.tintTone(grey, 0).g, closeTo(0.346, 1e-3));
      expect(tinted.tintTone(grey, 1).b, closeTo(0.6585, 1e-3));
      expect(
        identical(model.at(200, tint: white), model.at(300, tint: grey)),
        isTrue,
      );
      expect(model.at(200, tint: white), isNot(model.at(200)));
      expect(
        identical(model.at(200, tint: const Color(0x00808080)), model.at(200)),
        isTrue,
      );
    }
    // A color runs between the two tones UIKit's matrix gives it.
    const blue = Color(0xFF007AFF);
    final onLight = light.at(200, tint: blue).parameters!;
    expect(onLight.tintTone(blue, 0).g, closeTo(0.2502, 1e-3));
    expect(onLight.tintTone(blue, 0).b, closeTo(0.6, 1e-3));
    expect(onLight.tintTone(blue, 1).g, closeTo(0.4784, 1e-3));
    final onDark = dark.at(200, tint: blue).parameters!;
    expect(onDark.tintTone(blue, 0).g, closeTo(0.4651, 1e-3));
    expect(onDark.tintTone(blue, 1).r, closeTo(0.1735, 1e-3));
    expect(onDark.tintTone(blue, 1).b, closeTo(0.9681, 1e-3));
    expect(
      clear.at(200, tint: blue).parameters!.tintTone(blue, 0).b,
      closeTo(0.6, 1e-3),
    );
  });

  test('a curve through values bends at each of them', () {
    final curve = GlassColorCurve.through(const [0, 1, 1, 4, 2]);
    expect(curve.clear, 0);
    expect(curve.tinted, 2);
    expect(curve.evaluate(0.125), closeTo(0.5, 1e-12));
    expect(curve.evaluate(0.5), 1);
    expect(curve.evaluate(0.625), closeTo(2.5, 1e-12));
    expect(curve.evaluate(2), 2);
    expect(curve, GlassColorCurve.through(const [0, 1, 1, 4, 2]));
    expect(curve, isNot(GlassColorCurve.through(const [0, 1, 2, 4, 2])));
    expect(curve, isNot(const GlassColorCurve(0, 2)));
  });

  test('parameters keep their curves and bleed through JSON', () {
    final panel = GlassColorParameters.ios27Regular(
      brightness: Brightness.dark,
      shortSide: 120,
    );
    expect(GlassColorParameters.fromJson(panel.toJson()), panel);
    expect(panel.bleed.opacity, closeTo(0.8 * 56 / 96, 1e-12));
  });
}

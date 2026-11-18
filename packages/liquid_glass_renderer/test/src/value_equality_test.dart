import 'dart:ui';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/painting/glass_color_parameters.dart';

// Values built at run time, so that const canonicalisation cannot make two
// of them identical.
double _n(double value) => double.parse('$value');

void _holdsValue(Object a, Object same, List<Object> different) {
  expect(identical(a, same), isFalse);
  expect(a, same);
  expect(a.hashCode, same.hashCode);
  for (final other in different) {
    expect(a, isNot(other));
  }
}

void main() {
  test('shapes compare by kind, side and radii', () {
    _holdsValue(
      LiquidRoundedSuperellipse(radius: _n(12)),
      LiquidRoundedSuperellipse(radius: _n(12)),
      [
        LiquidRoundedSuperellipse(radius: _n(13)),
        LiquidRoundedSuperellipse.vertical(top: _n(12), bottom: _n(20)),
        LiquidRoundedSuperellipse(
          radius: _n(12),
          side: const BorderSide(),
        ),
        LiquidRoundedRectangle(radius: _n(12)),
      ],
    );
    _holdsValue(
      LiquidRoundedRectangle(radius: _n(8)),
      LiquidRoundedRectangle(radius: _n(8)),
      [
        LiquidRoundedRectangle(radius: _n(9)),
        LiquidRoundedSuperellipse(radius: _n(8)),
      ],
    );
    _holdsValue(
      LiquidOval(side: BorderSide(width: _n(2))),
      LiquidOval(side: BorderSide(width: _n(2))),
      [
        LiquidOval(side: BorderSide(width: _n(3))),
        LiquidRoundedRectangle(
          radius: 0,
          side: BorderSide(width: _n(2)),
        ),
      ],
    );
  });

  test('appearances compare by tint, visibility and color model', () {
    _holdsValue(
      LiquidGlassAppearance(tint: Color(0x40FF0000 + _n(1).toInt())),
      LiquidGlassAppearance(tint: Color(0x40FF0000 + _n(1).toInt())),
      [
        LiquidGlassAppearance(tint: Color(0x40FF0000 + _n(2).toInt())),
        LiquidGlassAppearance(
          tint: Color(0x40FF0000 + _n(1).toInt()),
          visibility: _n(0.5),
        ),
        LiquidGlassAppearance(
          tint: Color(0x40FF0000 + _n(1).toInt()),
          colorModel: const LiquidGlassColorModel.ios27Clear(),
        ),
      ],
    );
  });

  test('color models compare by parameters and adjustments', () {
    _holdsValue(
      LiquidGlassColorModel.direct(saturation: _n(1.2)),
      LiquidGlassColorModel.direct(saturation: _n(1.2)),
      [
        LiquidGlassColorModel.direct(saturation: _n(1.3)),
        LiquidGlassColorModel.direct(
          saturation: _n(1.2),
          transmissionGamma: _n(2),
        ),
        LiquidGlassColorModel.direct(saturation: _n(1.2), vibrancy: _n(1)),
      ],
    );
    _holdsValue(
      LiquidGlassColorModel.ios27Regular(
        brightness: Brightness.dark,
        transmissionGamma: _n(1),
      ),
      LiquidGlassColorModel.ios27Regular(
        brightness: Brightness.dark,
        transmissionGamma: _n(1),
      ),
      [
        LiquidGlassColorModel.ios27Regular(
          brightness: Brightness.light,
          transmissionGamma: _n(1),
        ),
        LiquidGlassColorModel.ios27Regular(
          brightness: Brightness.dark,
          transmissionGamma: _n(1.1),
        ),
        const LiquidGlassColorModel.ios27Clear(),
        const LiquidGlassColorModel.direct(),
      ],
    );
  });

  test('a color model is one of three kinds, each with its own fields', () {
    String kind(LiquidGlassColorModel model) => switch (model) {
      LiquidGlassDirectColorModel(:final saturation) => 'direct $saturation',
      LiquidGlassIos27RegularColorModel(:final brightness) =>
        'regular ${brightness.name}',
      LiquidGlassIos27ClearColorModel() => 'clear',
    };
    expect(
      kind(const LiquidGlassColorModel.direct(saturation: 2)),
      'direct 2.0',
    );
    expect(
      kind(
        const LiquidGlassColorModel.ios27Regular(brightness: Brightness.dark),
      ),
      'regular dark',
    );
    expect(kind(const LiquidGlassColorModel.ios27Clear()), 'clear');
  });

  test('every appearance constructor defaults to one tint', () {
    const none = Color(0x00000000);
    expect(const LiquidGlassAppearance().tint, none);
    expect(const LiquidGlassAppearance.ios27Clear().tint, none);
    expect(
      const LiquidGlassAppearance.ios27Regular(
        brightness: Brightness.light,
      ).tint,
      none,
    );
  });

  test('shapes of one kind lerp into each other', () {
    const from = LiquidRoundedSuperellipse(radius: 10);
    const to = LiquidRoundedSuperellipse.vertical(top: 20, bottom: 40);
    const middle = LiquidRoundedSuperellipse.vertical(top: 15, bottom: 25);
    expect(ShapeBorder.lerp(from, to, 0.5), middle);
    expect(from.lerpTo(to, 0.5), middle);
    expect(to.lerpFrom(from, 0.5), middle);
    expect(
      ShapeBorder.lerp(
        const LiquidRoundedRectangle(radius: 4),
        const LiquidRoundedRectangle(radius: 8),
        0.25,
      ),
      const LiquidRoundedRectangle(radius: 5),
    );
    expect(
      ShapeBorder.lerp(const LiquidOval(), const LiquidOval(), 0.5),
      const LiquidOval(),
    );
    expect(const LiquidOval().copyWith(), isA<LiquidOval>());
    expect(
      const LiquidRoundedSuperellipse(radius: 12).borderRadius,
      BorderRadius.circular(12),
    );
  });

  test('silhouettes compare by their shape and bounds, or by their path', () {
    const shape = LiquidRoundedSuperellipse(radius: 12);
    const bounds = Rect.fromLTWH(0, 0, 40, 20);
    _holdsValue(
      LiquidGlassSilhouette.shape(shape, Rect.fromLTWH(0, 0, _n(40), 20)),
      LiquidGlassSilhouette.shape(shape, Rect.fromLTWH(0, 0, _n(40), 20)),
      [
        const LiquidGlassSilhouette.shape(LiquidOval(), bounds),
        LiquidGlassSilhouette.shape(shape, bounds.shift(const Offset(1, 0))),
        LiquidGlassSilhouette.path(Path()..addRect(bounds)),
      ],
    );
    final path = Path()..addRect(bounds);
    expect(LiquidGlassSilhouette.path(path), LiquidGlassSilhouette.path(path));
    expect(LiquidGlassSilhouette.path(path).bounds, bounds);
    expect(
      LiquidGlassSilhouette.path(path),
      isNot(LiquidGlassSilhouette.path(Path()..addRect(bounds))),
    );
  });

  test('color parameters, curves and ramps compare by every field', () {
    _holdsValue(
      _toned(_n(0.5)),
      _toned(_n(0.5)),
      [
        _toned(_n(0.6)),
        GlassColorParameters.ios27Regular(
          brightness: Brightness.dark,
          shortSide: double.infinity,
          greyTint: false,
        ).copyWith(toneHigh: _ramp(0.5)),
      ],
    );
    _holdsValue(GlassColorCurve(_n(1), _n(2)), GlassColorCurve(_n(1), _n(2)), [
      GlassColorCurve(_n(1), _n(3)),
      GlassColorCurve(_n(0), _n(2)),
    ]);
    _holdsValue(_ramp(0.1), _ramp(0.1), [
      _ramp(0.2),
      GlassToneRamp(base: _n(0.1), amplitude: _n(0.6)),
    ]);
  });

  test('settings compare by every field', () {
    final settings = LiquidGlassSettings(refractionHeight: _n(20));
    _holdsValue(settings, LiquidGlassSettings(refractionHeight: _n(20)), [
      LiquidGlassSettings(refractionHeight: _n(21)),
      settings.copyWith(frost: LiquidGlassFrost.sigma(_n(9))),
      settings.copyWith(sliderPosition: _n(0.5)),
      settings.copyWith(glintStrength: _n(0.2)),
    ]);
    expect(settings.copyWith(), settings);
  });

  test('frosts and hazes compare by variant and by their numbers', () {
    LiquidGlassFrost regular() => const LiquidGlassFrost.ios27Regular();
    _holdsValue(
      LiquidGlassFrost.sigma(_n(4)),
      LiquidGlassFrost.sigma(_n(4)),
      [
        LiquidGlassFrost.sigma(_n(5)),
        regular(),
        const LiquidGlassFrost.ios27Clear(),
      ],
    );
    expect(regular(), isNot(const LiquidGlassFrost.ios27Clear()));
    expect(regular().hashCode, regular().hashCode);

    _holdsValue(
      LiquidGlassHaze(lighten: _n(0.5)),
      LiquidGlassHaze(lighten: _n(0.5)),
      [
        LiquidGlassHaze(lighten: _n(0.6)),
        LiquidGlassHaze(darken: _n(0.5)),
        LiquidGlassHaze(lighten: _n(0.5), sigma: _n(4)),
        LiquidGlassHaze(lighten: _n(0.5), cover: _n(1)),
        const LiquidGlassHaze.none(),
        const LiquidGlassHaze.ios27Clear(),
      ],
    );
    expect(
      const LiquidGlassHaze.ios27Regular(brightness: Brightness.light),
      isNot(const LiquidGlassHaze.ios27Regular(brightness: Brightness.dark)),
    );
    expect(
      const LiquidGlassHaze.ios27Regular(brightness: Brightness.light),
      isNot(const LiquidGlassHaze.ios27Clear()),
    );
  });
}

GlassToneRamp _ramp(double base) =>
    GlassToneRamp(base: _n(base), amplitude: _n(0.5));

GlassColorParameters _toned(double toneHighBase) =>
    GlassColorParameters.ios27Regular(
      brightness: Brightness.light,
      shortSide: double.infinity,
      greyTint: false,
    ).copyWith(toneHigh: _ramp(toneHighBase));

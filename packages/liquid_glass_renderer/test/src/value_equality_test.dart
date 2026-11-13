import 'dart:ui';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

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
      LiquidRoundedSuperellipse(borderRadius: _n(12)),
      LiquidRoundedSuperellipse(borderRadius: _n(12)),
      [
        LiquidRoundedSuperellipse(borderRadius: _n(13)),
        LiquidRoundedSuperellipse(borderRadius: _n(12), bottomRadius: _n(20)),
        LiquidRoundedSuperellipse(
          borderRadius: _n(12),
          side: const BorderSide(),
        ),
        LiquidRoundedRectangle(borderRadius: _n(12)),
      ],
    );
    _holdsValue(
      LiquidRoundedRectangle(borderRadius: _n(8)),
      LiquidRoundedRectangle(borderRadius: _n(8)),
      [
        LiquidRoundedRectangle(borderRadius: _n(9)),
        LiquidRoundedSuperellipse(borderRadius: _n(8)),
      ],
    );
    _holdsValue(
      LiquidOval(side: BorderSide(width: _n(2))),
      LiquidOval(side: BorderSide(width: _n(2))),
      [
        LiquidOval(side: BorderSide(width: _n(3))),
        LiquidRoundedRectangle(
          borderRadius: 0,
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
      LiquidGlassColorModel.ios27(
        brightness: Brightness.dark,
        transmissionGamma: _n(1),
      ),
      LiquidGlassColorModel.ios27(
        brightness: Brightness.dark,
        transmissionGamma: _n(1),
      ),
      [
        LiquidGlassColorModel.ios27(
          brightness: Brightness.light,
          transmissionGamma: _n(1),
        ),
        LiquidGlassColorModel(
          GlassColorParameters.fromJson({'toneGammaLuminance': _n(0.5)}),
        ),
      ],
    );
  });

  test('color parameters, curves and ramps compare by every field', () {
    _holdsValue(
      GlassColorParameters.fromJson({'toneGammaLuminance': _n(0.5)}),
      GlassColorParameters.fromJson({'toneGammaLuminance': _n(0.5)}),
      [
        GlassColorParameters.fromJson({'toneGammaLuminance': _n(0.6)}),
        GlassColorParameters.fromJson({
          'toneGammaLuminance': _n(0.5),
          'preset': 'ios27Dark',
        }),
      ],
    );
    _holdsValue(GlassColorCurve(_n(1), _n(2)), GlassColorCurve(_n(1), _n(2)), [
      GlassColorCurve(_n(1), _n(3)),
      GlassColorCurve(_n(0), _n(2)),
    ]);
    GlassToneRamp ramp({double base = 0.1, double exponent = 2}) =>
        GlassToneRamp(
          base: _n(base),
          amplitude: _n(0.5),
          pivot: _n(0.8),
          exponent: _n(exponent),
        );
    _holdsValue(ramp(), ramp(), [ramp(base: 0.2), ramp(exponent: 3)]);
  });

  test('settings compare by every field', () {
    final settings = LiquidGlassSettings(refractionHeight: _n(20));
    _holdsValue(settings, LiquidGlassSettings(refractionHeight: _n(20)), [
      LiquidGlassSettings(refractionHeight: _n(21)),
      settings.copyWith(frost: _n(9)),
      settings.copyWith(tintAmount: _n(0.5)),
      settings.copyWith(highlight: _n(0.2)),
    ]);
    expect(settings.copyWith(), settings);
  });
}

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_backdrop_filter.dart';

const _fade = Color(0x80102030);
const _line = Color(0x40FFFFFF);
const _clip = Rect.fromLTWH(10, 100, 300, 80);

LiquidGlassFrostBand _hard(
  AxisDirection edge, {
  double saturation = 1.25,
  double brightness = 0.05,
  double presence = 1,
}) => LiquidGlassFrostBand.hard(
  sigma: 2,
  edge: edge,
  fade: _fade,
  line: _line,
  saturation: saturation,
  brightness: brightness,
  presence: presence,
);

LiquidGlassFrostBand _soft(AxisDirection edge, {double fadeStart = 0.25}) =>
    LiquidGlassFrostBand.soft(
      sigma: 1.5,
      edge: edge,
      fade: _fade,
      fadeStart: fadeStart,
    );

void main() {
  group('a backdrop filter', () {
    test('equals one of the same kind and numbers, and no other', () {
      final blur = ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3);
      expect(
        LiquidGlassBackdropFilter.image(blur, sigma: 3),
        LiquidGlassBackdropFilter.image(blur, sigma: 3),
      );
      expect(
        LiquidGlassBackdropFilter.image(blur, sigma: 3),
        isNot(LiquidGlassBackdropFilter.image(blur)),
      );
      expect(
        LiquidGlassBackdropFilter.frost(sigma: 3),
        LiquidGlassBackdropFilter.frost(sigma: 3),
      );
      expect(
        LiquidGlassBackdropFilter.frost(sigma: 3),
        isNot(LiquidGlassBackdropFilter.frost(sigma: 4)),
      );
      expect(_hard(AxisDirection.up), _hard(AxisDirection.up));
      expect(_hard(AxisDirection.up), isNot(_hard(AxisDirection.down)));
      expect(
        _hard(AxisDirection.up),
        isNot(_hard(AxisDirection.up, presence: 0.5)),
      );
      expect(_soft(AxisDirection.up), _soft(AxisDirection.up));
      expect(
        _soft(AxisDirection.up),
        isNot(_soft(AxisDirection.up, fadeStart: 0.5)),
      );
      expect(_soft(AxisDirection.up), isNot(_hard(AxisDirection.up)));
    });

    test('prints as the factory that builds it', () {
      expect(
        '${LiquidGlassBackdropFilter.frost(sigma: 3)}',
        'LiquidGlassBackdropFilter.frost(sigma: 3.0)',
      );
      expect(
        '${_soft(AxisDirection.up)}',
        startsWith('LiquidGlassFrostBand.soft(sigma: 1.5, '),
      );
      expect(
        '${_hard(AxisDirection.up)}',
        startsWith('LiquidGlassFrostBand.hard(sigma: 2.0, '),
      );
    });
  });

  group('a soft band', () {
    test('is whole from its edge to fadeStart and gone at its far side', () {
      expect(
        _soft(AxisDirection.up).fadeRows(_clip),
        (whole: 120.0, gone: 180.0),
      );
      expect(
        _soft(AxisDirection.down).fadeRows(_clip),
        (whole: 160.0, gone: 100.0),
      );
    });

    test('has no hairline and leaves the color under it', () {
      final band = _soft(AxisDirection.up);
      final (start, end) = band.lineRows(_clip, 2);
      expect(start, end);
      expect(band.drawnLine.a, 0);
      expect(band.colorMatrix, isNull);
    });

    test('paints a gradient over all of its rect', () {
      expect(
        (Canvas canvas) => _soft(
          AxisDirection.up,
        ).paintOver(canvas, _clip, devicePixelRatio: 2),
        paints..something(
          (method, arguments) =>
              method == #drawRect &&
              arguments[0] == _clip &&
              (arguments[1] as Paint).shader != null,
        ),
      );
    });
  });

  group('a hard band', () {
    test('is whole all over', () {
      expect(_hard(AxisDirection.up).fadeRows(_clip), isNull);
    });

    test('keeps a hairline one device pixel wide away from its edge', () {
      expect(_hard(AxisDirection.up).lineRows(_clip, 2), (179.5, 180.0));
      expect(_hard(AxisDirection.down).lineRows(_clip, 2), (100.0, 100.5));
    });

    test('paints its fade and, beside it, the hairline over the fade', () {
      final line = Color.alphaBlend(_line, _fade);
      expect(
        (Canvas canvas) => _hard(
          AxisDirection.up,
        ).paintOver(canvas, _clip, devicePixelRatio: 2),
        paints
          ..rect(rect: const Rect.fromLTRB(10, 100, 310, 179.5), color: _fade)
          ..rect(rect: const Rect.fromLTRB(10, 179.5, 310, 180), color: line),
      );
      expect(
        (Canvas canvas) => _hard(
          AxisDirection.down,
        ).paintOver(canvas, _clip, devicePixelRatio: 2),
        paints
          ..rect(rect: const Rect.fromLTRB(10, 100.5, 310, 180), color: _fade)
          ..rect(rect: const Rect.fromLTRB(10, 100, 310, 100.5), color: line),
      );
    });

    test('changes the color only by what it was given', () {
      expect(
        _hard(AxisDirection.up, saturation: 1, brightness: 0).colorMatrix,
        isNull,
      );
      final matrix = _hard(AxisDirection.up, presence: 0.5).colorMatrix!;
      expect(matrix, hasLength(20));
      expect(matrix[18], 0.5);
      expect(matrix[4], 0.05 * 255);
    });
  });
}

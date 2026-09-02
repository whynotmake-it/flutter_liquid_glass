import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/internal/snap_rect_to_pixels.dart';

void main() {
  test('matte snapping commutes with whole-pixel scroll across zero', () {
    for (final dpr in [1.0, 2.0, 3.0]) {
      const rect = Rect.fromLTRB(69.5, 179.5, 350.5, 360.5);
      for (final pixels in [-600.0, -280.0, -180.0, 0.0, 280.0]) {
        final delta = Offset(0, pixels / dpr);
        expect(
          rect.shift(delta).snapToPixels(dpr),
          rectMoreOrLessEquals(
            rect.snapToPixels(dpr).shift(delta),
            epsilon: 1e-9,
          ),
          reason:
              'A retained matte and a fresh matte must have the same '
              'pixel grid at DPR $dpr after $pixels physical pixels.',
        );
      }
    }
  });

  test('expands filter bounds to physical-pixel buckets', () {
    const rect = Rect.fromLTRB(17, 33, 111, 148);

    expect(
      rect.expandToPixelBuckets(2),
      const Rect.fromLTRB(0, 32, 128, 160),
    );
  });

  test('bucket expansion never clips fractional transformed bounds', () {
    const rect = Rect.fromLTRB(-0.1, 31.9, 32.1, 64.1);
    final expanded = rect.expandToPixelBuckets(2);

    expect(expanded, const Rect.fromLTRB(-32, 0, 64, 96));
    expect(expanded.contains(rect.topLeft), isTrue);
    expect(expanded.contains(rect.bottomRight), isTrue);
  });
}

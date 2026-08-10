import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/internal/snap_rect_to_pixels.dart';

void main() {
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

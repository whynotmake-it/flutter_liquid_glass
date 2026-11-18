import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/painting/view_pixels.dart';

const _ratios = [1.0, 2.0, 2.625, 3.0];
const _shares = [1, 2, 4, 8];

void main() {
  test('buffer snapping commutes with whole-pixel scroll across zero', () {
    for (final dpr in [1.0, 2.0, 3.0]) {
      final view = ViewPixels(dpr);
      const rect = Rect.fromLTRB(69.5, 179.5, 350.5, 360.5);
      for (final pixels in [-600.0, -280.0, -180.0, 0.0, 280.0]) {
        final delta = Offset(0, pixels / dpr);
        expect(
          view.nearest(rect.shift(delta)),
          rectMoreOrLessEquals(
            view.nearest(rect).shift(delta),
            epsilon: 1e-9,
          ),
          reason:
              'A retained buffer and a fresh buffer must have the same '
              'pixel grid at DPR $dpr after $pixels physical pixels.',
        );
      }
    }
  });

  test('expands filter bounds to physical-pixel buckets', () {
    const rect = Rect.fromLTRB(17, 33, 111, 148);

    expect(
      const ViewPixels(2).bucket(rect),
      const Rect.fromLTRB(0, 32, 128, 160),
    );
  });

  test('bucket expansion never clips fractional transformed bounds', () {
    const rect = Rect.fromLTRB(-0.1, 31.9, 32.1, 64.1);
    final expanded = const ViewPixels(2).bucket(rect);

    expect(expanded, const Rect.fromLTRB(-32, 0, 64, 96));
    expect(expanded.contains(rect.topLeft), isTrue);
    expect(expanded.contains(rect.bottomRight), isTrue);
  });

  test('a box covered again from its logical rect is the same box', () {
    for (final dpr in _ratios) {
      final view = ViewPixels(dpr);
      for (final share in _shares) {
        for (var n = 0; n < 2000; n += 7) {
          final rect = Rect.fromLTWH(n / dpr + 0.3, n / 3, 41.7, n / 5 + 1);
          final box = view.cover(rect, share: share);
          expect(view.cover(view.logical(box), share: share), box);
          expect(box.left % share, 0);
          expect(box.right % share, 0);
          expect(box.rect.contains(rect.topLeft * dpr), isTrue);
        }
      }
    }
  });

  test('a box in logical pixels is one division of its whole edge', () {
    for (final dpr in _ratios) {
      for (final share in _shares) {
        for (var n = 0; n < 4000; n++) {
          expect((n * share) / dpr, n / (dpr / share));
        }
      }
    }
  });

  test('a band cut at the screen edge keeps the edge, its layer the grid', () {
    const dpr = 2.625;
    const view = ViewPixels(dpr);
    final screen = view.cover(Offset.zero & const Size(1206, 2622) / dpr);
    expect(screen.right, 1206);
    expect(screen.bottom, 2622);
    final band = view
        .cover(const Rect.fromLTRB(400, 900, 460, 1000), share: 4)
        .intersect(screen);
    expect(band.right, 1206);
    expect(band.outTo(4).right, 1208);
    expect(band.outTo(4).left, band.left);
  });
}

import 'package:flutter/rendering.dart';
import 'package:meta/meta.dart';

// Impeller reuses an offscreen target only at exactly the same size, and
// allocating one stalls the frame (11-36 ms on a Pixel 10).
const _pixelBucket = 64;

@internal
extension SnapRectToPixels on Rect {
  Rect snapToPixels(double devicePixelRatio) => Rect.fromLTRB(
    left.snapToPixel(devicePixelRatio),
    top.snapToPixel(devicePixelRatio),
    right.snapToPixel(devicePixelRatio),
    bottom.snapToPixel(devicePixelRatio),
  );

  /// Expands this rect outward to multiples of 64 device pixels, for a
  /// render target that would otherwise change size every frame.
  Rect expandToPixelBuckets(double devicePixelRatio) {
    final logicalBucket = _pixelBucket / devicePixelRatio;
    return Rect.fromLTRB(
      (left / logicalBucket).floorToDouble() * logicalBucket,
      (top / logicalBucket).floorToDouble() * logicalBucket,
      (right / logicalBucket).ceilToDouble() * logicalBucket,
      (bottom / logicalBucket).ceilToDouble() * logicalBucket,
    );
  }
}

extension on double {
  // Half-pixel ties go the same way on both sides of zero: roundToDouble
  // rounds them away from zero, so a matte moved across the origin would
  // change size by a pixel, and a retained translated matte must match one
  // rasterized at the destination.
  double snapToPixel(double devicePixelRatio) =>
      (this * devicePixelRatio + 0.5).floorToDouble() / devicePixelRatio;
}

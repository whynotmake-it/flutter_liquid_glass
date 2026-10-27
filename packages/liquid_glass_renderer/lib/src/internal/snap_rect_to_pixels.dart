import 'package:flutter/rendering.dart';
import 'package:meta/meta.dart';

/// Device-pixel bucket sizes for render targets that would otherwise change
/// size every frame: Impeller reuses an offscreen target only at exactly the
/// same size, and allocating one stalls the frame (11-36 ms on a Pixel 10).
@internal
abstract final class PixelBuckets {
  /// Most targets: a glass filter's clip, a shadow layer, a larger pass.
  static const standard = 64;

  /// Small backdrop passes (a pill or a button), where a 64 px bucket would
  /// be a large share of the pass.
  static const fine = 32;

  /// Large backdrop passes while they resize. 64 px on a sheet that grows
  /// 545 px/s is a new target every 7 frames; 256 px makes it every ~28.
  static const coarse = 256;
}

@internal
extension SnapRectToPixels on Rect {
  Rect snapToPixels(double devicePixelRatio) {
    return Rect.fromLTRB(
      left.snapToPixel(devicePixelRatio: devicePixelRatio),
      top.snapToPixel(devicePixelRatio: devicePixelRatio),
      right.snapToPixel(devicePixelRatio: devicePixelRatio),
      bottom.snapToPixel(devicePixelRatio: devicePixelRatio),
    );
  }

  /// Expands this rect to stable physical-pixel buckets.
  ///
  /// Backdrop image filters allocate an offscreen Impeller render target for
  /// their clip bounds. Small animated transform changes otherwise produce a
  /// differently sized target on nearly every frame.
  Rect expandToPixelBuckets(
    double devicePixelRatio, {
    int bucketSize = PixelBuckets.standard,
  }) {
    final logicalBucket = bucketSize / devicePixelRatio;
    return Rect.fromLTRB(
      (left / logicalBucket).floorToDouble() * logicalBucket,
      (top / logicalBucket).floorToDouble() * logicalBucket,
      (right / logicalBucket).ceilToDouble() * logicalBucket,
      (bottom / logicalBucket).ceilToDouble() * logicalBucket,
    );
  }
}

extension on double {
  double snapToPixel({required double devicePixelRatio}) {
    // Resolve half-pixel ties in the same direction on both sides of zero.
    // roundToDouble rounds ties away from zero, so moving an antialiased
    // matte across the origin changes its dimensions by a pixel. A retained
    // translated matte must match one rasterized at the destination.
    return (this * devicePixelRatio + 0.5).floorToDouble() / devicePixelRatio;
  }
}

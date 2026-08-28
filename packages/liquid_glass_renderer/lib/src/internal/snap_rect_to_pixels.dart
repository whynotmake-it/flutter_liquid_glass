import 'package:flutter/rendering.dart';
import 'package:meta/meta.dart';

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
    int bucketSize = 64,
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
    return (this * devicePixelRatio).roundToDouble() / devicePixelRatio;
  }
}

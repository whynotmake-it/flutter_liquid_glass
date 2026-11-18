import 'dart:ui';

import 'package:liquid_glass_renderer/src/painting/screen_place.dart';
import 'package:meta/meta.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4;

/// A rect of the screen's device pixels whose edges lie on whole pixels.
///
/// Only [ViewPixels] rounds a logical rect into one, so a box is rounded once
/// and whatever is laid out from it counts whole pixels.
@internal
extension type const DeviceBox._(Rect rect) {
  /// The left edge, in device pixels.
  double get left => rect.left;

  /// The top edge, in device pixels.
  double get top => rect.top;

  /// The right edge, in device pixels.
  double get right => rect.right;

  /// The bottom edge, in device pixels.
  double get bottom => rect.bottom;

  /// The width, in device pixels.
  double get width => rect.width;

  /// The height, in device pixels.
  double get height => rect.height;

  /// The top left corner.
  Offset get topLeft => rect.topLeft;

  /// The size, in device pixels.
  Size get size => rect.size;

  /// Whether the box holds no pixel.
  bool get isEmpty => rect.isEmpty;

  /// The pixels both boxes hold.
  DeviceBox intersect(DeviceBox other) =>
      DeviceBox._(rect.intersect(other.rect));

  /// The box grown to whole cells of [share] device pixels along each side,
  /// on a grid anchored at the screen's origin.
  DeviceBox outTo(int share) => share == 1
      ? this
      : DeviceBox._(
          Rect.fromLTRB(
            (left / share).floorToDouble() * share,
            (top / share).floorToDouble() * share,
            (right / share).ceilToDouble() * share,
            (bottom / share).ceilToDouble() * share,
          ),
        );

  /// The pixels across the box of a copy whose pixels hold [share] device
  /// pixels along each side.
  (int, int) pixelsOn(int share) =>
      ((width / share).round(), (height / share).round());

  /// The box grown down to [bottom], a whole device pixel, or itself where
  /// it already reaches it.
  DeviceBox downTo(double bottom) => bottom <= this.bottom
      ? this
      : DeviceBox._(Rect.fromLTRB(left, top, right, bottom));
}

// Impeller reuses an offscreen target only at exactly the same size, and
// allocating one stalls the frame (11-36 ms on a Pixel 10).
const _pixelBucket = 64;

/// The screen's device pixels: the one ratio a frame's glass lays its copies
/// out at.
@internal
extension type const ViewPixels(double devicePixelRatio) {
  /// [rect] (logical pixels) grown to whole cells of [share] device pixels
  /// along each side, on a grid anchored at the screen's origin.
  ///
  /// A rect laid out from a box and scaled back lands a hair off its pixels
  /// (837 / 2.625 * 2.625 is 836.999...); it stays on them, or covering it
  /// again would grow it by a pixel.
  DeviceBox cover(Rect rect, {int share = 1}) {
    final pixels = devicePixelRatio / share;
    return DeviceBox._(
      Rect.fromLTRB(
        (rect.left * pixels + 1e-6).floorToDouble() * share,
        (rect.top * pixels + 1e-6).floorToDouble() * share,
        (rect.right * pixels - 1e-6).ceilToDouble() * share,
        (rect.bottom * pixels - 1e-6).ceilToDouble() * share,
      ),
    );
  }

  /// [box] in logical pixels.
  Rect logical(DeviceBox box) => Rect.fromLTRB(
    box.left / devicePixelRatio,
    box.top / devicePixelRatio,
    box.right / devicePixelRatio,
    box.bottom / devicePixelRatio,
  );

  /// [rect] (logical pixels, in any space the screen's pixels are whole in)
  /// grown out to whole pixels.
  Rect outward(Rect rect) => logical(cover(rect));

  /// [size] (logical pixels) grown to whole pixels.
  Size whole(Size size) => Size(
    (size.width * devicePixelRatio).ceilToDouble() / devicePixelRatio,
    (size.height * devicePixelRatio).ceilToDouble() / devicePixelRatio,
  );

  /// [rect] (logical pixels, in any space the screen's pixels are whole in)
  /// with each edge moved to the nearest whole pixel.
  ///
  /// Half-pixel ties go the same way on both sides of zero: roundToDouble
  /// rounds them away from zero, so a buffer moved across the origin would
  /// change size by a pixel, and a retained translated buffer must match one
  /// rasterized at the destination.
  Rect nearest(Rect rect) => Rect.fromLTRB(
    _nearest(rect.left),
    _nearest(rect.top),
    _nearest(rect.right),
    _nearest(rect.bottom),
  );

  double _nearest(double edge) =>
      (edge * devicePixelRatio + 0.5).floorToDouble() / devicePixelRatio;

  /// [rect] (logical pixels) grown outward to multiples of 64 device pixels,
  /// for a render target that would otherwise change size every frame.
  Rect bucket(Rect rect) {
    final logicalBucket = _pixelBucket / devicePixelRatio;
    return Rect.fromLTRB(
      (rect.left / logicalBucket).floorToDouble() * logicalBucket,
      (rect.top / logicalBucket).floorToDouble() * logicalBucket,
      (rect.right / logicalBucket).ceilToDouble() * logicalBucket,
      (rect.bottom / logicalBucket).ceilToDouble() * logicalBucket,
    );
  }
}

/// [rect], in the coordinates [toDevice] maps to device pixels, grown to the
/// whole device pixels around it, or shrunk to those inside it when
/// [inward]; null where [toDevice] turns it ([Turned]).
@internal
Rect? onWholeDevicePixels(Rect rect, Matrix4 toDevice, {bool inward = false}) {
  if (ScreenPlace.of(toDevice) is Turned) return null;
  final m = toDevice.storage;
  double snap(double at, double axisScale, double shift, {required bool up}) {
    final pixel = at * axisScale + shift;
    return ((up ? pixel.ceilToDouble() : pixel.floorToDouble()) - shift) /
        axisScale;
  }

  return Rect.fromLTRB(
    snap(rect.left, m[0], m[12], up: inward),
    snap(rect.top, m[5], m[13], up: inward),
    snap(rect.right, m[0], m[12], up: !inward),
    snap(rect.bottom, m[5], m[13], up: !inward),
  );
}

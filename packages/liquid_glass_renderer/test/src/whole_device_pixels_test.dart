import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/painting/view_pixels.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  /// A local->device transform for `dpr` 2 with the shape origin at the
  /// given logical offset.
  Matrix4 transformAt(double x, double y, {double dpr = 2}) =>
      Matrix4.identity()
        ..translateByDouble(x * dpr, y * dpr, 0, 1)
        ..scaleByDouble(dpr, dpr, 1, 1);

  const quad = Rect.fromLTWH(-1.75, -1.75, 103.5, 103.5);

  test('a quad at half device pixels grows out to whole pixels', () {
    // Shape at (40, 30)pt -> quad edges at 76.5px/283.5px.
    expect(
      onWholeDevicePixels(quad, transformAt(40, 30)),
      const Rect.fromLTWH(-2, -2, 104, 104),
    );
  });

  test('already aligned quads are unchanged', () {
    // Shape at (40.25, 30.25)pt -> quad edges already on whole px.
    expect(onWholeDevicePixels(quad, transformAt(40.25, 30.25)), quad);
  });

  test('quarter-pixel phases snap outward', () {
    // Shape at (40.125, 30.125)pt -> quad edges at 76.75px/283.75px.
    expect(
      onWholeDevicePixels(quad, transformAt(40.125, 30.125)),
      const Rect.fromLTWH(-2.125, -2.125, 104, 104),
    );
  });

  test('axes snap independently', () {
    // x aligned (quad edge at whole px), y at half px.
    final r = onWholeDevicePixels(quad, transformAt(40.25, 30))!;
    expect(r.left, quad.left);
    expect(r.right, quad.right);
    expect(r.top, -2.0);
    expect(r.bottom, 102.0);
  });

  test('inward, a rect shrinks to the whole pixels inside it', () {
    expect(
      onWholeDevicePixels(quad, transformAt(40, 30), inward: true),
      const Rect.fromLTWH(-1.5, -1.5, 103, 103),
    );
  });

  test('a turned transform has no whole pixels', () {
    final rotated = Matrix4.identity()..rotateZ(0.3);
    expect(onWholeDevicePixels(quad, rotated), isNull);
    final flipped = Matrix4.identity()..scaleByDouble(-1, 1, 1, 1);
    expect(onWholeDevicePixels(quad, flipped), isNull);
  });
}

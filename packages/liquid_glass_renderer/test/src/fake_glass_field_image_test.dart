import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/painting/shader_constants.dart';
import 'package:liquid_glass_renderer/src/rendering/fake_glass_field_image.dart';

LiquidGlassField _field() {
  const cols = 400;
  const rows = 200;
  final samples = Float32List(cols * rows * 4);
  for (var j = 0; j < rows; j++) {
    for (var i = 0; i < cols; i++) {
      final at = (j * cols + i) * 4;
      samples[at] =
          math.sqrt(math.pow(i - 200.3, 2) + math.pow(j - 99.7, 2)) - 80;
    }
  }
  return LiquidGlassField(
    samples: samples,
    columns: cols,
    rows: rows,
    origin: ui.Offset.zero,
    step: 1,
    edge: ui.Path()
      ..addOval(
        ui.Rect.fromCircle(center: const ui.Offset(200.3, 99.7), radius: 80),
      ),
  );
}

void main() {
  test('every texel holds its node: the distance in red, the normal by '
      'central differences in green and blue', () async {
    final field = _field();
    final LiquidGlassField(:samples, columns: cols, :rows) = field;
    expect(cols * rows, greaterThan(1 << 16));
    final images = FakeGlassFieldImage();
    addTearDown(images.dispose);
    final image = images.of(field);
    expect((image.width, image.height), (cols, rows));
    final bytes = (await image.toByteData())!.buffer.asUint8List();

    double distance(int i, int j) => samples[(j * cols + i) * 4];
    const span = fakeFieldInside + fakeFieldOutside;
    var worst = 0;
    for (var j = 0; j < rows; j++) {
      for (var i = 0; i < cols; i++) {
        final left = math.max(i - 1, 0);
        final right = math.min(i + 1, cols - 1);
        final up = math.max(j - 1, 0);
        final down = math.min(j + 1, rows - 1);
        final dx = (distance(right, j) - distance(left, j)) / (right - left);
        final dy = (distance(i, down) - distance(i, up)) / (down - up);
        final length = math.sqrt(dx * dx + dy * dy);
        final expected = [
          ((distance(i, j) + fakeFieldInside) / span).clamp(0.0, 1.0),
          dx / length * 0.5 + 0.5,
          dy / length * 0.5 + 0.5,
          1.0,
        ];
        final at = (j * cols + i) * 4;
        for (var c = 0; c < 4; c++) {
          final error = (bytes[at + c] - expected[c] * 255).abs().round();
          worst = math.max(worst, error);
        }
      }
    }
    expect(worst, lessThanOrEqualTo(1));
  });

  test('the image is drawn again only for other samples', () {
    final field = _field();
    final images = FakeGlassFieldImage();
    addTearDown(images.dispose);
    final first = images.of(field);
    expect(
      images.of(
        LiquidGlassField(
          samples: field.samples,
          columns: field.columns,
          rows: field.rows,
          origin: field.origin + const ui.Offset(5, 5),
          step: field.step,
          edge: field.edge,
        ),
      ),
      same(first),
    );
    expect(images.of(_field()), isNot(same(first)));
  });
}

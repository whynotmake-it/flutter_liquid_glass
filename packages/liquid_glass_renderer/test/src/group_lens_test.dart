import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/rendering/shape_set.dart';

// A shape's row: [width] by [height], its distances scaled by [scale], the
// first of its blend group where [first].
List<double> _row(
  double width,
  double height, {
  required bool first,
  double scale = 1,
}) => [0, width, height, 0, 1, 0, 0, 1, 0, 0, scale, if (first) -11 else 10];

ShapeSet _set(List<List<double>> rows) => ShapeSet.rows(
  shapes: [for (final row in rows) ...row],
  boxes: List.filled(rows.length * 4, 0),
);

void main() {
  test('glass that blends takes its lens from the smallest of its group', () {
    final set = _set([
      _row(160, 100, first: true),
      _row(70, 70, first: false),
      _row(300, 200, first: true),
      _row(44, 400, first: true),
      _row(120, 120, first: false),
      _row(64, 500, first: false),
    ]);
    expect(
      [for (var i = 0; i < set.count; i++) set.lensOf(i)],
      [35, 35, 100, 22, 22, 22],
    );
  });

  test('the lens is as large as the shape is drawn', () {
    final set = _set([
      _row(100, 100, first: true, scale: 0.5),
      _row(80, 80, first: false),
    ]);
    expect(set.lensOf(0), 25);
    expect(set.lensOf(1), 25);
  });
}

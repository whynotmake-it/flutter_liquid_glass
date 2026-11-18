import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/painting/shader_constants.dart';

/// The node image fake glass shades a field body from
/// (fake_glass_field_surface.frag): one texel per node of a
/// [LiquidGlassField].
final class FakeGlassFieldImage {
  Float32List? _samples;
  int _cols = 0;
  int _rows = 0;
  ui.Image? _image;

  /// The node image of [field].
  ui.Image of(LiquidGlassField field) {
    final held = _image;
    if (held != null &&
        identical(_samples, field.samples) &&
        _cols == field.columns &&
        _rows == field.rows) {
      return held;
    }
    held?.dispose();
    _samples = field.samples;
    _cols = field.columns;
    _rows = field.rows;
    return _image = _drawNodes(field);
  }

  /// Releases the image it holds.
  void dispose() {
    _image?.dispose();
    _image = null;
    _samples = null;
  }
}

// Vertices one Uint16 index list reaches.
const _indexedVertices = 1 << 16;

ui.Image _drawNodes(LiquidGlassField field) {
  final LiquidGlassField(:samples, columns: cols, :rows) = field;
  final colors = _nodeColors(samples, cols, rows);
  // A ring of vertices half a texel outside the image repeats the outer
  // nodes, so every texel's center lies inside the mesh, on its own node's
  // vertex, whichever edges the rasterizer counts as inside.
  final across = cols + 2;
  final down = rows + 2;
  final bandRows = _indexedVertices ~/ across;
  assert(bandRows >= 2, 'A field $cols nodes wide is too wide to draw.');
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final paint = ui.Paint()..blendMode = ui.BlendMode.src;
  for (var top = 0; top < down - 1; top += bandRows - 1) {
    final bottom = math.min(top + bandRows - 1, down - 1);
    final count = (bottom - top + 1) * across;
    final positions = Float32List(count * 2);
    final vertexColors = Int32List(count);
    for (var b = top; b <= bottom; b++) {
      final node = (b - 1).clamp(0, rows - 1) * cols;
      for (var a = 0; a < across; a++) {
        final at = (b - top) * across + a;
        positions[at * 2] = a - 0.5;
        positions[at * 2 + 1] = b - 0.5;
        vertexColors[at] = colors[node + (a - 1).clamp(0, cols - 1)];
      }
    }
    final indices = Uint16List((bottom - top) * (across - 1) * 6);
    var at = 0;
    for (var b = 0; b < bottom - top; b++) {
      for (var a = 0; a < across - 1; a++) {
        final corner = b * across + a;
        indices
          ..[at++] = corner
          ..[at++] = corner + 1
          ..[at++] = corner + across
          ..[at++] = corner + 1
          ..[at++] = corner + across + 1
          ..[at++] = corner + across;
      }
    }
    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      positions,
      colors: vertexColors,
      indices: indices,
    );
    // The vertices' own colors: the paint's color is the source of the
    // blend, the vertices' the destination.
    canvas.drawVertices(vertices, ui.BlendMode.dst, paint);
    vertices.dispose();
  }
  final picture = recorder.endRecording();
  final image = picture.toImageSync(cols, rows);
  picture.dispose();
  return image;
}

Int32List _nodeColors(Float32List samples, int cols, int rows) {
  double distance(int i, int j) => samples[(j * cols + i) * 4];
  int channel(double value) => (value.clamp(0.0, 1.0) * 255).round();
  const span = fakeFieldInside + fakeFieldOutside;
  final colors = Int32List(cols * rows);
  for (var j = 0; j < rows; j++) {
    final up = math.max(j - 1, 0);
    final down = math.min(j + 1, rows - 1);
    for (var i = 0; i < cols; i++) {
      final left = math.max(i - 1, 0);
      final right = math.min(i + 1, cols - 1);
      final dx = (distance(right, j) - distance(left, j)) / (right - left);
      final dy = (distance(i, down) - distance(i, up)) / (down - up);
      final length = math.sqrt(dx * dx + dy * dy);
      final (nx, ny) = length > 1e-9 ? (dx / length, dy / length) : (0.0, 0.0);
      colors[j * cols + i] =
          0xFF000000 |
          channel((distance(i, j) + fakeFieldInside) / span) << 16 |
          channel(nx * 0.5 + 0.5) << 8 |
          channel(ny * 0.5 + 0.5);
    }
  }
  return colors;
}

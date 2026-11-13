// Run with `flutter test --enable-impeller --enable-flutter-gpu`: the layer is
// sized as Impeller sizes it.
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/rendering/pinned_layer.dart';

// A blur clamped at a layer's edge shows where the layer ends: a square that
// fills the layer stays whole to its edge, one inside a larger layer fades
// there.
final _clamped = ui.ImageFilter.blur(
  sigmaX: 4,
  sigmaY: 4,
  tileMode: TileMode.clamp,
);
const _square = Rect.fromLTWH(0, 0, 10, 10);
final _green = Paint()..color = const Color(0xFF00FF00);
const _canvas = 100;

Future<int Function(int x, int y)> _alphaOf(ui.Image image) async {
  final bytes = (await image.toByteData())!;
  image.dispose();
  return (int x, int y) => bytes.getUint8((y * _canvas + x) * 4 + 3);
}

// The layer of [size] from the canvas's corner under [clip], recorded into
// a picture: with an R-tree, as macOS records a frame.
Future<int Function(int x, int y)> _inPicture(Size size, Rect clip) {
  final recorder = ui.PictureRecorder();
  Canvas(recorder)
    ..clipRect(clip)
    ..saveLayer(null, Paint()..imageFilter = _clamped)
    ..drawPicture(PinnedLayers.pinOf(size))
    ..drawRect(_square, _green)
    ..restore();
  return _alphaOf(recorder.endRecording().toImageSync(_canvas, _canvas));
}

// The same layer pushed into a scene, as iOS records a frame.
Future<int Function(int x, int y)> _inScene(Size size, Rect clip) {
  final square = ui.PictureRecorder();
  Canvas(square).drawRect(_square, _green);
  final builder = ui.SceneBuilder()
    ..pushClipRect(clip, clipBehavior: ui.Clip.hardEdge);
  PinnedLayers.push(builder, _clamped, Offset.zero, size);
  builder
    ..addPicture(Offset.zero, square.endRecording())
    ..pop()
    ..pop();
  final scene = builder.build();
  final image = scene.toImageSync(_canvas, _canvas);
  scene.dispose();
  return _alphaOf(image);
}

void main() {
  const whole = Rect.fromLTWH(0, 0, 100, 100);
  // Each cuts less than Impeller's bound off the layer, which keeps it whole.
  final cuts = {
    'right': (const Size(120, 90), whole),
    'bottom': (const Size(90, 120), whole),
    'right and bottom': (const Size(120, 120), whole),
  };
  final ways = {'a picture': _inPicture, 'a scene': _inScene};
  for (final MapEntry(key: way, value: draw) in ways.entries) {
    for (final MapEntry(key: side, value: (size, clip)) in cuts.entries) {
      test('a pinned layer in $way keeps its size where a clip cuts its '
          '$side', () async {
        final alpha = await draw(size, clip);
        expect(alpha(9, 9), lessThan(200), reason: 'the square fades');
        expect(alpha(5, 5), greaterThan(200));
        expect(alpha(30, 30), 0);
      });
    }
  }
}

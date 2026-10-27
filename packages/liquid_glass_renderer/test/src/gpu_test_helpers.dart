import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';

/// Creates a renderer and registers cleanup for the end of the test.
Future<FlutterGpuGeometryRenderer> createGeometryRenderer() async {
  final renderer = await FlutterGpuGeometryRenderer.fromAsset(
    ShaderKeys.gpuGeometryShaderBundle,
  );
  addTearDown(renderer.dispose);
  return renderer;
}

/// Renders a 64x64 rounded rectangle and returns its matte image.
ui.Image renderTestRectangle(
  FlutterGpuGeometryRenderer renderer, {
  double centerX = 16,
  bool writeMatte = true,
  bool writeMaterials = false,
  List<double> appearanceData = const <double>[],
}) => renderer
    .render(
      width: 64,
      height: 64,
      shapeData: [
        3, 20, 30, 4, // Rounded rectangle.
        1, 0, 0, 1, // Identity inverse affine basis.
        centerX, 32, 1, -1, // Center, scale, new group marker.
      ],
      numShapes: 1,
      refractionAmount: 24,
      refractionHeight: 10,
      offsetX: 0,
      offsetY: 0,
      writeMatte: writeMatte,
      writeMaterials: writeMaterials,
      appearanceData: appearanceData,
      matteScale: testMatteScale,
    )
    .image;

/// The matte scale the renderer tests draw at.
const testMatteScale = 2;

/// The four floats of each texel of a low-res matte image: the distance to the
/// edge, the surface direction (possibly shortened), and half of the shape's
/// shorter side (see `geometry_fragment.glsl`).
///
/// The engine reads the image back as if the fourth channel were alpha and
/// divides the other three by it; this multiplies them back. That can't work
/// where the fourth channel is zero, which is only the texels far from every
/// shape, so those are set to `kLowResFarInward`, which is what they hold.
Future<Float32List> readGeometryField(ui.Image image) async {
  final data = await image.toByteData(
    format: ui.ImageByteFormat.rawExtendedRgba128,
  );
  final field = Float32List.fromList(
    data!.buffer.asFloat32List(data.offsetInBytes, data.lengthInBytes ~/ 4),
  );
  for (var i = 0; i < field.length; i += 4) {
    final halfMinor = field[i + 3];
    if (halfMinor > 0) {
      field[i] *= halfMinor;
      field[i + 1] *= halfMinor;
      field[i + 2] *= halfMinor;
    } else {
      field[i] = kLowResFarInward;
      field[i + 1] = 0;
      field[i + 2] = 0;
    }
  }
  return field;
}

/// The distance to the edge at matte pixel ([x], [y]), as the final shader
/// reads it: the four nearest texels blended. [textureWidth] is the width of
/// the low-res matte image, [scale] its matte scale.
double fieldInwardAt(
  Float32List field,
  int textureWidth,
  int x,
  int y, {
  int scale = testMatteScale,
}) {
  final u = x / scale;
  final v = y / scale;
  final i = u.floor();
  final j = v.floor();
  final fu = u - i;
  final fv = v - j;
  double texel(int tx, int ty) => field[(ty * textureWidth + tx) * 4];
  final top = texel(i, j) * (1 - fu) + texel(i + 1, j) * fu;
  final bottom = texel(i, j + 1) * (1 - fu) + texel(i + 1, j + 1) * fu;
  return top * (1 - fv) + bottom * fv;
}

/// The top-left [width] x [height] texels of a low-res matte image that is
/// [textureWidth] texels wide. The rest of the texture is unused space, since
/// textures only grow.
Float32List fieldRegion(
  Float32List field,
  int textureWidth,
  int width,
  int height,
) => Float32List.fromList([
  for (var y = 0; y < height; y++)
    ...field.sublist(y * textureWidth * 4, (y * textureWidth + width) * 4),
]);

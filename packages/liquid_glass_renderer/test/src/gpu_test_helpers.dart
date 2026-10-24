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

/// The four floats per texel of a geometry field image: the inward edge
/// distance, the optical normal scaled by its shortening factor, and the half
/// short side (see `geometry_fragment.glsl`).
///
/// The engine reads the image back as if the fourth channel were alpha and
/// divides the others by it; this undoes that. Texels the pass left empty have
/// a zero half short side, which the readback cannot undo: they come back as
/// far outside (`kLowResFarInward`), which is what they hold.
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

/// The inward edge distance at matte pixel ([x], [y]), as the final shader
/// reads it: the field interpolated bilinearly at that pixel's lattice
/// position. [textureWidth] is the width of the field image, [scale] its
/// lattice spacing.
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

/// The texels of the top-left [width] x [height] lattice of a geometry field
/// image that is [textureWidth] texels wide: what a matte of that size holds,
/// without the rest of a texture that only grows.
Float32List fieldRegion(
  Float32List field,
  int textureWidth,
  int width,
  int height,
) => Float32List.fromList([
  for (var y = 0; y < height; y++)
    ...field.sublist(y * textureWidth * 4, (y * textureWidth + width) * 4),
]);

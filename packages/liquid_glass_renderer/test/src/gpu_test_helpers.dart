import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/internal/flutter_gpu_geometry_renderer.dart';
import 'package:liquid_glass_renderer/src/shaders.dart';

/// Creates a geometry renderer from the shared test shader bundle and
/// disposes it when the test ends.
Future<FlutterGpuGeometryRenderer> createGeometryRenderer() async {
  final renderer = await FlutterGpuGeometryRenderer.fromAsset(
    ShaderKeys.gpuGeometryShaderBundle,
  );
  addTearDown(renderer.dispose);
  return renderer;
}

/// Renders the shared 64x64 rounded-rectangle test fixture and returns the
/// matte image.
ui.Image renderTestRectangle(
  FlutterGpuGeometryRenderer renderer, {
  double centerX = 16,
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
      writeMaterials: writeMaterials,
      appearanceData: appearanceData,
    )
    .image;

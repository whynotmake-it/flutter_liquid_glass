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
    )
    .image;

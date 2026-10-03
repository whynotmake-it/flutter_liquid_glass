import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/app.dart';

void main() {
  debugPaintLiquidGlassGeometry = const bool.fromEnvironment(
    'LIQUID_GLASS_DEBUG_GEOMETRY',
  );
  runApp(const PlaygroundApp());
}

import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/rendering/consolidated_fake_glass_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/geometry_render_link.dart';
import 'package:liquid_glass_renderer/src/widgets/glass_pixel_ratio.dart';
import 'package:meta/meta.dart';

@internal
class ConsolidatedFakeGlassLayer extends SingleChildRenderObjectWidget {
  const ConsolidatedFakeGlassLayer({
    required this.link,
    required this.settings,
    required this.defaultAppearance,
    required this.surfaceShader,
    required this.fieldShader,
    required this.field,
    required super.child,
    super.key,
  });

  final GeometryRenderLink link;
  final LiquidGlassSettings settings;
  final LiquidGlassAppearance defaultAppearance;
  final FragmentShader? surfaceShader;
  final FragmentShader? fieldShader;
  final LiquidGlassField? field;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderConsolidatedFakeGlassLayer(
        devicePixelRatio: glassDevicePixelRatioOf(context),
        link: link,
        settings: settings,
        defaultAppearance: defaultAppearance,
        surfaceShader: surfaceShader,
        fieldShader: fieldShader,
      )..field = field;

  @override
  void updateRenderObject(
    BuildContext context,
    RenderConsolidatedFakeGlassLayer renderObject,
  ) {
    renderObject
      ..devicePixelRatio = glassDevicePixelRatioOf(context)
      ..link = link
      ..settings = settings
      ..defaultAppearance = defaultAppearance
      ..surfaceShader = surfaceShader
      ..fieldShader = fieldShader
      ..field = field;
  }
}

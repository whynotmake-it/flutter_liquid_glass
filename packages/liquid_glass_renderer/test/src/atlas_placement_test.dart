import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/src/rendering/flutter_gpu_geometry_renderer.dart';

import 'gpu_test_helpers.dart';
import 'shared.dart';

void main() {
  testWidgets(
    'an atlas placed as the scene is built fails the frame',
    (tester) async {
      final renderer = (await tester.runAsync(createGeometryRenderer))!;
      renderTestRectangle(renderer);
      await tester.pumpWidget(_PlacesAtlas(renderer));
      if (!kDebugMode) return;
      expect(tester.takeException(), isAssertionError);
      expect(FlutterGpuGeometryRenderer.debugPostFrameFlushCount, 1);
    },
    skip: skipProperGlassTests,
  );
}

final class _PlacesAtlas extends LeafRenderObjectWidget {
  const _PlacesAtlas(this.renderer);

  final FlutterGpuGeometryRenderer renderer;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPlacesAtlas(renderer);
}

final class _RenderPlacesAtlas extends RenderBox {
  _RenderPlacesAtlas(this.renderer);

  final FlutterGpuGeometryRenderer renderer;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  bool get alwaysNeedsCompositing => true;

  @override
  void paint(PaintingContext context, Offset offset) =>
      context.pushLayer(_PlacingLayer(renderer), (_, _) {}, offset);
}

final class _PlacingLayer extends ContainerLayer {
  _PlacingLayer(this.renderer);

  final FlutterGpuGeometryRenderer renderer;

  @override
  void addToScene(ui.SceneBuilder builder) {
    renderTestRectangle(renderer);
    super.addToScene(builder);
  }
}

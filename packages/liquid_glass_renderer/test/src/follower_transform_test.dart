import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/composer/plan_site.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/transform_tracking_render_object_mixin.dart';

import 'shared.dart';

void main() {
  testWidgets('glass under a follower composes where the leader is now', (
    tester,
  ) async {
    final link = LayerLink();
    final left = ValueNotifier<double>(10);
    addTearDown(left.dispose);
    final composed = <Offset>[];
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            ValueListenableBuilder<double>(
              valueListenable: left,
              builder: (_, value, _) => Positioned(
                left: value,
                top: 20,
                child: CompositedTransformTarget(
                  link: link,
                  child: const SizedBox(width: 10, height: 10),
                ),
              ),
            ),
            CompositedTransformFollower(
              link: link,
              offset: const Offset(5, 30),
              child: _Probe(composed),
            ),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(composed.last, const Offset(15, 50));

    left.value = 60;
    await tester.pump();
    expect(composed.last, const Offset(65, 50));
  });

  testWidgets(
    'a shape under a follower moves its matte in the frame its leader moves',
    (tester) async {
      tester.view.physicalSize = const Size(400, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final link = LayerLink();
      final left = ValueNotifier<double>(40);
      addTearDown(left.dispose);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: LiquidGlassLayer(
            settings: settingsWithoutLighting,
            child: Stack(
              children: [
                ValueListenableBuilder<double>(
                  valueListenable: left,
                  builder: (_, value, _) => Positioned(
                    left: value,
                    top: 40,
                    child: CompositedTransformTarget(
                      link: link,
                      child: const SizedBox(width: 10, height: 10),
                    ),
                  ),
                ),
                CompositedTransformFollower(
                  link: link,
                  offset: const Offset(0, 40),
                  child: const LiquidGlass(
                    shape: LiquidRoundedRectangle(borderRadius: 20),
                    child: SizedBox(width: 100, height: 60),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      final layer = tester.allRenderObjects
          .whereType<RenderLiquidGlassLayer>()
          .where((layer) => layer.gpuGeometryRenderer != null)
          .last;
      // Where the retained matte lies in the layer: where it was encoded,
      // shifted by the translation applied while compositing.
      Offset placed() =>
          // ignore: invalid_use_of_protected_member
          layer.encodedGeometryBounds!.topLeft +
          layer.debugCompositorTranslation;
      expect(placed(), const Offset(40, 80));

      left.value = 90;
      // One pump only: a second would hide a frame of lag.
      await tester.pump();
      expect(placed(), const Offset(90, 80));
    },
    skip: skipProperGlassTests,
  );
}

class _Probe extends SingleChildRenderObjectWidget {
  const _Probe(this.composed)
    : super(child: const SizedBox(width: 20, height: 20));

  final List<Offset> composed;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderProbe(composed);
}

class _RenderProbe extends RenderProxyBox
    with TransformTrackingRenderObjectMixin {
  _RenderProbe(this.composed);

  final List<Offset> composed;

  @override
  void onTransformChanged() {}

  @override
  SiteAsk ask() {
    composed.add(MatrixUtils.transformPoint(transformToScreen(), Offset.zero));
    return super.ask();
  }
}

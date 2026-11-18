import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/appearance.dart';
import 'package:liquid_glass_renderer/src/rendering/consolidated_fake_glass_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/frame_shapes.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_blend_group.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/liquid_glass_render_object.dart';
import 'package:liquid_glass_renderer/src/rendering/render_liquid_glass_geometry.dart';
import 'package:material_ui/material_ui.dart';

import 'shared.dart';

const _key = ValueKey('live');
const _view = Size(260, 180);
const _gray = Color(0xFF808080);
const _box = Rect.fromLTWH(20, 30, 220, 120);

const _first = LiquidGlassShapeFrame(
  shape: LiquidRoundedSuperellipse(radius: 20),
);
const _second = LiquidGlassShapeFrame(
  shape: LiquidRoundedSuperellipse(radius: 44),
  appearance: LiquidGlassAppearance.ios27Regular(
    brightness: Brightness.light,
    tint: Color(0x66FF3B30),
  ),
);
const _glow = LiquidGlassGlow(
  center: Offset(90, 90),
  radius: 24,
  gain: 0.6,
  wash: 0.08,
);

Widget _scene({required Widget layer}) => Directionality(
  textDirection: TextDirection.ltr,
  child: Center(
    child: RepaintBoundary(
      key: _key,
      child: SizedBox.fromSize(
        size: _view,
        child: ColoredBox(color: _gray, child: layer),
      ),
    ),
  ),
);

Widget _layer({
  required Widget glass,
  ValueListenable<LiquidGlassLayerFrame>? live,
}) {
  final child = Stack(
    children: [Positioned.fromRect(rect: _box, child: glass)],
  );
  // A paint over a solid color: no backdrop filter, so every render of
  // the process draws.
  const backdrop = LiquidGlassBackdrop.solid(_gray);
  return live == null
      ? LiquidGlassLayer(
          settings: const LiquidGlassSettings.ios27Regular(
            brightness: Brightness.light,
          ),
          backdrop: backdrop,
          child: child,
        )
      : LiquidGlassLayer.live(frame: live, backdrop: backdrop, child: child);
}

Future<Uint8List> _capture(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_key),
  );
  final image = (await tester.runAsync(boundary.toImage))!;
  final bytes = (await tester.runAsync(image.toByteData))!;
  image.dispose();
  return bytes.buffer.asUint8List();
}

void main() {
  setUp(() {
    debugOnRebuildDirtyWidget = null;
  });

  testWidgets('a live shape and layer draw what fixed ones draw, '
      'without rebuilding', (tester) async {
    tester.view
      ..physicalSize = _view
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _scene(
        layer: _layer(
          glass: LiquidGlass(
            shape: _second.shape,
            appearance: _second.appearance,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pump();
    final fixed = await _capture(tester);

    final shape = ValueNotifier(_first);
    final layer = ValueNotifier(
      const LiquidGlassLayerFrame(
        settings: LiquidGlassSettings.ios27Regular(
          brightness: Brightness.light,
        ),
      ),
    );
    addTearDown(shape.dispose);
    addTearDown(layer.dispose);
    await tester.pumpWidget(
      _scene(
        layer: _layer(
          live: layer,
          glass: LiquidGlass.live(
            frame: shape,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pump();

    final rebuilt = <Widget>[];
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      rebuilt.add(element.widget);
    };
    shape.value = _second;
    layer.value = const LiquidGlassLayerFrame(
      settings: LiquidGlassSettings.ios27Regular(brightness: Brightness.light),
    );
    await tester.pump();
    debugOnRebuildDirtyWidget = null;
    final live = await _capture(tester);

    expect(rebuilt, isEmpty);
    var differing = 0;
    for (var i = 0; i < fixed.length; i++) {
      if ((fixed[i] - live[i]).abs() > 1) differing++;
    }
    expect(differing, 0);
  }, skip: skipProperGlassTests);

  testWidgets('a fake live layer draws new settings and a glow without a '
      'rebuild', (tester) async {
    final layer = ValueNotifier(
      const LiquidGlassLayerFrame(
        settings: LiquidGlassSettings.ios27Regular(
          brightness: Brightness.light,
        ),
      ),
    );
    final shape = ValueNotifier(_first);
    addTearDown(layer.dispose);
    addTearDown(shape.dispose);
    await tester.pumpWidget(
      _scene(
        layer: LiquidGlassLayer.live(
          frame: layer,
          fake: true,
          child: Stack(
            children: [
              Positioned.fromRect(
                rect: _box,
                child: LiquidGlass.live(
                  frame: shape,
                  child: const SizedBox.expand(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final rebuilt = <Widget>[];
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      rebuilt.add(element.widget);
    };
    shape.value = LiquidGlassShapeFrame(
      shape: _first.shape,
      appearance: _first.appearance,
      glow: _glow,
    );
    await tester.pump();
    const dark = LiquidGlassSettings.ios27Regular(
      brightness: Brightness.dark,
    );
    layer.value = const LiquidGlassLayerFrame(settings: dark);
    await tester.pump();
    debugOnRebuildDirtyWidget = null;
    expect(rebuilt, isEmpty);
    final fake = tester.allRenderObjects
        .whereType<RenderConsolidatedFakeGlassLayer>()
        .toSet()
        .single;
    expect(fake.settings, dark);
  });

  testWidgets('a fake live layer draws settings that arrive during layout '
      'in the same frame', (tester) async {
    const light = LiquidGlassSettings.ios27Regular(
      brightness: Brightness.light,
    );
    const dark = LiquidGlassSettings.ios27Regular(
      brightness: Brightness.dark,
    );
    final layer = ValueNotifier(const LiquidGlassLayerFrame(settings: light));
    addTearDown(layer.dispose);
    var next = light;
    late StateSetter setInner;
    await tester.pumpWidget(
      _scene(
        layer: LiquidGlassLayer.live(
          frame: layer,
          fake: true,
          child: StatefulBuilder(
            builder: (context, setState) {
              setInner = setState;
              return LayoutBuilder(
                builder: (context, constraints) {
                  layer.value = LiquidGlassLayerFrame(settings: next);
                  return Stack(
                    children: [
                      Positioned.fromRect(
                        rect: _box,
                        child: LiquidGlass(
                          shape: _first.shape,
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    setInner(() => next = dark);
    await tester.pump();
    final fake = tester.allRenderObjects
        .whereType<RenderConsolidatedFakeGlassLayer>()
        .toSet()
        .single;
    expect(fake.settings, dark);
  });

  for (final fake in [true, false]) {
    final kind = fake ? 'fake' : 'real';
    testWidgets('a $kind live layer hands settings that arrive during layout '
        'to every shape in the same frame', (tester) async {
      const light = LiquidGlassSettings.ios27Regular(
        brightness: Brightness.light,
      );
      const dark = LiquidGlassSettings.ios27Regular(
        brightness: Brightness.dark,
      );
      final layer = ValueNotifier(const LiquidGlassLayerFrame(settings: light));
      addTearDown(layer.dispose);
      var next = light;
      late StateSetter setInner;
      await tester.pumpWidget(
        _scene(
          layer: LiquidGlassLayer.live(
            frame: layer,
            fake: fake,
            child: StatefulBuilder(
              builder: (context, setState) {
                setInner = setState;
                return LayoutBuilder(
                  builder: (context, constraints) {
                    layer.value = LiquidGlassLayerFrame(settings: next);
                    return Stack(
                      children: [
                        Positioned.fromRect(
                          rect: const Rect.fromLTWH(20, 30, 100, 60),
                          child: LiquidGlass(
                            shape: _first.shape,
                            child: const SizedBox.expand(),
                          ),
                        ),
                        Positioned.fromRect(
                          rect: const Rect.fromLTWH(20, 100, 220, 60),
                          child: const LiquidGlassBlendGroup(
                            child: Row(
                              children: [
                                Expanded(
                                  child: LiquidGlass(
                                    shape: LiquidOval(),
                                    child: SizedBox.expand(),
                                  ),
                                ),
                                Expanded(
                                  child: LiquidGlass(
                                    shape: LiquidOval(),
                                    child: SizedBox.expand(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();

      setInner(() => next = dark);
      await tester.pump();
      final layers = tester.allRenderObjects
          .whereType<LiquidGlassRenderObject>()
          .toSet();
      expect(
        layers.single,
        fake
            ? isA<RenderConsolidatedFakeGlassLayer>()
            : isA<RenderLiquidGlassLayer>(),
      );
      expect(layers.single.settings, dark);
      final members = tester.allRenderObjects
          .whereType<RenderLiquidGlassGeometry>()
          .toSet();
      expect(members, hasLength(4));
    }, skip: !fake && skipProperGlassTests);
  }

  for (final fake in [true, false]) {
    final kind = fake ? 'fake' : 'real';
    testWidgets('a $kind live layer dresses every shape that sets no '
        "appearance in its frame's default in the same frame", (tester) async {
      const light = LiquidGlassAppearance.ios27Regular(
        brightness: Brightness.light,
      );
      const dark = LiquidGlassAppearance.ios27Regular(
        brightness: Brightness.dark,
      );
      const own = LiquidGlassAppearance.ios27Regular(
        brightness: Brightness.light,
        tint: Color(0x66FF3B30),
      );
      const settings = LiquidGlassSettings.ios27Regular(
        brightness: Brightness.light,
      );
      final layer = ValueNotifier(
        const LiquidGlassLayerFrame(
          settings: settings,
          defaultAppearance: light,
        ),
      );
      addTearDown(layer.dispose);
      await tester.pumpWidget(
        _scene(
          layer: LiquidGlassLayer.live(
            frame: layer,
            fake: fake,
            child: const Stack(
              children: [
                Positioned(
                  left: 20,
                  top: 30,
                  width: 100,
                  height: 60,
                  child: LiquidGlass(
                    shape: LiquidOval(),
                    child: SizedBox.expand(),
                  ),
                ),
                Positioned(
                  left: 130,
                  top: 30,
                  width: 100,
                  height: 60,
                  child: LiquidGlass(
                    shape: LiquidOval(),
                    appearance: own,
                    child: SizedBox.expand(),
                  ),
                ),
                Positioned(
                  left: 20,
                  top: 100,
                  width: 220,
                  height: 60,
                  child: LiquidGlassVisibility(
                    visibility: 0.5,
                    child: LiquidGlassBlendGroup(
                      child: Row(
                        children: [
                          Expanded(
                            child: LiquidGlass(
                              shape: LiquidOval(),
                              child: SizedBox.expand(),
                            ),
                          ),
                          Expanded(
                            child: LiquidGlass(
                              shape: LiquidOval(),
                              child: SizedBox.expand(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      final rebuilt = <Widget>[];
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        rebuilt.add(element.widget);
      };
      layer.value = const LiquidGlassLayerFrame(
        settings: settings,
        defaultAppearance: dark,
      );
      await tester.pump();
      debugOnRebuildDirtyWidget = null;
      expect(rebuilt, isEmpty);

      final drawn = tester.allRenderObjects
          .whereType<LiquidGlassRenderObject>()
          .toSet()
          .single
          .frameShapes
          .drawn;
      expect(drawn, hasLength(4));
      for (final FrameShape(
            :shape,
            committed: CommittedGeometry(:source),
          )
          in drawn) {
        final size = shape.renderObject.paintSize;
        final expected = switch (source) {
          RenderLiquidGlassBlendGroup() => dark.copyWith(visibility: 0.5),
          _ when (shape.renderObject as RenderLiquidGlass).appearance != null =>
            own,
          _ => dark,
        };
        expect(shape.appearance, expected.wear(size));
      }
    }, skip: !fake && skipProperGlassTests);
  }

  testWidgets('a fake live layer shares one backdrop filter from the frame '
      'its default wears the model of its shapes', (tester) async {
    const dark = LiquidGlassAppearance.ios27Regular(
      brightness: Brightness.dark,
    );
    const settings = LiquidGlassSettings.ios27Regular(
      brightness: Brightness.dark,
    );
    final layer = ValueNotifier(
      const LiquidGlassLayerFrame(
        settings: settings,
        defaultAppearance: LiquidGlassAppearance.ios27Regular(
          brightness: Brightness.light,
        ),
      ),
    );
    addTearDown(layer.dispose);
    await tester.pumpWidget(
      _scene(
        layer: LiquidGlassLayer.live(
          frame: layer,
          fake: true,
          child: const Stack(
            children: [
              Positioned(
                left: 20,
                top: 30,
                width: 100,
                height: 60,
                child: LiquidGlass(
                  shape: LiquidOval(),
                  appearance: dark,
                  child: SizedBox.expand(),
                ),
              ),
              Positioned(
                left: 130,
                top: 30,
                width: 100,
                height: 60,
                child: LiquidGlass(
                  shape: LiquidOval(),
                  appearance: dark,
                  child: SizedBox.expand(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final fake = tester.allRenderObjects
        .whereType<RenderConsolidatedFakeGlassLayer>()
        .toSet()
        .single;
    expect(fake.debugSeparateBackdropLayers, hasLength(2));

    layer.value = const LiquidGlassLayerFrame(
      settings: settings,
      defaultAppearance: dark,
    );
    await tester.pump();
    expect(fake.debugSeparateBackdropLayers, isEmpty);
    expect(fake.debugBackdropFilterLayer, isNotNull);
  });

  testWidgets('a fake live layer clips its backdrop to the edge of its '
      'field, and repaints for nothing it does not draw', (tester) async {
    final field = LiquidGlassField.fromPath(
      Path()..addRRect(
        RRect.fromRectAndRadius(_box.deflate(10), const Radius.circular(24)),
      ),
      step: 4,
    );
    const settings = LiquidGlassSettings.ios27Regular(
      brightness: Brightness.light,
    );
    final layer = ValueNotifier(
      LiquidGlassLayerFrame(settings: settings, field: field),
    );
    addTearDown(layer.dispose);
    await tester.pumpWidget(
      _scene(
        layer: LiquidGlassLayer.live(
          frame: layer,
          fake: true,
          child: Stack(
            children: [
              Positioned.fromRect(
                rect: _box,
                child: const LiquidGlass(
                  shape: LiquidRoundedSuperellipse(radius: 20),
                  child: SizedBox.expand(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    final fake = tester.allRenderObjects
        .whereType<RenderConsolidatedFakeGlassLayer>()
        .toSet()
        .single;
    expect(fake.field, field);
    expect(fake.debugClipPath, same(field.edge));

    layer.value = LiquidGlassLayerFrame(
      settings: settings.copyWith(refractionAmount: 99, dispersion: 1),
      field: field,
    );
    expect(fake.debugNeedsPaint, isFalse);
    layer.value = LiquidGlassLayerFrame(
      settings: settings.copyWith(frost: const LiquidGlassFrost.sigma(9)),
      field: field,
    );
    expect(fake.debugNeedsPaint, isTrue);
  });

  testWidgets('a live shape rebuilds when its kind of shape changes', (
    tester,
  ) async {
    final shape = ValueNotifier(_first);
    addTearDown(shape.dispose);
    await tester.pumpWidget(
      _scene(
        layer: _layer(
          glass: LiquidGlass.live(
            frame: shape,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pump();
    shape.value = const LiquidGlassShapeFrame(shape: LiquidOval());
    await tester.pump();
    expect(
      tester.allRenderObjects.whereType<RenderLiquidGlass>().single.shape,
      const LiquidOval(),
    );
    expect(tester.takeException(), isNull);
  }, skip: skipProperGlassTests);
}

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/rendering.dart';
import 'package:material_ui/material_ui.dart';

import 'shared.dart';

const _key = ValueKey('live');
const _view = Size(260, 180);
const _gray = Color(0xFF808080);
const _box = Rect.fromLTWH(20, 30, 220, 120);

const _first = LiquidGlassShapeFrame(
  shape: LiquidRoundedSuperellipse(borderRadius: 20),
);
final _second = LiquidGlassShapeFrame(
  shape: const LiquidRoundedSuperellipse(borderRadius: 44),
  appearance: LiquidGlassAppearance.ios27Regular(
    brightness: Brightness.light,
    tint: const Color(0x66FF3B30),
  ),
);
const _glow = LiquidGlassGlow(
  bounds: _box,
  cornerRadius: 44,
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
  LiquidGlassGlow? glow,
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
          settings: LiquidGlassSettings.ios27RegularLight(),
          backdrop: backdrop,
          glow: glow,
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
          glow: _glow,
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
      LiquidGlassLayerFrame(settings: LiquidGlassSettings.ios27RegularLight()),
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
    layer.value = LiquidGlassLayerFrame(
      settings: LiquidGlassSettings.ios27RegularLight(),
      glow: _glow,
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

  testWidgets('a fake live layer rebuilds for new settings, not for a '
      'glow', (tester) async {
    final layer = ValueNotifier(
      LiquidGlassLayerFrame(settings: LiquidGlassSettings.ios27RegularLight()),
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
                child: LiquidGlass(
                  shape: _first.shape,
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
    layer.value = LiquidGlassLayerFrame(
      settings: LiquidGlassSettings.ios27RegularLight(),
      glow: _glow,
    );
    await tester.pump();
    expect(rebuilt, isEmpty);

    layer.value = LiquidGlassLayerFrame(
      settings: LiquidGlassSettings.ios27RegularDark(),
    );
    await tester.pump();
    debugOnRebuildDirtyWidget = null;
    expect(rebuilt.whereType<LiquidGlassLayer>(), isNotEmpty);
  });

  testWidgets('a fake live layer draws settings that arrive during layout '
      'in the same frame', (tester) async {
    final light = LiquidGlassSettings.ios27RegularLight();
    final dark = LiquidGlassSettings.ios27RegularDark();
    final layer = ValueNotifier(LiquidGlassLayerFrame(settings: light));
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
      final light = LiquidGlassSettings.ios27RegularLight();
      final dark = LiquidGlassSettings.ios27RegularDark();
      final layer = ValueNotifier(LiquidGlassLayerFrame(settings: light));
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
                                  child: LiquidGlass.grouped(
                                    shape: LiquidOval(),
                                    child: SizedBox.expand(),
                                  ),
                                ),
                                Expanded(
                                  child: LiquidGlass.grouped(
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
      expect(members.map((member) => member.settings).toSet(), {dark});
    }, skip: !fake && skipProperGlassTests);
  }

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
      tester.widget<LiquidGlass>(find.byType(LiquidGlass)).shape,
      const LiquidOval(),
    );
    expect(tester.takeException(), isNull);
  }, skip: skipProperGlassTests);
}

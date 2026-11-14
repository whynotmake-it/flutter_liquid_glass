import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/composer/plan_scenery.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_form.dart';
import 'package:liquid_glass_renderer/src/rendering/read.dart';
import 'package:material_ui/material_ui.dart';

import '../shared.dart';
import 'generated_layers.dart';

const _dpr = 2.625;

/// One thing a read could see: a leaf, what it draws, where and under what.
typedef _Seen = (Layer, ui.Picture?, Rect, List<Object?>);

List<Object?> _tokens(StateChain? chain) => [
  for (var at = chain; at != null; at = at.parent) at.token,
];

// What a read at [lead] over [band] holds, worked out from the walk's result
// alone: this keeps the old signature's idea of a frame, so it knows nothing
// of the dirty log it checks.
List<_Seen> _signature(GlassForm form, Layer lead, Rect band) {
  final seen = <_Seen>[];
  final open = <OpenNode>[];
  for (var i = 0; i < form.length; i++) {
    final node = form.nodeAt(i);
    while (open.isNotEmpty && open.last.end <= i) {
      open.removeLast();
    }
    if (identical(node.layer, lead)) break;
    final state = _tokens(open.lastOrNull?.world.state);
    switch (node) {
      case PictureNode(:final picture, :final screen):
        if (!screen.isEmpty && screen.overlaps(band)) {
          seen.add((node.layer, picture, screen, state));
        }
      case VolatileNode(:final screen):
        if (!screen.isEmpty && screen.overlaps(band)) {
          seen.add((node.layer, null, screen, state));
        }
      case OutputNode():
        break;
      case OpenNode():
        open.add(node);
    }
  }
  return seen;
}

bool _same(List<_Seen> a, List<_Seen> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final (leafA, pictureA, rectA, stateA) = a[i];
    final (leafB, pictureB, rectB, stateB) = b[i];
    if (!identical(leafA, leafB) || !identical(pictureA, pictureB)) {
      return false;
    }
    if (rectA != rectB) return false;
    if (stateA.length != stateB.length) return false;
    for (var j = 0; j < stateA.length; j++) {
      if (stateA[j] != stateB[j]) return false;
    }
  }
  return true;
}

int? _orderOf(GlassForm form, Layer layer) {
  for (var i = 0; i < form.length; i++) {
    if (identical(form.nodeAt(i).layer, layer)) return i;
  }
  return null;
}

PictureLayer _picture(Rect rect) {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(rect, Paint());
  final layer = PictureLayer(rect)..picture = recorder.endRecording();
  return layer;
}

void main() {
  group('layers that change places', () {
    const glassKey = ValueKey('glass');
    const pictureKey = ValueKey('picture');

    Widget places({required bool glassFirst}) {
      final glass = KeyedSubtree(
        key: glassKey,
        child: LiquidGlassLayer(
          settings: LiquidGlassSettings.ios27RegularLight(),
          child: const LiquidGlass(
            shape: LiquidRoundedSuperellipse(borderRadius: 28),
            child: SizedBox.expand(),
          ),
        ),
      );
      const picture = RepaintBoundary(
        key: pictureKey,
        child: ColoredBox(color: Color(0xFF80A040), child: SizedBox.expand()),
      );
      return Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          fit: StackFit.expand,
          children: glassFirst ? [glass, picture] : [picture, glass],
        ),
      );
    }

    testWidgets('a held read sees a retained layer that came under it', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      debugGlassCopies = true;
      addTearDown(() => debugGlassCopies = null);

      await tester.pumpWidget(places(glassFirst: true));
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final watch = PlanWatch();
      await tester.pumpWidget(places(glassFirst: false));
      expect(watch.last!.reads.last.changed, isTrue);
    }, skip: skipProperGlassTests);
  });

  testWidgets('a held read sees it when a follower of what it holds leaves', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    debugGlassCopies = true;
    addTearDown(() => debugGlassCopies = null);
    final settings = LiquidGlassSettings.ios27RegularLight();

    Widget glassAt(double left) => Positioned(
      key: ValueKey(left),
      left: left,
      top: 100,
      width: 90,
      height: 60,
      child: LiquidGlassLayer(
        settings: settings,
        child: const LiquidGlass(
          shape: LiquidRoundedSuperellipse(borderRadius: 20),
          child: SizedBox.expand(),
        ),
      ),
    );

    Widget scene({required bool follower}) => Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(size: Size(400, 800)),
        child: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Color(0xFF204060))),
            glassAt(20),
            if (follower) glassAt(130),
            Positioned(
              key: const ValueKey('upper'),
              left: 40,
              top: 130,
              width: 200,
              height: 90,
              child: LiquidGlassLayer(
                settings: settings.copyWith(highlight: 1),
                child: const LiquidGlass(
                  shape: LiquidRoundedSuperellipse(borderRadius: 28),
                  child: SizedBox.expand(),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    await tester.pumpWidget(scene(follower: true));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final watch = PlanWatch();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pumpWidget(scene(follower: true));
    final before = watch.last!;
    expect(before.reads.first.members, hasLength(2));
    expect(before.reads.last.holds, hasLength(1));
    await tester.pumpWidget(scene(follower: false));
    expect(watch.last!.reads.last.changed, isTrue);
  }, skip: skipProperGlassTests);

  testWidgets('a shape that grows under the glass own repaint boundary '
      'shows in the same frame', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    debugGlassCopies = true;
    addTearDown(() => debugGlassCopies = null);
    final width = ValueNotifier<double>(100);
    addTearDown(width.dispose);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(400, 800)),
          child: Stack(
            children: [
              const Positioned.fill(
                child: ColoredBox(color: Color(0xFF204060)),
              ),
              LiquidGlassLayer(
                settings: LiquidGlassSettings.ios27RegularLight(),
                child: RepaintBoundary(
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: ValueListenableBuilder(
                      valueListenable: width,
                      builder: (_, value, _) => SizedBox(
                        width: value,
                        height: 60,
                        child: const LiquidGlass(
                          shape: LiquidRoundedSuperellipse(borderRadius: 20),
                          child: SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final watch = PlanWatch();
    width.value = 200;
    await tester.pump(const Duration(milliseconds: 16));
    final drawn = watch.last!.reads.single.lead.ask.drawn;
    expect(drawn.width, greaterThan(150));
  }, skip: skipProperGlassTests);

  test('what left from just under a read is under it in the log', () {
    const rect = Rect.fromLTWH(0, 0, 100, 100);
    final root = ContainerLayer();
    final gone = _picture(rect);
    final lead = _picture(rect);
    root
      ..append(gone)
      ..append(lead);
    final form = GlassForm()..lower(root, _dpr, GeneratedLayers.screen);
    gone.remove();
    form.lower(root, _dpr, GeneratedLayers.screen);
    expect(form.dirty.meets(_orderOf(form, lead)!, rect), isTrue);
  });

  test('a change under a read is in the log, whatever changed', () {
    for (var seed = 0; seed < 300; seed++) {
      final scene = GeneratedLayers(seed);
      final random = Random(seed);
      final form = GlassForm()..lower(scene.root, _dpr, GeneratedLayers.screen);
      if (form.length == 0) continue;

      Layer pickLead() {
        final at = form.length - 1 - random.nextInt(max(form.length ~/ 3, 1));
        return form.nodeAt(at).layer;
      }

      Rect pickBand() => Rect.fromLTWH(
        random.nextDouble() * 300,
        random.nextDouble() * 800,
        40 + random.nextDouble() * 200,
        40 + random.nextDouble() * 200,
      );

      var lead = pickLead();
      var band = pickBand();
      var held = _signature(form, lead, band);
      for (var step = 0; step < 40; step++) {
        scene.mutate();
        form.lower(scene.root, _dpr, GeneratedLayers.screen);
        final order = _orderOf(form, lead);
        if (order == null) {
          lead = pickLead();
          band = pickBand();
          held = _signature(form, lead, band);
          continue;
        }
        final now = _signature(form, lead, band);
        if (!_same(held, now)) {
          expect(
            form.dirty.meets(order, band),
            isTrue,
            reason:
                'seed $seed step $step: what lies under the read at $order '
                'changed and the log says it held',
          );
        }
        held = now;
      }
    }
  });

  group('glass under glass', () {
    const upperKey = ValueKey('upper');

    Widget scene({
      double left = 40,
      double width = 200,
      double highlight = 0.4,
      double alpha = 1,
      bool lower = true,
    }) {
      final settings = LiquidGlassSettings.ios27RegularLight();
      return Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(400, 800)),
          child: Stack(
            children: [
              const Positioned.fill(
                child: ColoredBox(color: Color(0xFF204060)),
              ),
              if (lower)
                Positioned(
                  left: left,
                  top: 100,
                  width: width,
                  height: 90,
                  child: Opacity(
                    opacity: alpha,
                    child: LiquidGlassLayer(
                      settings: settings.copyWith(highlight: highlight),
                      child: const LiquidGlass(
                        shape: LiquidRoundedSuperellipse(borderRadius: 28),
                        child: SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 60,
                top: 140,
                width: 200,
                height: 90,
                child: RepaintBoundary(
                  child: LiquidGlassLayer(
                    settings: settings,
                    child: const LiquidGlass(
                      key: upperKey,
                      shape: LiquidRoundedSuperellipse(borderRadius: 28),
                      child: SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final changes = <String, Widget>{
      'moves': scene(left: 70),
      'grows': scene(width: 240),
      'shades differently': scene(highlight: 1),
      'fades': scene(alpha: 0.5),
      'fades out': scene(alpha: 0),
      'leaves': scene(lower: false),
    };

    for (final MapEntry(key: what, value: changed) in changes.entries) {
      testWidgets('a held read sees it when the lower glass $what', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        debugGlassCopies = true;
        addTearDown(() => debugGlassCopies = null);

        await tester.pumpWidget(scene());
        for (var i = 0; i < 60; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        final watch = PlanWatch();
        await tester.pumpWidget(changed);
        final upper = tester.renderObject(find.byKey(upperKey)).parent!.parent!;
        final plan = watch.last!;
        final held = plan.reads.last;
        expect(held.changed, isTrue, reason: 'read of $upper');
      }, skip: skipProperGlassTests);
    }
  });
}

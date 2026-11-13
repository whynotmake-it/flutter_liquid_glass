@Tags(['macos_pixels'])
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:material_ui/material_ui.dart';

import 'shared.dart';

const _key = ValueKey('scene');
const _view = Size(300, 220);
const _gray = Color(0xFF808080);
const _shape = LiquidRoundedSuperellipse(borderRadius: 24);

// The box the live glass is laid out in, and where its frame draws it.
const _box = Rect.fromLTWH(20, 20, 160, 100);
const _drawn = Rect.fromLTWH(90, 70, 190, 120);

Widget _scene({required Widget glass, required Rect at, bool fake = false}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: RepaintBoundary(
          key: _key,
          child: SizedBox.fromSize(
            size: _view,
            child: ColoredBox(
              color: _gray,
              child: LiquidGlassLayer(
                settings: LiquidGlassSettings.ios27RegularLight(),
                backdrop: const LiquidGlassBackdrop.solid(_gray),
                fake: fake,
                child: Stack(
                  children: [Positioned.fromRect(rect: at, child: glass)],
                ),
              ),
            ),
          ),
        ),
      ),
    );

// Content pinned to the top left, so it shows where the child is drawn.
const _content = Align(
  alignment: Alignment.topLeft,
  child: SizedBox.square(
    dimension: 30,
    child: ColoredBox(color: Color(0xFFFF3B30)),
  ),
);

Future<Uint8List> _capture(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_key),
  );
  final image = (await tester.runAsync(boundary.toImage))!;
  final bytes = (await tester.runAsync(image.toByteData))!;
  image.dispose();
  return bytes.buffer.asUint8List();
}

int _differing(Uint8List a, Uint8List b) {
  var differing = 0;
  for (var i = 0; i < a.length; i++) {
    if ((a[i] - b[i]).abs() > 1) differing++;
  }
  return differing;
}

List<RenderObject> _subtree(RenderObject root) {
  final all = <RenderObject>[root];
  void visit(RenderObject child) {
    all.add(child);
    child.visitChildren(visit);
  }

  root.visitChildren(visit);
  return all;
}

Future<void> _drawsWhereFixedGlassDoes(
  WidgetTester tester, {
  required bool fake,
  double scaleX = 1,
  double scaleY = 1,
}) async {
  tester.view
    ..physicalSize = _view
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final scaled = scaleX != 1 || scaleY != 1;
  const fixedGlass = LiquidGlass(shape: _shape, child: _content);
  await tester.pumpWidget(
    _scene(
      fake: fake,
      at: _drawn,
      glass: scaled
          ? Transform(
              alignment: Alignment.center,
              transform: Matrix4.diagonal3Values(scaleX, scaleY, 1),
              child: fixedGlass,
            )
          : fixedGlass,
    ),
  );
  await tester.pump();
  final fixed = await _capture(tester);

  final frame = ValueNotifier(const LiquidGlassShapeFrame(shape: _shape));
  addTearDown(frame.dispose);
  await tester.pumpWidget(
    _scene(
      fake: fake,
      at: _box,
      glass: LiquidGlass.live(frame: frame, child: _content),
    ),
  );
  await tester.pump();

  final rebuilt = <Widget>[];
  debugOnRebuildDirtyWidget = (element, builtOnce) {
    rebuilt.add(element.widget);
  };
  addTearDown(() => debugOnRebuildDirtyWidget = null);
  frame.value = LiquidGlassShapeFrame(
    shape: _shape,
    rect: _drawn.shift(-_box.topLeft),
    scaleX: scaleX,
    scaleY: scaleY,
  );
  final glass = tester.renderObject(find.byType(LiquidGlass));
  expect(
    _subtree(glass).where((object) => object.debugNeedsLayout),
    isEmpty,
  );
  await tester.pump();
  debugOnRebuildDirtyWidget = null;

  expect(rebuilt, isEmpty);
  expect(_differing(fixed, await _capture(tester)), 0);
}

void main() {
  testWidgets('a live frame moves and resizes glass and child at paint', (
    tester,
  ) async {
    await _drawsWhereFixedGlassDoes(tester, fake: false);
  }, skip: skipProperGlassTests);

  testWidgets('a live frame moves and resizes fake glass at paint', (
    tester,
  ) async {
    await _drawsWhereFixedGlassDoes(tester, fake: true);
  }, skip: skipProperGlassTests);

  testWidgets('a live frame scales glass and child about the rect center', (
    tester,
  ) async {
    await _drawsWhereFixedGlassDoes(
      tester,
      fake: false,
      scaleX: 1.2,
      scaleY: 0.8,
    );
  }, skip: skipProperGlassTests);

  testWidgets('a live frame scales fake glass about the rect center', (
    tester,
  ) async {
    await _drawsWhereFixedGlassDoes(
      tester,
      fake: true,
      scaleX: 1.2,
      scaleY: 0.8,
    );
  }, skip: skipProperGlassTests);

  testWidgets('a live frame writes shape, appearance and shadows into fake '
      'glass without rebuilding', (tester) async {
    tester.view
      ..physicalSize = _view
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const after = LiquidRoundedSuperellipse(borderRadius: 44);
    final tinted = LiquidGlassAppearance.ios27Regular(
      brightness: Brightness.light,
      tint: const Color(0x66FF3B30),
    );
    const shadows = [BoxShadow(color: Color(0x40000000), blurRadius: 12)];
    await tester.pumpWidget(
      _scene(
        fake: true,
        at: _drawn,
        glass: LiquidGlass(
          shape: after,
          appearance: tinted,
          shadows: shadows,
          child: _content,
        ),
      ),
    );
    await tester.pump();
    final fixed = await _capture(tester);

    final frame = ValueNotifier(
      const LiquidGlassShapeFrame(
        shape: _shape,
        shadows: [BoxShadow(color: Color(0x20000000), blurRadius: 4)],
      ),
    );
    addTearDown(frame.dispose);
    await tester.pumpWidget(
      _scene(
        fake: true,
        at: _drawn,
        glass: LiquidGlass.live(frame: frame, child: _content),
      ),
    );
    await tester.pump();

    final rebuilt = <Widget>[];
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      rebuilt.add(element.widget);
    };
    addTearDown(() => debugOnRebuildDirtyWidget = null);
    frame.value = LiquidGlassShapeFrame(
      shape: after,
      appearance: tinted,
      shadows: shadows,
    );
    await tester.pump();
    debugOnRebuildDirtyWidget = null;

    expect(rebuilt, isEmpty);
    expect(_differing(fixed, await _capture(tester)), 0);
  }, skip: skipProperGlassTests);

  testWidgets('a grouped live shape draws at its frame rect', (tester) async {
    tester.view
      ..physicalSize = _view
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Widget grouped(Widget glass, Rect at) => _scene(
      at: Offset.zero & _view,
      glass: LiquidGlassBlendGroup(
        child: Stack(
          children: [Positioned.fromRect(rect: at, child: glass)],
        ),
      ),
    );

    await tester.pumpWidget(
      grouped(
        const LiquidGlass.grouped(shape: _shape, child: _content),
        _drawn,
      ),
    );
    await tester.pump();
    final fixed = await _capture(tester);

    final frame = ValueNotifier(const LiquidGlassShapeFrame(shape: _shape));
    addTearDown(frame.dispose);
    await tester.pumpWidget(
      grouped(
        LiquidGlass.live(frame: frame, grouped: true, child: _content),
        _box,
      ),
    );
    await tester.pump();
    frame.value = LiquidGlassShapeFrame(
      shape: _shape,
      rect: _drawn.shift(-_box.topLeft),
    );
    await tester.pump();

    expect(_differing(fixed, await _capture(tester)), 0);
  }, skip: skipProperGlassTests);

  testWidgets('a live glass is hit where it was laid out', (tester) async {
    tester.view
      ..physicalSize = _view
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var taps = 0;
    final frame = ValueNotifier(
      LiquidGlassShapeFrame(
        shape: _shape,
        rect: _drawn.shift(-_box.topLeft),
      ),
    );
    addTearDown(frame.dispose);
    await tester.pumpWidget(
      _scene(
        at: _box,
        glass: LiquidGlass.live(
          frame: frame,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    final origin = tester.getTopLeft(find.byKey(_key));

    await tester.tapAt(origin + const Offset(60, 50));
    expect(taps, 1);
    await tester.tapAt(origin + const Offset(260, 180));
    expect(taps, 1);
  });
}

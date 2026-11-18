import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

// Run with `flutter test --enable-impeller --enable-flutter-gpu`: the glass
// shades its outline's field, which only Impeller's compositor draws.
const _key = ValueKey('page');
const _width = 300;

final _shape = PopoverShape(
  content: const Rect.fromLTWH(0, 0, 240, 120),
  direction: PopoverArrowDirection.down,
  arrowCenter: 120,
  cornerRadius: 34,
);

Widget _page(GlassRenderer renderer, GlassFrame frame) => Directionality(
  textDirection: TextDirection.ltr,
  child: GlassScope(
    renderer: renderer,
    child: Align(
      alignment: Alignment.topLeft,
      child: RepaintBoundary(
        key: _key,
        child: SizedBox(
          width: 300,
          height: 200,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFFFFFF), Color(0xFFFF0000)],
                stops: [0.75, 0.75],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(30),
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox.fromSize(
                  size: _shape.bounds.size,
                  child: GlassSurface.live(
                    role: GlassRole.panel,
                    frame: MotionSelection(() => frame),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  ),
);

Future<Uint8List> _capture(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_key));
  final image = (await tester.runAsync(boundary.toImage))!;
  final bytes = (await tester.runAsync(image.toByteData))!;
  image.dispose();
  return bytes.buffer.asUint8List();
}

List<int> _pixel(Uint8List bytes, int x, int y) {
  final i = (y * _width + x) * 4;
  return bytes.sublist(i, i + 3);
}

void main() {
  setUp(MotionClock.debugReset);
  setUpAll(precacheLiquidGlass);

  for (final (name, renderer, shaded) in [
    ('liquid', const LiquidGlassRenderer(), true),
    ('flat', const FlatGlassRenderer(), false),
  ]) {
    testWidgets('the $name popover draws its arrow as part of its body', (
      tester,
    ) async {
      // flutter_tester places backdrop glass right at a ratio of 1 only.
      tester.view.physicalSize = const Size(300, 200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _page(renderer, GlassFrame(outline: _shape.outline)),
      );
      await tester.pump();
      final bytes = await _capture(tester);
      // The page is white down to the content's bottom edge at 150 and red
      // below, where the arrow hangs around x = 150: glass there bends the
      // white in or fills it, and the red beside and below stays red.
      final arrow = _pixel(bytes, 150, 158);
      final beside = _pixel(bytes, 120, 158);
      final below = _pixel(bytes, 150, 190);
      expect(arrow[1], greaterThan(150), reason: 'the arrow: $arrow');
      expect(beside[1], lessThan(20), reason: 'beside the arrow: $beside');
      expect(below[1], lessThan(20), reason: 'below the tip: $below');
    }, skip: shaded && !ui.ImageFilter.isShaderFilterSupported);
  }
}

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

// Run with `flutter test --enable-impeller --enable-flutter-gpu`: the liquid
// glass only draws under Impeller's compositor.
const _key = ValueKey('page');
const _width = 402;
const _height = 120;
const _red = Color(0xFFFF0000);
const _green = Color(0xFF00FF00);

Widget _icon(String name) => SizedBox.square(
  key: ValueKey(name),
  dimension: 12,
  child: const ColoredBox(color: _green),
);

GlassBarItem _item(String name) => GlassBarItem(
  icon: _icon(name),
  semanticLabel: name,
  onPressed: () {},
);

Widget _page(GlassRenderer renderer, List<GlassBarEntry> items) => MediaQuery(
  data: const MediaQueryData(size: Size(402, 120)),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: GlassScope(
      renderer: renderer,
      child: RepaintBoundary(
        key: _key,
        child: ColoredBox(
          color: _red,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: GlassToolbar(items: items),
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

bool _isRed(Uint8List bytes, int x, int y) {
  final i = (y * _width + x) * 4;
  return bytes[i] > 240 && bytes[i + 1] < 15 && bytes[i + 2] < 15;
}

bool _isGreen(Uint8List bytes, int x, int y) {
  final i = (y * _width + x) * 4;
  return bytes[i] < 40 && bytes[i + 1] > 200 && bytes[i + 2] < 40;
}

// The drawn icons, left to right, as the centers of their green runs on
// the row that crosses the most of them.
List<Offset> _icons(Uint8List bytes) {
  var found = <Offset>[];
  for (var y = 0; y < _height; y++) {
    final row = <Offset>[];
    var start = -1;
    for (var x = 0; x <= _width; x++) {
      final green = x < _width && _isGreen(bytes, x, y);
      if (green && start < 0) start = x;
      if (!green && start >= 0) {
        if (x - start >= 3) row.add(Offset((start + x) / 2, y.toDouble()));
        start = -1;
      }
    }
    if (row.length > found.length) found = row;
  }
  return found;
}

// The glass around [icon] along its row: from the last red pixel on its
// left to the first red pixel on its right.
(int, int) _glassAround(Uint8List bytes, Offset icon) {
  final y = icon.dy.round();
  var left = icon.dx.round();
  while (left > 0 && !_isRed(bytes, left - 1, y)) {
    left--;
  }
  var right = icon.dx.round();
  while (right < _width - 1 && !_isRed(bytes, right + 1, y)) {
    right++;
  }
  return (left, right);
}

void main() {
  setUp(MotionClock.debugReset);
  setUpAll(precacheLiquidGlass);

  for (final (name, renderer, shaded) in [
    ('liquid', const LiquidGlassRenderer(), true),
    ('flat', const FlatGlassRenderer(), false),
  ]) {
    testWidgets('on the $name glass an item that joins a capsule draws '
        'inside the glass on every frame of the change', (tester) async {
      // flutter_tester places backdrop glass right at a ratio of 1 only.
      tester.view.physicalSize = const Size(402, 120);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_page(renderer, [_item('a')]));
      await tester.pump();
      final before = _icons(await _capture(tester));
      expect(before, hasLength(1));

      await tester.pumpWidget(_page(renderer, [_item('a'), _item('b')]));
      final drawn = <List<Offset>>[];
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final bytes = await _capture(tester);
        final icons = _icons(bytes);
        drawn.add(icons);
        for (final icon in icons) {
          final (left, right) = _glassAround(bytes, icon);
          expect(
            right - left,
            greaterThan(20),
            reason: 'frame $i: the icon at $icon has glass $left..$right',
          );
          expect(
            left < icon.dx - 6 && right > icon.dx + 6,
            isTrue,
            reason: 'frame $i: the icon at $icon has glass $left..$right',
          );
        }
      }
      expect(drawn.last, hasLength(2));
      final joining = [
        for (final icons in drawn)
          if (icons.length == 2) icons.last.dx,
      ];
      expect(
        joining.last - joining.first,
        greaterThan(2),
        reason: 'the new item moves into its place',
      );
    }, skip: shaded && !ui.ImageFilter.isShaderFilterSupported);
  }
}
